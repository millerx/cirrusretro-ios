#import "AudioOutput.h"
#import "PCMQueue.h"
#import "cirrus_nsf.h"

@interface CRSampleStorage : NSObject {
@public
    CRPCMQueue queue;
}
@end
@implementation CRSampleStorage
@end

@implementation CRAudioOutput {
    CRSampleStorage *_storage;
}
- (instancetype)init
{
    if ((self = [super init])) {
        CRSampleStorage *storage = [CRSampleStorage new];
        cr_queue_init(&storage->queue);
        _storage = storage;
        _engine = [AVAudioEngine new];
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:CR_NSF_RATE channels:2];
        // The block retains storage at construction. Direct ivar access in the
        // render body emits no Objective-C messaging or ARC ownership traffic.
        AVAudioSourceNode *source = [[AVAudioSourceNode alloc] initWithFormat:format
            renderBlock:^OSStatus(BOOL *silent, const AudioTimeStamp *time, AVAudioFrameCount frames,
                                  AudioBufferList *buffers) {
                (void)time;
                if (buffers->mNumberBuffers != 2)
                    return kAudio_ParamError;
                Float32 *left = buffers->mBuffers[0].mData;
                Float32 *right = buffers->mBuffers[1].mData;
                if (!left || !right || frames > buffers->mBuffers[0].mDataByteSize / sizeof(*left)
                    || frames > buffers->mBuffers[1].mDataByteSize / sizeof(*right))
                    return kAudio_ParamError;
                *silent = cr_queue_read(&storage->queue, left, right, frames) == 0;
                return noErr;
            }];
        [_engine attachNode:source];
        [_engine connect:source to:_engine.mainMixerNode format:format];
    }
    return self;
}
- (NSUInteger)freeFrames { return cr_queue_space(&_storage->queue); }
- (void)writePCM:(const int16_t *)samples frames:(unsigned)frames
{
    cr_queue_write(&_storage->queue, samples, frames);
}
@end
