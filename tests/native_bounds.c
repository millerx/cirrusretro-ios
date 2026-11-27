#define _POSIX_C_SOURCE 200809L
#include "cirrus_nsf.h"
#include "PCMQueue.h"
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "failed at line %d\n", __LINE__); return 1; } } while (0)

int main(int argc, char **argv)
{
    CRPCMQueue q;
    cr_queue_init(&q);
    // Force both unsigned counters to wrap while audio remains buffered.
    atomic_store(&q.read, UINT_MAX - 10);
    atomic_store(&q.written, UINT_MAX - 10);
    int16_t pcm[CR_QUEUE_FRAMES * 2];
    for (unsigned i = 0; i < CR_QUEUE_FRAMES; ++i) {
        pcm[2*i] = (int16_t)i;
        pcm[2*i+1] = (int16_t)-(int)i;
    }
    cr_queue_write(&q, pcm, CR_QUEUE_FRAMES);
    REQUIRE(cr_queue_space(&q) == 0);
    float left[CR_QUEUE_FRAMES], right[CR_QUEUE_FRAMES];
    REQUIRE(cr_queue_read(&q, left, right, 17) == 17);
    REQUIRE(cr_queue_space(&q) == 17);
    REQUIRE(cr_queue_read(&q, left, right, CR_QUEUE_FRAMES) == CR_QUEUE_FRAMES - 17);
    for (unsigned i = 0; i < CR_QUEUE_FRAMES; ++i) {
        float expected = i + 17 < CR_QUEUE_FRAMES ? (i + 17) / 32768.0f : 0.0f;
        REQUIRE(left[i] == expected && right[i] == -expected);
    }

    REQUIRE(argc == 2);
    FILE *f = fopen(argv[1], "rb");
    REQUIRE(f);
    uint8_t bytes[512];
    size_t n = fread(bytes, 1, sizeof bytes, f);
    REQUIRE(feof(f) && fclose(f) == 0);
    // The 1 us play period drives many short CPU dispatches in one GME quantum.
    bytes[110] = 1;
    bytes[111] = 0;
    cr_nsf *nsf = NULL;
    REQUIRE(!cr_nsf_open(bytes, n, &nsf));
    REQUIRE(!cr_nsf_select(nsf, 0));
    struct timespec start, end;
    REQUIRE(!clock_gettime(CLOCK_MONOTONIC, &start));
    REQUIRE(cr_nsf_render(nsf, pcm, CR_BLOCK_FRAMES));
    REQUIRE(!clock_gettime(CLOCK_MONOTONIC, &end));
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    printf("512-frame guest budget rejection: %.3f ms\n", elapsed * 1000);
    REQUIRE(elapsed < 1.0);
    REQUIRE(cr_nsf_render(nsf, pcm, CR_BLOCK_FRAMES));
    cr_nsf_close(nsf);
    return 0;
}
