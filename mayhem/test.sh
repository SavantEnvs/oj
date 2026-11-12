#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Upstream's own minitest suite, run through /mayhem/oj_ruby (a ruby with Oj's C sources linked in,
# built by build.sh with the project's normal flags). One process per test file; each prints a
# minitest summary line "N runs, N assertions, N failures, N errors, N skips".
RUBY_BIN=/mayhem/oj_ruby
[ -x "$RUBY_BIN" ] || { echo "missing $RUBY_BIN: mayhem/build.sh did not produce it" >&2; exit 1; }

TEST_FILES="test_compat test_custom test_fast test_file test_gc test_hash test_null test_object
  test_parser_safe test_saj test_scp test_strict test_rails test_wab test_writer test_integer_range
  test_long_strings test_max_integer_digits test_various test_parser test_parser_usual test_parser_saj
  test_generate test_ostruct test_to_json_json_gem"

passed=0 ; failed=0 ; skipped=0
cd "$SRC/test"
for f in $TEST_FILES; do
  out="$(timeout 600 "$RUBY_BIN" -I ../lib -I ../ext -I . "$f.rb" 2>&1)" ; rc=$?
  summary="$(printf '%s\n' "$out" | grep -E '^[0-9]+ runs, [0-9]+ assertions, ' | tail -n1)"
  if [ -z "$summary" ]; then
    printf '%s\n' "$out" | tail -n 20
    echo "$f: no minitest summary (rc=$rc)" >&2
    failed=$((failed + 1)) ; continue
  fi
  runs=$(sed -E 's/^([0-9]+) runs.*/\1/' <<<"$summary")
  fl=$(sed -E 's/.* ([0-9]+) failures.*/\1/' <<<"$summary")
  er=$(sed -E 's/.* ([0-9]+) errors.*/\1/' <<<"$summary")
  sk=$(sed -E 's/.* ([0-9]+) skips.*/\1/' <<<"$summary")
  [ "$runs" -gt 0 ] || { echo "$f: ran 0 tests" >&2 ; failed=$((failed + 1)) ; continue; }
  echo "$f: $summary"
  if [ "$fl" -gt 0 ] || [ "$er" -gt 0 ]; then printf '%s\n' "$out" | tail -n 40; fi
  failed=$((failed + fl + er)) ; skipped=$((skipped + sk))
  passed=$((passed + runs - fl - er - sk))
done

emit_ctrf "minitest (oj)" "$passed" "$failed" "$skipped"
