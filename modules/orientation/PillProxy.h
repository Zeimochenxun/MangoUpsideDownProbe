#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Stand-in for the recognizer handed to -[MangoPillElement handlePanGesture:].
// The verified Beta9-1 handler sends its argument only -state, -view and
// -translationInView: and reads y once (build-info/beta94-audit). The proxy
// answers translationInView: with a corrected value and forwards everything
// else, so the real recognizer is never mutated and no UIKit method is hooked.
@protocol MWPillGesture <NSObject>
- (NSInteger)state;
- (id)view;
- (CGPoint)translationInView:(id)view;
@end

@interface MWPillPanProxy : NSObject
@property(nonatomic, strong) id<MWPillGesture> gesture;
@property(nonatomic) CGPoint translation;
@end
@implementation MWPillPanProxy
- (NSInteger)state { return [self.gesture state]; }
- (id)view { return [self.gesture view]; }
- (CGPoint)translationInView:(__unused id)view { return self.translation; }
- (id)forwardingTargetForSelector:(__unused SEL)selector { return self.gesture; }
@end

static inline id MWPillProxy(id gesture, CGPoint translation) {
    MWPillPanProxy *proxy = [MWPillPanProxy new];
    proxy.gesture = gesture;
    proxy.translation = translation;
    return proxy;
}
