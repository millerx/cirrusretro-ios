#include "cirrus_nsf.h"
#include <stdio.h>
#include <string.h>

#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "line %d failed: %s\n", __LINE__, #expr); return 1; \
} } while (0)

int main(int argc, char **argv)
{
    CHECK(argc == 2);
    FILE *in = fopen(argv[1], "rb");
    CHECK(in);
    uint8_t data[512];
    size_t size = fread(data, 1, sizeof data, in);
    CHECK(feof(in) && fclose(in) == 0);
    cr_nsf *nsf = NULL;
    cr_nsf_info info;
    int16_t first[2048], replay[2048];
    CHECK(cr_nsf_open(NULL, 0, &nsf) && !nsf);
    CHECK(cr_nsf_open(data, CR_NSF_MAX_BYTES + 1, &nsf) && !nsf);
    CHECK(cr_nsf_open(data, size, NULL));
    memset(data + 78, 'a', 32); /* Full-width NSF metadata has no trailing NUL. */
    CHECK(!cr_nsf_open(data, size, &nsf) && nsf);
    memset(data, 0, sizeof data);
    CHECK(!cr_nsf_get_info(nsf, &info));
    CHECK(info.track_count == 2 && info.default_track == 1);
    CHECK(!strcmp(info.title, "Pulse pair") && !strcmp(info.artist, "Cirrus Retro test"));
    CHECK(strlen(info.copyright) == 32);
    CHECK(cr_nsf_get_info(nsf, NULL) && cr_nsf_get_info(NULL, &info));
    CHECK(cr_nsf_render(nsf, first, 1024));
    CHECK(cr_nsf_select(nsf, info.track_count));
    CHECK(!cr_nsf_select(nsf, 0));
    CHECK(cr_nsf_render(nsf, NULL, 1) && cr_nsf_render(nsf, first, 0));
    CHECK(cr_nsf_render(nsf, first, SIZE_MAX));
    CHECK(!cr_nsf_render(nsf, first, 1024));
    CHECK(!cr_nsf_select(nsf, 0));
    CHECK(!cr_nsf_render(nsf, replay, 511));
    CHECK(cr_nsf_select(nsf, info.track_count)); /* preserve position */
    CHECK(!cr_nsf_render(nsf, replay + 1022, 513));
    CHECK(!memcmp(first, replay, sizeof first));
    CHECK(!cr_nsf_select(nsf, 1));
    CHECK(cr_nsf_render(nsf, replay, 1024)); /* guest warning ends selection */
    CHECK(cr_nsf_render(nsf, replay, 1024));
    CHECK(!cr_nsf_select(nsf, 0));
    CHECK(!cr_nsf_render(nsf, replay, 1024));
    CHECK(!memcmp(first, replay, sizeof first));
    CHECK(!cr_nsf_select(nsf, 0));
    int16_t block[CR_NSF_MAX_RENDER_FRAMES * CR_NSF_CHANNELS];
    unsigned remaining = CR_NSF_MAX_TRACK_FRAMES;
    while (remaining > CR_NSF_MAX_RENDER_FRAMES) {
        CHECK(!cr_nsf_render(nsf, block, CR_NSF_MAX_RENDER_FRAMES));
        remaining -= CR_NSF_MAX_RENDER_FRAMES;
    }
    CHECK(remaining < CR_NSF_MAX_RENDER_FRAMES);
    CHECK(cr_nsf_render(nsf, block, remaining + 1));
    CHECK(!cr_nsf_render(nsf, block, remaining));
    CHECK(cr_nsf_render(nsf, block, 1));
    CHECK(!cr_nsf_select(nsf, 0));
    CHECK(!cr_nsf_render(nsf, replay, 1024));
    CHECK(!memcmp(first, replay, sizeof first));
    cr_nsf_close(nsf);
    cr_nsf_close(NULL);
    return 0;
}
