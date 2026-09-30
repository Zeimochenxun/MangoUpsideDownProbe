// Test-only property stubs: actual three helper bodies are inserted by runner.
// This executable checks their Objective-C syntax/traversal/math; it is not UIKit.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

static int Failures;
#undef assert
#define assert(condition) do { if (!(condition)) { Failures++; } } while (0)

@interface CALayer : NSObject
@property (nonatomic) CGFloat opacity;
@property (nonatomic) BOOL hidden;
@property (nonatomic, assign) CALayer *presentationLayer;
@property (nonatomic) CGRect bounds;
@property (nonatomic) CGFloat transform;
@property (nonatomic) CGFloat position;
@end
@implementation CALayer
@end

@interface UIView : NSObject
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL hidden;
@property (nonatomic, assign) CALayer *layer;
@property (nonatomic, assign) UIView *superview;
@property (nonatomic) CGRect bounds;
@end
@implementation UIView
@end

/* ACTUAL_HELPERS */
/* ACTUAL_POLICY_EXPRESSIONS */

static UIView *View(CGFloat width, CGFloat height, CGFloat alpha) {
    UIView *v = [UIView new];
    v.alpha = alpha;
    v.layer = [CALayer new];
    v.layer.opacity = alpha;
    v.bounds = (CGRect){ .size = { width, height } };
    v.layer.bounds = v.bounds;
    return v;
}

static void Presented(UIView *v, CGFloat width, CGFloat height, CGFloat opacity) {
    CALayer *p = [CALayer new];
    p.bounds = (CGRect){ .size = { width, height } };
    p.opacity = opacity;
    v.layer.presentationLayer = p;
}

static void Near(CGFloat actual, CGFloat expected) {
    assert(fabs(actual - expected) < 0.000001);
}

int main(void) {
    UIView *host = View(125, 36.67, 0.1);
    UIView *native = View(125, 36.67, 0);
    native.superview = host;
    Presented(native, 125, 36.67, 1);
    Near(EffectiveOpacity(native, host), 1);
    native.layer.presentationLayer.opacity = 0.75;
    Near(EffectiveOpacity(native, host), 0.75);
    native.layer.presentationLayer.opacity = 0.25;
    Near(EffectiveOpacity(native, host), 0.25);
    native.alpha = 1;
    native.layer.opacity = 1;
    native.layer.presentationLayer.opacity = 0;
    Near(EffectiveOpacity(native, host), 0);
    native.layer.presentationLayer = nil;
    native.alpha = 0.4;
    native.layer.opacity = 0.4;
    Near(EffectiveOpacity(native, host), 0.4);

    UIView *ancestor = View(125, 36.67, 0);
    ancestor.superview = host;
    native.superview = ancestor;
    Presented(ancestor, 125, 36.67, 0.7);
    Presented(native, 125, 36.67, 0.6);
    Near(EffectiveOpacity(native, host), 0.42);
    native.hidden = YES;
    Near(EffectiveOpacity(native, host), 0);
    native.hidden = NO;
    native.layer.hidden = YES;
    Near(EffectiveOpacity(native, host), 0);
    native.layer.hidden = NO;
    ancestor.hidden = YES;
    Near(EffectiveOpacity(native, host), 0);
    ancestor.hidden = NO;
    ancestor.layer.hidden = YES;
    Near(EffectiveOpacity(native, host), 0);
    ancestor.layer.hidden = NO;
    Near(EffectiveOpacity(host, host), 1);

    assert(StableIdleHostGeometry(host));
    Presented(host, 150, 44, 1);
    assert(!StableIdleHostGeometry(host));
    Presented(host, 143, 40, 1);
    assert(StableIdleHostGeometry(host));
    Presented(host, 125.6, 36.67, 1);
    assert(StableIdleHostGeometry(host));
    Presented(host, 125.4, 36.67, 1);
    assert(StableIdleHostGeometry(host));
    Presented(host, 125, 37.27, 1);
    assert(StableIdleHostGeometry(host));
    Presented(host, 125, 37.07, 1);
    assert(StableIdleHostGeometry(host));
    Presented(host, NAN, 36.67, 1);
    assert(!StableIdleHostGeometry(host));
    Presented(host, 125, INFINITY, 1);
    assert(!StableIdleHostGeometry(host));
    Presented(host, 125, 36.67, 1);
    host.layer.transform = 1;
    host.layer.presentationLayer.transform = 1.08;
    host.layer.position = 80;
    host.layer.presentationLayer.position = 82;
    assert(StableIdleHostGeometry(host));

    // Return after notification content clears: compact geometry must restore
    // backing before bounds reach near-exact agreement with the model.
    host.alpha = 1;
    host.layer.opacity = 1;
    native.superview = host;
    native.alpha = 0;
    native.layer.opacity = 0;
    Presented(native, 125, 36.67, 0);
    CGFloat widths[] = {160, 143, 129, 125.8, 125};
    for (NSUInteger i = 0; i < sizeof(widths) / sizeof(widths[0]); i++) {
        Presented(host, widths[i], 36.67, 1);
        CGFloat expected = widths[i] > 145 ? 0 : 1;
        Near(Backing(host, EffectiveOpacity(native, host)), expected);
    }
    Presented(host, 129, 38, 1);
    native.layer.presentationLayer.opacity = 0.75;
    Near(Backing(host, EffectiveOpacity(native, host)), 0.25);
    native.layer.presentationLayer.opacity = 1;
    Near(Backing(host, EffectiveOpacity(native, host)), 0);
    Presented(host, 150, 44, 1);
    Near(Backing(host, 0), 0);
    Presented(host, 145.01, 36.67, 1);
    assert(!StableIdleHostGeometry(host));
    Presented(host, 125, 45.01, 1);
    assert(!StableIdleHostGeometry(host));
    Presented(host, 125, 36.67, 1);
    host.bounds = (CGRect){ .size = { 150, 44 } };
    assert(!StableIdleHostGeometry(host));
    Near(Backing(host, 0), 0);
    if (Failures) {
        fprintf(stderr, "FAIL: actual helper bodies failed %d behavior expectations\n", Failures);
        return 1;
    }
    puts("PASS: actual helper bodies compiled and executed with Objective-C property stubs (no UIKit/device validation)");
    return 0;
}

