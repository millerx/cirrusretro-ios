#ifndef CR_PCM_QUEUE_H
#define CR_PCM_QUEUE_H
#include <stdatomic.h>
#include <stdint.h>

// Single producer, single consumer. Only reset by constructing a fresh queue.
enum { CR_QUEUE_FRAMES = 2048, CR_BLOCK_FRAMES = 512 };
typedef struct {
    atomic_uint read, written;
    int16_t samples[CR_QUEUE_FRAMES][2];
} CRPCMQueue;

void cr_queue_init(CRPCMQueue *q);
unsigned cr_queue_space(const CRPCMQueue *q);
void cr_queue_write(CRPCMQueue *q, const int16_t *pcm, unsigned frames);
// Returns sourced frames; fills the rest of both output planes with silence.
unsigned cr_queue_read(CRPCMQueue *q, float *left, float *right, unsigned frames);
#endif
