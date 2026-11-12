// A ruby interpreter with Oj's C extension linked in, built with the project's normal flags.
// test.sh runs upstream's minitest suite through it, so the assertions exercise the exact C
// sources a patch edits (no separately compiled oj.so to go stale).
#include <ruby.h>
#include <stdio.h>

extern void Init_oj(void);

static VALUE boot(VALUE unused) {
    (void)unused;
    Init_oj();
    rb_provide("oj/oj.so");
    // Tests that spawn RbConfig.ruby must get this interpreter, the only one that has Oj.
    rb_require("rbconfig");
    rb_eval_string(
        "exe = File.realpath('/proc/self/exe')\n"
        "RbConfig::CONFIG['bindir'] = File.dirname(exe)\n"
        "RbConfig::CONFIG['ruby_install_name'] = File.basename(exe)\n"
        "RbConfig::CONFIG['RUBY_INSTALL_NAME'] = File.basename(exe)\n"
        "RbConfig::CONFIG['EXEEXT'] = ''\n");
    return Qnil;
}

int main(int argc, char **argv) {
    ruby_sysinit(&argc, &argv);
    {
        RUBY_INIT_STACK;
        ruby_init();
        void *node = ruby_options(argc, argv);
        int state = 0;
        // After option processing so -I paths and rubygems are in place when Init_oj requires lib/oj/*.rb.
        rb_protect(boot, Qnil, &state);
        if (state) {
            rb_p(rb_errinfo());
            return 1;
        }
        return ruby_run_node(node);
    }
}
