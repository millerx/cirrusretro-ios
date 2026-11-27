#ifndef CIRRUS_MUSIC_H
#define CIRRUS_MUSIC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cr_nsf cr_music;
enum {
    CR_MUSIC_RATE = 44100,
    CR_MUSIC_CHANNELS = 2,
    CR_MUSIC_MAX_TRACK_SECONDS = 3600,
    CR_MUSIC_MAX_TRACK_FRAMES = CR_MUSIC_RATE * CR_MUSIC_MAX_TRACK_SECONDS,
    CR_MUSIC_MAX_BYTES = 8 * 1024 * 1024,
    CR_MUSIC_MAX_RENDER_FRAMES = 4096
};

typedef enum { CR_FORMAT_NSF, CR_FORMAT_SPC, CR_FORMAT_VGM } cr_format;

typedef struct {
    cr_format format;
    unsigned track_count;
    unsigned frame_limit; /* per selection, shortened for finite VGM streams */
    unsigned default_track; /* zero-based */
    char title[33], artist[33], copyright[33]; /* NUL-terminated text, up to 32 bytes */
} cr_music_info;

/* NULL means success. Errors are static strings. Serialize all calls on one
   handle (including close) on one worker or serial queue. Calls have no
   physical-thread affinity and provide no real-time guarantee.
   Open identifies the format by content and consumes the input synchronously. On success the caller owns
   *out and can release the bytes. On error *out is NULL. */
const char *cr_music_open(const uint8_t *bytes, size_t size, cr_music **out);
/* Copies metadata into caller storage, independent of the handle's lifetime. */
const char *cr_music_get_info(const cr_music *music, cr_music_info *out);
/* Select before rendering. Selecting again restarts at frame zero.
   An out-of-range track preserves the current position and selection.
   An engine selection error requires selecting again or closing. */
const char *cr_music_select(cr_music *music, unsigned track);
/* Writes exactly frames of interleaved native-endian signed 16-bit L,R PCM
   at CR_MUSIC_RATE. Supply room for frames * CR_MUSIC_CHANNELS samples.
   Valid block size is 1..CR_MUSIC_MAX_RENDER_FRAMES. Discard the entire block
   on error. Each selection permits up to CR_MUSIC_MAX_TRACK_FRAMES (one hour).
   A block that exceeds the remaining frame_limit allowance leaves the position unchanged.
   An engine error requires selecting a track again or closing. */
const char *cr_music_render(cr_music *music, int16_t *pcm, size_t frames);
/* Accepts NULL. Release each successful open exactly once. */
void cr_music_close(cr_music *music);

#ifdef __cplusplus
}
#endif
#endif
