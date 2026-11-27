#include "cirrus_music.h"
#include "cirrus_nsf.h"
#include "vgm.h"
#include <gme/gme.h>
#include <stdlib.h>
#include <string.h>

struct cr_nsf {
    Music_Emu *emu;
    cr_music_info info;
    int playing;
    unsigned frames_left;
};

static unsigned little16(const uint8_t *p)
{
    return p[0] | ((unsigned)p[1] << 8);
}

static const char *validate_nsf(const uint8_t *b, size_t size, size_t *engine_size)
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
    size_t declared = little16(b + 125) | ((size_t)b[127] << 16);
    if (declared > payload)
        return "declared program length exceeds input";
    if (declared)
        payload = declared;
    *engine_size = 128 + payload;
    const uint8_t flat_banks[8] = {0};
    if (memcmp(b + 112, flat_banks, 8) == 0) {
        if (payload > 0x10000u - load)
            return "unbanked payload exceeds ROM address space";
    } else if (payload + (load & 0xfff) > 1024u * 1024u) {
        return "payload exceeds 256 ROM banks";
    }
    return NULL;
}

const char *cr_music_open(const uint8_t *bytes, size_t size, cr_music **out)
{
    if (!out)
        return "missing output handle";
    *out = NULL;
    if (!bytes || size < 4 || size > CR_MUSIC_MAX_BYTES)
        return "music file size outside supported range";

    cr_music_info info = {.frame_limit = CR_MUSIC_MAX_TRACK_FRAMES};
    size_t engine_size = size;
    if (memcmp(bytes, "NESM", 4) == 0) {
        const char *error = validate_nsf(bytes, size, &engine_size);
        if (error)
            return error;
        info.format = CR_FORMAT_NSF;
        info.track_count = bytes[6];
        info.default_track = bytes[7] - 1u;
        memcpy(info.title, bytes + 14, 32);
        memcpy(info.artist, bytes + 46, 32);
        memcpy(info.copyright, bytes + 78, 32);
    } else if (memcmp(bytes, "SNES", 4) == 0) {
        static const char signature[] = "SNES-SPC700 Sound File Data v0.30\x1a\x1a";
        if (size < 0x10180 || memcmp(bytes, signature, sizeof signature - 1) ||
            (bytes[0x23] != 0x1a && bytes[0x23] != 0x1b))
            return "expected an SPC v0.30 snapshot";
        // Only the header, APU RAM and DSP registers are needed for playback.
        // Keep optional extended metadata outside the engine's tag parser.
        engine_size = 0x10180;
        info.format = CR_FORMAT_SPC;
        info.track_count = 1;
        if (bytes[0x23] == 0x1a) {
            memcpy(info.title, bytes + 0x2e, 32);
            // Text ID666 uses a five-byte fade field; binary uses four.
            size_t artist = bytes[0xb0] < ' ' ||
                            (bytes[0xb0] >= '0' && bytes[0xb0] <= '9') ? 0xb1 : 0xb0;
            memcpy(info.artist, bytes + artist, 32);
        }
    } else if (memcmp(bytes, "Vgm ", 4) == 0) {
        const char *error = cr_validate_vgm(bytes, size, &info);
        if (error)
            return error;
        info.format = CR_FORMAT_VGM;
        info.track_count = 1;
    } else {
        return "unsupported music file signature";
    }

    cr_music *music = calloc(1, sizeof *music);
    if (!music)
        return "out of memory";
    if (gme_open_data(bytes, (long)engine_size, &music->emu, CR_MUSIC_RATE)) {
        free(music);
        return "engine could not load music file";
    }
    gme_ignore_silence(music->emu, 1);
    gme_set_autoload_playback_limit(music->emu, 0);
    if (info.format == CR_FORMAT_VGM && memcmp(bytes + 0x14, "\0\0\0\0", 4)) {
        gme_info_t *tag = NULL;
        if (gme_track_info(music->emu, &tag, 0)) {
            cr_music_close(music);
            return "engine could not read VGM metadata";
        }
        strncpy(info.title, tag->song, sizeof info.title - 1);
        strncpy(info.artist, tag->author, sizeof info.artist - 1);
        gme_free_info(tag);
    }
    music->info = info;
    *out = music;
    return NULL;
}

const char *cr_music_get_info(const cr_music *music, cr_music_info *out)
{
    if (!music || !out)
        return "missing handle or metadata buffer";
    *out = music->info;
    return NULL;
}

const char *cr_music_select(cr_music *music, unsigned track)
{
    if (!music || track >= music->info.track_count)
        return "track outside track range";
    music->playing = !gme_start_track(music->emu, (int)track) && !gme_warning(music->emu);
    music->frames_left = music->info.frame_limit;
    return music->playing ? NULL : "engine could not start track";
}

const char *cr_music_render(cr_music *music, int16_t *pcm, size_t frames)
{
    if (!music || !music->playing)
        return "select a track before rendering";
    if (!pcm || !frames || frames > CR_MUSIC_MAX_RENDER_FRAMES)
        return "invalid PCM buffer or frame count";
    if (frames > music->frames_left)
        return "render exceeds remaining track duration";
    if (gme_play(music->emu, (int)frames * CR_MUSIC_CHANNELS, pcm) || gme_warning(music->emu)) {
        music->playing = 0;
        return "engine error during playback";
    }
    music->frames_left -= (unsigned)frames;
    return NULL;
}

void cr_music_close(cr_music *music)
{
    if (music) {
        gme_delete(music->emu);
        free(music);
    }
}

/* Keep the NSF v1 entry points and metadata layout for existing clients. */
const char *cr_nsf_open(const uint8_t *bytes, size_t size, cr_nsf **out)
{
    if (!out)
        return "missing output handle";
    *out = NULL;
    if (!bytes || size < 5 || size > CR_NSF_MAX_BYTES || memcmp(bytes, "NESM\x1a", 5))
        return "expected a raw NSF version 1 file";
    return cr_music_open(bytes, size, out);
}

const char *cr_nsf_get_info(const cr_nsf *nsf, cr_nsf_info *out)
{
    if (!nsf || !out)
        return "missing handle or metadata buffer";
    out->track_count = nsf->info.track_count;
    out->default_track = nsf->info.default_track;
    memcpy(out->title, nsf->info.title, sizeof out->title);
    memcpy(out->artist, nsf->info.artist, sizeof out->artist);
    memcpy(out->copyright, nsf->info.copyright, sizeof out->copyright);
    return NULL;
}

const char *cr_nsf_select(cr_nsf *nsf, unsigned track) { return cr_music_select(nsf, track); }

const char *cr_nsf_render(cr_nsf *nsf, int16_t *pcm, size_t frames)
{
    return cr_music_render(nsf, pcm, frames);
}

void cr_nsf_close(cr_nsf *nsf) { cr_music_close(nsf); }
