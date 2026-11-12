#!/usr/bin/env bash
#
# mayhem/build.sh — build Oj's C extension + the Ruby VM it needs into
#   (a) five sanitized libFuzzer harnesses (+ -standalone reproducers), and
#   (b) /mayhem/oj_ruby, a ruby interpreter with Oj linked in (project's NORMAL flags) that test.sh
#       runs upstream's minitest suite through.
# Oj is a Ruby C extension, so there is no standalone library to link: the harnesses embed libruby
# (apt ruby3.3, installed by the Dockerfile) and compile ext/oj/*.c straight into the binary.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

TARGETS="fuzz_load fuzz_dump fuzz_doc fuzz_parser fuzz_saj"
GEN="$SRC/tmp/mayhem-gen"
FOBJ="$SRC/tmp/mayhem-obj-fuzz"
TOBJ="$SRC/tmp/mayhem-obj-test"
mkdir -p "$GEN" "$FOBJ" "$TOBJ"

rbconf() { ruby -rrbconfig -e "print RbConfig::CONFIG['$1']"; }
RUBY_HDR="$(rbconf rubyhdrdir)"
RUBY_ARCH_HDR="$(rbconf rubyarchhdrdir)"
RUBY_LIBDIR="$(rbconf libdir)"
RUBY_SOLIB="$(rbconf RUBY_SO_NAME)"
read -r RV_MAJOR RV_MINOR RV_MICRO <<<"$(ruby -e 'puts RUBY_VERSION.split(".").join(" ")')"
RV="$RV_MAJOR.$RV_MINOR.$RV_MICRO"

# The -D set ext/oj/extconf.rb would pass for this Ruby (mkmf's have_func results are recorded here
# as constants, since the sources are compiled directly rather than through its Makefile).
OJ_DEFS=(
  -DRUBY_TYPE=ruby -DRUBY_RUBY -DRUBY_VERSION="$RV" -DRUBY_VERSION_MAJOR="$RV_MAJOR"
  -DRUBY_VERSION_MINOR="$RV_MINOR" -DRUBY_VERSION_MICRO="$RV_MICRO" -DIS_WINDOWS=0
  -DRSTRUCT_LEN_RETURNS_INTEGER_OBJECT=0
  -DHAVE_RB_GC_MARK_MOVABLE -DHAVE_STPCPY -DHAVE_PTHREAD_MUTEX_INIT -DHAVE_GETRLIMIT
  -DHAVE_RB_ENC_INTERNED_STR -DHAVE_RB_HASH_NEW_CAPA -DHAVE_RB_EXT_RACTOR_SAFE
)
INCS=(-I"$SRC/ext/oj" -I"$RUBY_HDR" -I"$RUBY_ARCH_HDR")
LIBS=(-L"$RUBY_LIBDIR" -l"$RUBY_SOLIB" -lm -lpthread)

OJ_SRCS=("$SRC"/ext/oj/*.c)

# compile_set <objdir> <flags...>: every ext/oj/*.c -> <objdir>/<name>.o, in parallel.
compile_set() {
  local dir="$1"; shift
  printf '%s\n' "${OJ_SRCS[@]}" | xargs -P "$MAYHEM_JOBS" -I{} bash -c '
    f="$1"; dir="$2"; shift 2
    "$@" -c "$f" -o "$dir/$(basename "${f%.c}").o"' _ {} "$dir" \
    "$CC" "$@" "${OJ_DEFS[@]}" "${INCS[@]}"
}

# 1) Sanitized + coverage-instrumented Oj for the fuzz harnesses. The C sources are compiled with
#    ASan+UBSan (halting) and SanCov; libruby (apt, uninstrumented) is only the runtime.
#    use-after-return is off because Ruby's GC conservatively scans the machine stack, and ASan's
#    fake stack would hide live VALUEs from it.
#    Three UBSan checks are relaxed because Oj trips them on routine input, which would end every
#    run at the first long digit string / large float / '+' token and hide everything deeper:
#    signed-integer-overflow (parse.c: ni.i * 10 + d over 19+ digits, before its own bignum fallback),
#    float-cast-overflow (dump*.c: d == (double)(long long)d for |d| >= 2^63), pointer-overflow
#    (sparse.c: pi->cur-- on a '+' token at the start of the buffer). ASan and all other checks halt.
FUZZ_CFLAGS=($SANITIZER_FLAGS $DEBUG_FLAGS -fno-sanitize=signed-integer-overflow,float-cast-overflow,pointer-overflow -fsanitize=fuzzer-no-link -fsanitize-address-use-after-return=never
             -O1 -fno-omit-frame-pointer -fno-fast-math -std=gnu99 -msse2)
compile_set "$FOBJ" "${FUZZ_CFLAGS[@]}"

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FOBJ/lsan_off.o"

# Ruby source of each target -> a C string literal, #included by the shared harness.
for t in $TARGETS; do
  { printf 'static const char oj_lambda_src[] =\n'
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/\\n"/' "$SRC/mayhem/$t/$t.rb"
    printf ';\n'; } > "$GEN/$t.inc"
done

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FOBJ/standalone_main.o"

for t in $TARGETS; do
  $CC "${FUZZ_CFLAGS[@]}" "${INCS[@]}" -I"$SRC/mayhem" -I"$GEN" -DOJ_LAMBDA_INC="\"$t.inc\"" \
      -c "$SRC/mayhem/fuzz_oj.c" -o "$FOBJ/$t.harness.o"
  objs=("$FOBJ"/*.o)
  objs=("${objs[@]##*/}")
  keep=()
  for o in "${objs[@]}"; do
    case "$o" in *.harness.o|standalone_main.o) ;; *) keep+=("$FOBJ/$o") ;; esac
  done
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FOBJ/$t.harness.o" "${keep[@]}" "${LIBS[@]}" -o "/mayhem/$t"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$FOBJ/standalone_main.o" "$FOBJ/$t.harness.o" "${keep[@]}" "${LIBS[@]}" -o "/mayhem/$t-standalone"
done

# 2) The oracle interpreter: same sources, the project's normal flags (no sanitizer, no -gdwarf-3).
# __FILE__ is made relative ("saj.c") as under upstream's own extconf build: test_saj matches it.
TEST_CFLAGS=(-O2 -fno-fast-math -Wall -std=gnu99 -msse2 -fmacro-prefix-map="$SRC/ext/oj/=" $COVERAGE_FLAGS)
compile_set "$TOBJ" "${TEST_CFLAGS[@]}"
$CC "${TEST_CFLAGS[@]}" "${INCS[@]}" -c "$SRC/mayhem/oj_ruby_main.c" -o "$TOBJ/oj_ruby_main.o"
$CC $COVERAGE_FLAGS "$TOBJ"/*.o "${LIBS[@]}" -o /mayhem/oj_ruby
