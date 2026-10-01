// Beta8 Mango split windows only. No UIView/UIWindow-wide hooks.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>
#import "Beta8Identity.h"
#include "WorldMath.h"
#include <math.h>

static const char *Disabled = "/var/mobile/Library/Preferences/MangoSplitUpsideDownFix.disabled";
static NSHashTable<UIWindow *> *Windows;
static BOOL Ready, Enabled, Busy;
static Class SceneClass, FloatingClass;
static dispatch_source_t Timer;
static char StateKey;

@interface MSB8SplitState : NSObject
@property(nonatomic) CGAffineTransform before, after;
@property(nonatomic) BOOL applied, suspended;
@end
@implementation MSB8SplitState
@end

static MWTransform Math(CGAffineTransform t) { return (MWTransform){t.a,t.b,t.c,t.d,t.tx,t.ty}; }
static CGAffineTransform CG(MWTransform t) { return CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty); }
static BOOL Near(CGAffineTransform a, CGAffineTransform b) { return MWNear(Math(a), Math(b)); }
static void Log(NSString *s) { NSLog(@"[MangoSuiteSplit] %@", s); }
static MSB8SplitState *State(UIWindow *w) { return objc_getAssociatedObject(w, &StateKey); }

static BOOL ContainsMangoTarget(UIWindow *window) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    for (NSUInteger i = 0; i < queue.count; ++i) {
        if (queue.count > 2048) return NO;
        UIView *view = queue[i];
        if ([view isKindOfClass:SceneClass] || [view isKindOfClass:FloatingClass]) return YES;
        [queue addObjectsFromArray:view.subviews];
    }
    return NO;
}

static NSArray<UIWindow *> *AllWindows(void) {
    NSMutableOrderedSet<UIWindow *> *set = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [set addObjectsFromArray:((UIWindowScene *)scene).windows];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [set addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    return set.array;
}

static void Write(UIWindow *w, CGAffineTransform value) {
    [UIView performWithoutAnimation:^{ w.transform = value; }];
}

static void Restore(UIWindow *w, MSB8SplitState *state) {
    if (!state.applied) return;
    BOOL owned = MWOwns(Math(w.transform), Math(state.after), state.applied, state.suspended);
    state.applied = NO;
    if (owned) {
        Write(w, state.before);
        return;
    }
    // Another layout owner has changed the transform. Do not replace its
    // value with our old baseline, and never reset a pre-existing half-turn.
    // Relinquish ownership without suspending routine scene transitions.
    // Mango can legitimately reset its window to identity on rotation; the
    // next reconciliation still must pass the complete target/basis guards.
    Log(@"Owned split transform replaced externally; ownership released");
}

static BOOL SafeWindow(UIWindow *w) {
    if (object_getClass(w) != UIWindow.class || w.screen != UIScreen.mainScreen) return NO;
    if (!CATransform3DIsAffine(w.layer.transform) || !CATransform3DIsIdentity(w.layer.sublayerTransform)) return NO;
    CGPoint anchor = w.layer.anchorPoint;
    if (fabs(anchor.x - .5) > 1e-6 || fabs(anchor.y - .5) > 1e-6) return NO;
    CGRect expected = w.screen.fixedCoordinateSpace.bounds;
    CGSize actual = w.bounds.size;
    if (!isfinite(actual.width) || !isfinite(actual.height) ||
        fabs(actual.width - expected.size.width) > 2 || fabs(actual.height - expected.size.height) > 2) return NO;
    CGRect fixed = [w convertRect:w.bounds toCoordinateSpace:w.screen.fixedCoordinateSpace];
    return isfinite(fixed.origin.x) && isfinite(fixed.origin.y) &&
        isfinite(fixed.size.width) && isfinite(fixed.size.height) &&
        fabs(CGRectGetMidX(fixed) - CGRectGetMidX(expected)) < 2 &&
        fabs(CGRectGetMidY(fixed) - CGRectGetMidY(expected)) < 2 &&
        fabs(fixed.size.width - expected.size.width) < 2 &&
        fabs(fixed.size.height - expected.size.height) < 2;
}

static void Update(UIWindow *w, BOOL active) {
    MSB8SplitState *state = State(w);
    BOOL isTarget = ContainsMangoTarget(w);
    if (!active || !isTarget || !SafeWindow(w)) {
        if (state) Restore(w, state);
        return;
    }
    if (!state) {
        state = [MSB8SplitState new];
        objc_setAssociatedObject(w, &StateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (state.suspended) return;
    if (state.applied) {
        if (!Near(w.transform, state.after)) Restore(w, state);
        return;
    }

    id<UICoordinateSpace> fixed = w.screen.fixedCoordinateSpace;
    CGPoint old[3] = {[w convertPoint:CGPointZero toCoordinateSpace:fixed],
                      [w convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed],
                      [w convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed]};
    double dx = old[1].x-old[0].x, dy = old[2].y-old[0].y;
    double skewX = old[2].x-old[0].x, skewY = old[1].y-old[0].y;
    // A Beta8 scene/window may already be inverted even when its model
    // transform reads identity. Inspect its actual coordinate mapping first.
    if (MWInvertedBasis(dx, dy, skewX, skewY)) return;
    if (!isfinite(dx) || !isfinite(dy) || dx <= 0 || dy <= 0 ||
        fabs(skewY) > fabs(dx)*.001 || fabs(skewX) > fabs(dy)*.001 ||
        !Near(w.transform, CGAffineTransformIdentity)) return;

    CGRect screen = fixed.bounds;
    CGPoint pivot = CGPointMake(CGRectGetMidX(screen), CGRectGetMidY(screen));
    MWTransform turn = MWTurn(Math(w.transform), (MWPoint){w.center.x,w.center.y}, (MWPoint){pivot.x,pivot.y});
    if (!MWFinite(turn)) return;
    state.before = w.transform; state.after = CG(turn); state.applied = YES;
    Write(w, state.after);
    CGPoint actual[3] = {[w convertPoint:CGPointZero toCoordinateSpace:fixed],
                         [w convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed],
                         [w convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed]};
    for (unsigned i = 0; i < 3; ++i) {
        if (!isfinite(actual[i].x) || !isfinite(actual[i].y) ||
            fabs(actual[i].x - (2*pivot.x-old[i].x)) > .1 ||
            fabs(actual[i].y - (2*pivot.y-old[i].y)) > .1) {
            Restore(w, state); state.suspended = YES;
            Log(@"Split coordinate verification failed; restored owned transform");
            return;
        }
    }
}

static void Reconcile(void) {
    if (!Ready || Busy || !NSThread.isMainThread) return;
    Busy = YES;
    @try {
        if (Enabled && B8Disabled(Disabled)) Enabled = NO;
        BOOL active = Enabled && B8Orientation() == UIInterfaceOrientationPortraitUpsideDown;
        if (active) {
            for (UIWindow *w in AllWindows())
                if (object_getClass(w) == UIWindow.class && ContainsMangoTarget(w)) [Windows addObject:w];
        }
        for (UIWindow *w in Windows.allObjects) Update(w, active);
    } @finally { Busy = NO; }
}

// Mango-owned class lifecycle callbacks give immediate updates as split
// windows attach or relayout. A slow timer handles direction changes and
// windows not enumerated by public scene APIs; it is not an animation driver.
static void (*SceneMove)(id,SEL), (*FloatingMove)(id,SEL);
static void (*SceneLayout)(id,SEL), (*FloatingLayout)(id,SEL);
static void AfterLifecycle(UIView *view) {
    if (!Ready || !NSThread.isMainThread) return;
    UIWindow *w = view.window;
    if (object_getClass(w) == UIWindow.class) [Windows addObject:w];
    Reconcile();
}
static void HookSceneMove(id self,SEL cmd) { SceneMove(self,cmd); AfterLifecycle(self); }
static void HookFloatingMove(id self,SEL cmd) { FloatingMove(self,cmd); AfterLifecycle(self); }
static void HookSceneLayout(id self,SEL cmd) { SceneLayout(self,cmd); AfterLifecycle(self); }
static void HookFloatingLayout(id self,SEL cmd) { FloatingLayout(self,cmd); AfterLifecycle(self); }

static BOOL VoidMethod(Class cls, SEL selector) {
    Method m = class_getInstanceMethod(cls, selector);
    return m && !strcmp(method_getTypeEncoding(m), "v16@0:8");
}

static void Install(void) {
    static unsigned attempts;
    if (Ready || B8Disabled(Disabled) || B8LegacyOrientationLoaded()) return;
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
    SceneClass = objc_getClass("DecoratedAppSceneView");
    FloatingClass = objc_getClass("DecoratedFloatingView");
    if (!B8VerifiedMango() || !SceneClass || !FloatingClass) {
        if (++attempts < 40) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ Install(); });
        else Log(@"Split unavailable: matching Beta8 images/classes not loaded");
        return;
    }
    for (Class cls in @[SceneClass, FloatingClass])
        if (!VoidMethod(cls, @selector(didMoveToWindow)) || !VoidMethod(cls, @selector(layoutSubviews))) {
            Log(@"Split unavailable: Mango lifecycle method ABI mismatch"); return;
        }
    Windows = [NSHashTable weakObjectsHashTable]; Enabled = YES; Ready = YES;
    MSHookMessageEx(SceneClass,@selector(didMoveToWindow),(IMP)HookSceneMove,(IMP *)&SceneMove);
    MSHookMessageEx(FloatingClass,@selector(didMoveToWindow),(IMP)HookFloatingMove,(IMP *)&FloatingMove);
    MSHookMessageEx(SceneClass,@selector(layoutSubviews),(IMP)HookSceneLayout,(IMP *)&SceneLayout);
    MSHookMessageEx(FloatingClass,@selector(layoutSubviews),(IMP)HookFloatingLayout,(IMP *)&FloatingLayout);
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            Reconcile(); dispatch_async(dispatch_get_main_queue(), ^{ Reconcile(); });
        }];
    Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),350*NSEC_PER_MSEC,75*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(Timer, ^{ Reconcile(); if (!Enabled) dispatch_source_cancel(Timer); });
    dispatch_resume(Timer);
    Log(@"Beta8 split installed; pre-existing rotations preserved"); Reconcile();
}

__attribute__((constructor)) static void StartSplit(void) {
    @autoreleasepool { dispatch_async(dispatch_get_main_queue(), ^{ Install(); }); }
}
