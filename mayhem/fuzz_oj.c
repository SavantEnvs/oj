#include "oj_embed.h"

#include OJ_LAMBDA_INC

int LLVMFuzzerInitialize(int *argc, char ***argv) {
    (void)argc;
    (void)argv;
    oj_embed_init(oj_lambda_src);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    oj_embed_run(data, size);
    return 0;
}
