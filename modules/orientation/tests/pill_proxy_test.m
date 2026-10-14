#import "../PillProxy.h"
#include <assert.h>
#include <stdio.h>

@interface FakePan : NSObject <MWPillGesture>
@property(nonatomic) NSInteger stateValue;
@property(nonatomic, strong) id viewValue;
@property(nonatomic) CGPoint local, velocity;
@property(nonatomic) unsigned translationCalls, mutations;
- (CGPoint)velocityInView:(id)view;
- (void)setTranslation:(CGPoint)translation inView:(id)view;
@end
@implementation FakePan
- (NSInteger)state { return self.stateValue; }
- (id)view { return self.viewValue; }
- (CGPoint)translationInView:(__unused id)view { ++self.translationCalls; return self.local; }
- (CGPoint)velocityInView:(__unused id)view { return self.velocity; }
- (void)setTranslation:(__unused CGPoint)translation inView:(__unused id)view { ++self.mutations; }
@end

// Mirrors the verified handler: only state/view/translationInView:, y once.
static int Handler(id<MWPillGesture> gesture) {
    if ([gesture state] != 3) return 0;
    CGPoint t = [gesture translationInView:[gesture view]];
    return t.y < -30 ? 1 : t.y > 30 ? 2 : 0;
}

int main(void) {
    @autoreleasepool {
        id marker = [NSObject new];
        FakePan *real = [FakePan new];
        real.stateValue = 3; real.viewValue = marker; real.local = CGPointMake(7, -50); real.velocity = CGPointMake(1, -900);
        assert(Handler(real) == 1);
        unsigned before = real.translationCalls;
        id proxy = MWPillProxy(real, CGPointMake(real.local.x, -real.local.y));
        assert(Handler(proxy) == 2);                      // the two vertical actions swap
        assert(real.translationCalls == before);          // the real answer is never asked
        assert([(id<MWPillGesture>)proxy state] == 3 && [(id<MWPillGesture>)proxy view] == marker);
        assert([(id<MWPillGesture>)proxy translationInView:nil].x == 7);
        CGPoint velocity = [(FakePan *)proxy velocityInView:marker];  // unknown selectors forward
        assert(velocity.x == 1 && velocity.y == -900);
        assert(real.mutations == 0 && real.local.y == -50);          // recognizer untouched
        real.stateValue = 2;
        assert(Handler(proxy) == 0);                      // state is live, not a copy
        puts("PASS: pill proxy swaps only the translation answer, forwards the rest and never mutates the recognizer");
    }
    return 0;
}
