#include "vgm.h"
#include <string.h>

static uint32_t le32(const uint8_t *p)
{
    return p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* Scan the intro once and the loop at most twice. The engine interprets trusted command boundaries
   and follows one backward edge at END. Validate both cursor and work bounds
   across that edge before giving it any input. */
static const char *scan(const uint8_t *b, size_t pos, size_t end, size_t loop,
                        int fm, cr_music_info *info)
{
    uint64_t frames = 0, loop_frame = 0;
    size_t loop_commands = 0, bank_size = 0, pcm = 0;
    unsigned credit = 1024;
    int in_loop = 0, replay = 0, have_seek = 0;
    while (pos < end) {
        if (pos == loop) {
            in_loop = 1;
            loop_frame = frames;
            loop_commands = 0;
            have_seek = 0; /* every loop must establish its own PCM cursor */
        }
        if (in_loop)
            ++loop_commands;
        if (credit == 0)
            return "VGM command density exceeds playback budget";
        --credit;
        uint8_t cmd = b[pos++];
        size_t left = end - pos;
        unsigned wait = 0;
        if (cmd == 0x66) {
            if (loop && (!in_loop || loop_frame == frames ||
                         loop_commands > (frames - loop_frame) * 8))
                return "invalid VGM loop target or timing";
            if (loop && !replay) {
                // A wait can fill the bucket and discard surplus credit. Check
                // the suffix-to-prefix burst with the actual credit at END.
                // With nonnegative net credit per lap, subsequent laps start
                // with at least this second lap's credit or reach a fixed point.
                replay = 1;
                pos = loop;
                continue;
            }
            if (!frames)
                return "VGM contains no timed audio";
            if (!loop && frames < CR_MUSIC_MAX_TRACK_FRAMES)
                info->frame_limit = (unsigned)frames;
            return NULL;
        } else if (cmd == 0x4f || cmd == 0x50) {
            if (left < 1)
                return "truncated VGM PSG command";
            ++pos;
        } else if (cmd == 0x52 || cmd == 0x53) {
            if (!fm || left < 2)
                return "invalid VGM YM2612 write";
            pos += 2;
        } else if (cmd == 0x61) {
            if (left < 2)
                return "truncated VGM wait";
            wait = b[pos] | ((unsigned)b[pos + 1] << 8);
            pos += 2;
        } else if (cmd == 0x62 || cmd == 0x63) {
            wait = cmd == 0x62 ? 735 : 882;
        } else if (cmd >= 0x70 && cmd <= 0x7f) {
            wait = cmd - 0x70 + 1;
        } else if (cmd == 0x67) {
            if (!fm || left < 6 || b[pos] != 0x66 || b[pos+1] != 0 || bank_size || in_loop)
                return "expected one YM2612 PCM bank before the loop";
            bank_size = le32(b + pos + 2);
            if (!bank_size || bank_size > left - 6)
                return "invalid VGM PCM bank size";
            pos += 6 + bank_size;
        } else if (cmd == 0xe0) {
            if (left < 4 || !bank_size)
                return "invalid VGM PCM seek";
            pcm = le32(b + pos);
            if (pcm >= bank_size)
                return "VGM PCM seek outside bank";
            have_seek = 1;
            pos += 4;
        } else if (cmd >= 0x80 && cmd <= 0x8f) {
            if (!have_seek || pcm >= bank_size)
                return "VGM PCM read outside bank";
            ++pcm;
            wait = cmd & 15;
        } else {
            return "unsupported VGM command";
        }
        frames += wait;
        credit += wait * 8;
        if (credit > 1024)
            credit = 1024;
    }
    return "missing VGM end command";
}

const char *cr_validate_vgm(const uint8_t *b, size_t size, cr_music_info *info)
{
    if (size <= 0x40 || le32(b + 4) != size - 4)
        return "invalid VGM file length";
    uint32_t version = le32(b + 8);
    if (version < 0x100 || version > 0x171)
        return "unsupported VGM version";
    uint32_t psg = le32(b + 0x0c), fm = le32(b + 0x2c);
    // Restrict clocks to the range of single-chip Sega consoles; flag bits
    // for dual/alternate chips are outside that range as well.
    if ((psg && (psg < 3000000 || psg > 4100000)) ||
        (fm && (version < 0x110 || fm < 7000000 || fm > 8100000)) ||
        le32(b + 0x10) || le32(b + 0x30) || b[0x2a] > 16 || b[0x2b])
        return "unsupported VGM chip or clock";
    size_t start = 0x40;
    uint32_t offset = le32(b + 0x34);
    if (version >= 0x150 && offset) {
        if (offset < 12 || offset >= size - 0x34)
            return "invalid VGM data offset";
        start = 0x34 + offset;
    }
    // Extended chip headers can request emulation that GME silently ignores.
    for (size_t i = 0x38; i < start; ++i) {
        if (b[i])
            return "unsupported extended VGM header";
    }
    size_t end = size;
    uint32_t gd3 = le32(b + 0x14);
    if (gd3) {
        if (gd3 > size - 0x14 - 12)
            return "invalid VGM metadata offset";
        end = 0x14 + gd3;
        if (end <= start || memcmp(b + end, "Gd3 ", 4) ||
            le32(b + end + 4) != 0x100 || le32(b + end + 8) > size - end - 12 ||
            (le32(b + end + 8) & 1))
            return "invalid VGM metadata";
    }
    uint32_t rel = le32(b + 0x1c);
    if (rel && (rel >= end - 0x1c || 0x1c + rel < start))
        return "invalid VGM loop offset";
    return scan(b, start, end, rel ? 0x1c + rel : 0, fm != 0, info);
}
