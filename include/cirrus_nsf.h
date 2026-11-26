#ifndef CIRRUS_NSF_H
#define CIRRUS_NSF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cr_nsf cr_nsf;
enum {
    CR_NSF_RATE = 44100,
    CR_NSF_CHANNELS = 2,
    CR_NSF_MAX_TRACK_SECONDS = 3600,
    CR_NSF_MAX_TRACK_FRAMES = CR_NSF_RATE * CR_NSF_MAX_TRACK_SECONDS,
    CR_NSF_MAX_BYTES = 128 + 1024 * 1024,
    CR_NSF_MAX_RENDER_FRAMES = 4096
};

typedef struct {
    unsigned track_count;
    unsigned default_track; /* zero-based */
    char title[33], artist[33], copyright[33]; /* NUL-terminated raw NSF text */
} cr_nsf_info;

/* NULL means success. Errors are static strings. Serialize all calls on one
   handle (including close) on its owning worker thread. No real-time guarantee.
   Open consumes raw NSF v1 bytes synchronously. On success the caller owns
   *out and can release the bytes. On error *out is NULL. */
const char *cr_nsf_open(const uint8_t *bytes, size_t size, cr_nsf **out);
/* Copies metadata into caller storage, independent of the handle's lifetime. */
const char *cr_nsf_get_info(const cr_nsf *nsf, cr_nsf_info *out);
/* Select before rendering. Selecting again restarts at frame zero.
   An out-of-range track preserves the current position and selection.
   An engine selection error requires selecting again or closing. */
const char *cr_nsf_select(cr_nsf *nsf, unsigned track);
/* Writes exactly frames of interleaved native-endian signed 16-bit L,R PCM
   at CR_NSF_RATE. Supply room for frames * CR_NSF_CHANNELS samples.
   Valid block size is 1..CR_NSF_MAX_RENDER_FRAMES. Discard the entire block
   on error. Each selection permits up to CR_NSF_MAX_TRACK_FRAMES (one hour).
   A block that exceeds the remaining allowance leaves the position unchanged.
   An engine error requires selecting a track again or closing. */
const char *cr_nsf_render(cr_nsf *nsf, int16_t *pcm, size_t frames);
/* Accepts NULL. Release each successful open exactly once. */
void cr_nsf_close(cr_nsf *nsf);

#ifdef __cplusplus
}
#endif
#endif
