#include "cirrus_nsf.h"
#include <gme/gme.h>
#include <stdlib.h>
#include <string.h>

struct cr_nsf {
    Music_Emu *emu;
    cr_nsf_info info;
    int playing;
};

static unsigned little16(const uint8_t *p)
{
    return p[0] | ((unsigned)p[1] << 8);
}

static const char *validate(const uint8_t *b, size_t size)
{
    if (!b || size <= 128 || size > CR_NSF_MAX_BYTES)
        return "NSF size outside supported range";
    if (memcmp(b, "NESM\x1a", 5) || b[5] != 1)
        return "expected a raw NSF version 1 file";
    if (!b[6] || !b[7] || b[7] > b[6])
        return "invalid NSF track count or start track";
    if (b[123])
        return "expansion audio is outside this prototype";

    unsigned load = little16(b + 8);
    if (load < 0x8000 || little16(b + 10) < 0x8000 || little16(b + 12) < 0x8000)
        return "expected ROM load, init and play addresses";
    size_t payload = size - 128;
    const uint8_t flat_banks[8] = {0};
    if (memcmp(b + 112, flat_banks, 8) == 0) {
        if (payload > 0x10000u - load)
            return "unbanked payload exceeds ROM address space";
    } else if (payload + (load & 0xfff) > 1024u * 1024u) {
        return "payload exceeds 256 ROM banks";
    }
    return NULL;
}

const char *cr_nsf_open(const uint8_t *bytes, size_t size, cr_nsf **out)
{
    if (!out)
        return "missing output handle";
    *out = NULL;
    const char *error = validate(bytes, size);
    if (error)
        return error;
    cr_nsf *nsf = calloc(1, sizeof *nsf);
    if (!nsf)
        return "out of memory";
    if (gme_open_data(bytes, (long)size, &nsf->emu, CR_NSF_RATE)) {
        free(nsf);
        return "engine could not load NSF";
    }
    gme_ignore_silence(nsf->emu, 1);
    nsf->info.track_count = bytes[6];
    nsf->info.default_track = bytes[7] - 1u;
    memcpy(nsf->info.title, bytes + 14, 32);
    memcpy(nsf->info.artist, bytes + 46, 32);
    memcpy(nsf->info.copyright, bytes + 78, 32);
    *out = nsf;
    return NULL;
}

const char *cr_nsf_get_info(const cr_nsf *nsf, cr_nsf_info *out)
{
    if (!nsf || !out)
        return "missing handle or metadata buffer";
    *out = nsf->info;
    return NULL;
}

const char *cr_nsf_select(cr_nsf *nsf, unsigned track)
{
    if (!nsf || track >= nsf->info.track_count)
        return "track outside NSF track range";
    nsf->playing = !gme_start_track(nsf->emu, (int)track) && !gme_warning(nsf->emu);
    return nsf->playing ? NULL : "engine could not start track";
}

const char *cr_nsf_render(cr_nsf *nsf, int16_t *pcm, size_t frames)
{
    if (!nsf || !nsf->playing)
        return "select a track before rendering";
    if (!pcm || !frames || frames > CR_NSF_MAX_RENDER_FRAMES)
        return "invalid PCM buffer or frame count";
    if (gme_play(nsf->emu, (int)frames * CR_NSF_CHANNELS, pcm) || gme_warning(nsf->emu)) {
        nsf->playing = 0;
        return "engine error during playback";
    }
    return NULL;
}

void cr_nsf_close(cr_nsf *nsf)
{
    if (nsf) {
        gme_delete(nsf->emu);
        free(nsf);
    }
}
