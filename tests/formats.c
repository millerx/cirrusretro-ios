#include "cirrus_music.h"
#include "cirrus_nsf.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(test) do { if (!(test)) { \
    fprintf(stderr, "line %d: %s\n", __LINE__, #test); return 1; \
} } while (0)

int main(int argc, char **argv)
{
    CHECK(argc == 3);
    FILE *f = fopen(argv[1], "rb");
    CHECK(f && !fseek(f, 0, SEEK_END));
    long size = ftell(f);
    CHECK(size > 0 && size <= CR_MUSIC_MAX_BYTES + 1);
    rewind(f);
    uint8_t *data = malloc(size);
    CHECK(data && fread(data, 1, size, f) == (size_t)size && !fclose(f));
    cr_music *music = NULL;
    cr_music_info info;
    CHECK(cr_nsf_open(data, size, &music) && !music);
    if (!strcmp(argv[2], "reject")) {
        CHECK(cr_music_open(data, size, &music) && !music);
        free(data);
        return 0;
    }
    CHECK(!cr_music_open(data, size, &music));
    free(data); /* GME owns all bytes needed for subsequent starts and loops. */
    CHECK(!cr_music_get_info(music, &info));
    CHECK(info.track_count == 1 && info.default_track == 0);
    int spc = !strcmp(argv[2], "spc");
    int dac = !strcmp(argv[2], "dac");
    CHECK(info.format == (spc ? CR_FORMAT_SPC : CR_FORMAT_VGM));
    CHECK(!strcmp(info.title, spc ? "BRR pulse" : dac ? "" : "PSG pulse"));
    CHECK(!strcmp(info.artist, dac ? "" : "Cirrus test"));
    CHECK(info.frame_limit == (spc || dac ? CR_MUSIC_MAX_TRACK_FRAMES : 44100));
    int16_t first[8192], replay[8192];
    CHECK(cr_music_render(music, first, 4096));
    CHECK(!cr_music_select(music, 0));
    CHECK(!cr_music_render(music, first, 4096));
    CHECK(!cr_music_select(music, 0));
    CHECK(!cr_music_render(music, replay, 1024));
    CHECK(cr_music_select(music, 1));
    CHECK(!cr_music_render(music, replay + 2048, 3072));
    CHECK(!memcmp(first, replay, sizeof first));
    int crossings = 0;
    for (size_t i = 2; i < 8192; i += 2)
        crossings += first[i-2] < 0 && first[i] >= 0;
    CHECK(crossings >= 35 && crossings <= 55); /* BRR tone, 500 Hz */
    if (!spc && !dac) {
        unsigned remaining = info.frame_limit - 4096;
        while (remaining > 4096) {
            CHECK(!cr_music_render(music, replay, 4096));
            remaining -= 4096;
        }
        CHECK(!cr_music_render(music, replay, remaining));
        CHECK(cr_music_render(music, replay, 1));
        CHECK(!cr_music_select(music, 0));
    }
    cr_music_close(music);
    return 0;
}
