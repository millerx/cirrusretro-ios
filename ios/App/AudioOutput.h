#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN
// Worker-queue interface. Each output owns an independent single-consumer queue.
@interface CRAudioOutput : NSObject
@property(nonatomic, readonly) NSUInteger freeFrames;
@property(nonatomic, readonly) AVAudioEngine *engine;
- (void)writePCM:(const int16_t *)samples frames:(unsigned)frames NS_SWIFT_NAME(write(_:frames:));
@end
NS_ASSUME_NONNULL_END
