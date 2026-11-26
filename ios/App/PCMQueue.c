#include "PCMQueue.h"
#include <assert.h>
#include <string.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "render indices must always be lock-free");
_Static_assert((CR_QUEUE_FRAMES & (CR_QUEUE_FRAMES - 1)) == 0, "index mask needs power of two");

void cr_queue_init(CRPCMQueue *q)
{
    atomic_init(&q->read, 0);
    atomic_init(&q->written, 0);
}

unsigned cr_queue_space(const CRPCMQueue *q)
{
    unsigned write = atomic_load_explicit(&q->written, memory_order_relaxed);
    unsigned read = atomic_load_explicit(&q->read, memory_order_acquire);
    return CR_QUEUE_FRAMES - (write - read);
}

void cr_queue_write(CRPCMQueue *q, const int16_t *pcm, unsigned frames)
{
    assert(frames <= cr_queue_space(q));
    unsigned write = atomic_load_explicit(&q->written, memory_order_relaxed);
    for (unsigned i = 0; i < frames; ++i)
        memcpy(q->samples[(write + i) & (CR_QUEUE_FRAMES - 1)], pcm + i * 2, 2 * sizeof(*pcm));
    atomic_store_explicit(&q->written, write + frames, memory_order_release);
}

unsigned cr_queue_read(CRPCMQueue *q, float *left, float *right, unsigned frames)
{
    unsigned read = atomic_load_explicit(&q->read, memory_order_relaxed);
    unsigned count = atomic_load_explicit(&q->written, memory_order_acquire) - read;
    if (count > frames)
        count = frames;
    for (unsigned i = 0; i < count; ++i) {
        const int16_t *p = q->samples[(read + i) & (CR_QUEUE_FRAMES - 1)];
        left[i] = p[0] / 32768.0f;
        right[i] = p[1] / 32768.0f;
    }
    memset(left + count, 0, (frames - count) * sizeof(*left));
    memset(right + count, 0, (frames - count) * sizeof(*right));
    atomic_store_explicit(&q->read, read + count, memory_order_release);
    return count;
}
