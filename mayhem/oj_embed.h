// Embeds the Ruby VM in a fuzz harness and links Oj's C extension in statically, so the sanitized,
// coverage-instrumented Oj code is what the fuzzer drives. Each harness supplies a Ruby lambda
// (mayhem/<target>.rb); a fuzz input becomes its String argument.
#include <ruby.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

extern void *__libc_stack_end;
extern void Init_oj(void);

static VALUE oj_fuzz_proc = Qnil;
static ID oj_id_call;

static VALUE oj_embed_boot(VALUE src) {
    (void)src;
    rb_require("stringio");
    // Oj itself is linked in: satisfy `require 'oj/oj'` from lib/oj.rb instead of loading a .so.
    Init_oj();
    rb_provide("oj/oj.so");
    rb_require("oj");
    return Qnil;
}

static VALUE oj_embed_eval(VALUE code) {
    return rb_eval_string((const char *)code);
}

static void oj_embed_init(const char *lambda_src) {
    struct sigaction saved[NSIG];
    for (int s = 1; s < NSIG; s++) {
        if (sigaction(s, NULL, &saved[s]) != 0) {
            saved[s].sa_handler = SIG_DFL;
        }
    }
    // The fuzzed process, not Ruby, must own crash signals so ASan/libFuzzer reports reach Mayhem.
    ruby_init_stack((VALUE *)__libc_stack_end);
    ruby_init();
    ruby_init_loadpath();
    for (int s = 1; s < NSIG; s++) {
        if (s == SIGKILL || s == SIGSTOP) {
            continue;
        }
        sigaction(s, &saved[s], NULL);
    }

    const char *src = getenv("SRC");
    char libdir[4096];
    snprintf(libdir, sizeof libdir, "%s/lib", src && *src ? src : "/mayhem");
    ruby_incpush(libdir);

    int state = 0;
    rb_protect(oj_embed_boot, Qnil, &state);
    if (state) {
        rb_p(rb_errinfo());
        abort();
    }
    oj_fuzz_proc = rb_protect(oj_embed_eval, (VALUE)lambda_src, &state);
    if (state) {
        rb_p(rb_errinfo());
        abort();
    }
    rb_gc_register_address(&oj_fuzz_proc);
    oj_id_call = rb_intern("call");
}

struct oj_call_args {
    VALUE arg;
};

static VALUE oj_embed_call(VALUE a) {
    return rb_funcall(oj_fuzz_proc, oj_id_call, 1, ((struct oj_call_args *)a)->arg);
}

static void oj_embed_run(const uint8_t *data, size_t size) {
    struct oj_call_args args;
    args.arg = rb_utf8_str_new((const char *)data, (long)size);
    int state = 0;
    rb_protect(oj_embed_call, (VALUE)&args, &state);
    if (state) {
        rb_set_errinfo(Qnil);
    }
}
