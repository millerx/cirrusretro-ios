#include "cirrus_nsf.h"
#include <stdio.h>

/* At link time the Linux test redirects the static engine's realloc calls.
   Exercise each fresh buffer allocation during a normal NSF open, including
   Nsf_Emu::init_sound's voice names. Shrinks can legitimately be optional. */
static unsigned allocations;
static unsigned fail_at;
static int injected;

void *__real_realloc(void *, size_t);
void *__wrap_realloc(void *p, size_t size)
{
    if (!p && size && ++allocations == fail_at) {
        injected = 1;
        return NULL;
    }
    return __real_realloc(p, size);
}

int main(int argc, char **argv)
{
    uint8_t bytes[512];
    FILE *in = argc == 2 ? fopen(argv[1], "rb") : NULL;
    if (!in)
        return 1;
    size_t size = fread(bytes, 1, sizeof bytes, in);
    if (!feof(in) || fclose(in))
        return 1;

    cr_nsf *control = NULL;
    if (cr_nsf_open(bytes, size, &control) || !control || allocations == 0)
        return 1;
    unsigned count = allocations;
    for (fail_at = 1; fail_at <= count; ++fail_at) {
        allocations = 0;
        injected = 0;
        cr_nsf *out = control; /* failure must overwrite a non-null sentinel */
        const char *error = cr_nsf_open(bytes, size, &out);
        if (!injected || !error || out) {
            fprintf(stderr, "allocation %u/%u did not propagate an open error\n", fail_at, count);
            return 1;
        }
    }
    cr_nsf_close(control);
    fail_at = 0;
    cr_nsf *retry = NULL;
    if (cr_nsf_open(bytes, size, &retry) || !retry)
        return 1;
    cr_nsf_close(retry);
    printf("verified %u required allocations and successful retry\n", count);
    return 0;
}
