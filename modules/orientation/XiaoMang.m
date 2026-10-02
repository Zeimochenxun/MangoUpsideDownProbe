// Beta8's own floating-ball, panel, notifications, and alert windows only.
// Preserve native child animations, gestures, positions, and blank hit testing.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>
#import "Beta8Identity.h"
#import "XiaoMangGeometry.h"
#import "XiaoMangMutation.h"
#import "XiaoMangAnimation.h"

static Class WindowClass, PortraitClass;
static NSHashTable<UIWindow *> *Windows;
static BOOL Ready, Enabled, Busy;
static dispatch_source_t Timer;
static char StateKey;
static const char *Disabled = "/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled";

@interface MSXMWindowState : NSObject {
@public
    unsigned mutationDepth;
}
@property(nonatomic) CGAffineTransform before, after;
@property(nonatomic) BOOL applied, suspended;
@end
@implementation MSXMWindowState
@end

static void (*OriginalFrame)(id,SEL,CGRect), (*OriginalBounds)(id,SEL,CGRect);
static void (*OriginalCenter)(id,SEL,CGPoint);
static void (*OriginalTransform)(id,SEL,CGAffineTransform);
static void (*OriginalRoot)(id,SEL,id), (*OriginalScene)(id,SEL,id);
static void (*OriginalHidden)(id,SEL,BOOL);
static void (*OriginalLayout)(id,SEL);

static MWTransform Math(CGAffineTransform t) { return (MWTransform){t.a,t.b,t.c,t.d,t.tx,t.ty}; }
static CGAffineTransform CG(MWTransform t) { return CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty); }
static void Log(NSString *message) { NSLog(@"[MangoSuiteXiaoMang] %@", message); }
static MSXMWindowState *State(UIWindow *window) {
    MSXMWindowState *state = objc_getAssociatedObject(window,&StateKey);
    if (!state) {
        state = [MSXMWindowState new];
        objc_setAssociatedObject(window,&StateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
static BOOL IsTarget(UIWindow *window) {
    return object_getClass(window) == WindowClass && window.screen == UIScreen.mainScreen &&
           object_getClass(window.rootViewController) == PortraitClass;
}
static void WriteTransform(UIWindow *window, CGAffineTransform value) {
    [UIView performWithoutAnimation:^{ OriginalTransform(window,@selector(setTransform:),value); }];
}
static void Restore(UIWindow *window, MSXMWindowState *state) {
    if (!state.applied) return;
    BOOL owned = MWOwns(Math(window.transform),Math(state.after),state.applied,state.suspended);
    state.applied = NO;
    if (owned) { XMClearGeometryAnimations(window.layer); WriteTransform(window,state.before); }
    else if (!state.suspended) {
        state.suspended = YES;
        Log(@"Window transform replaced outside geometry callbacks; preserved and suspended until restart");
    }
}
static XMPlanResult Plan(UIWindow *window, MWTransform *after, CGPoint old[3], MWPoint *pivot) {
    CGRect bounds = window.bounds;
    CGPoint anchor = window.layer.anchorPoint;
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
        bounds.size.width <= 0 || bounds.size.height <= 0 ||
        !isfinite(anchor.x) || !isfinite(anchor.y) ||
        !CATransform3DIsAffine(window.layer.transform) ||
        !CATransform3DIsIdentity(window.layer.sublayerTransform)) return XMPlanInvalid;
    id<UICoordinateSpace> fixed = window.screen.fixedCoordinateSpace;
    old[0] = [window convertPoint:CGPointZero toCoordinateSpace:fixed];
    old[1] = [window convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    old[2] = [window convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    MWTransform mapping = {old[1].x-old[0].x,old[1].y-old[0].y,
                           old[2].x-old[0].x,old[2].y-old[0].y,old[0].x,old[0].y};
    CGPoint anchorPoint = CGPointMake(bounds.origin.x+bounds.size.width*anchor.x,
                                      bounds.origin.y+bounds.size.height*anchor.y);
    CGPoint fixedAnchor = [window convertPoint:anchorPoint toCoordinateSpace:fixed];
    CGRect screen = fixed.bounds;
    *pivot = (MWPoint){CGRectGetMidX(screen),CGRectGetMidY(screen)};
    return XMPlanHalfTurn(Math(window.transform),mapping,(MWPoint){fixedAnchor.x,fixedAnchor.y},*pivot,after);
}
static void Apply(UIWindow *window, MSXMWindowState *state) {
    if (!Enabled || B8Orientation() != UIInterfaceOrientationPortraitUpsideDown ||
        !IsTarget(window) || window.hidden) { Restore(window,state); return; }
    if (state.suspended || state->mutationDepth) return;
    if (state.applied) {
        if (!MWOwns(Math(window.transform),Math(state.after),YES,NO)) Restore(window,state);
        return;
    }
    MWTransform after; CGPoint old[3]; MWPoint pivot;
    if (Plan(window,&after,old,&pivot) != XMPlanApply) return;
    state.before = window.transform; state.after = CG(after); state.applied = YES;
    XMClearGeometryAnimations(window.layer);
    BOOL wasBusy = Busy; Busy = YES;
    @try { WriteTransform(window,state.after); }
    @finally { Busy = wasBusy; }
    for (unsigned i = 0; i < 3; ++i) {
        CGPoint point = [window convertPoint:i == 0 ? CGPointZero : (i == 1 ? CGPointMake(1,0) : CGPointMake(0,1)) toCoordinateSpace:window.screen.fixedCoordinateSpace];
        if (!isfinite(point.x) || !isfinite(point.y) ||
            fabs(point.x-(2*pivot.x-old[i].x)) > .1 || fabs(point.y-(2*pivot.y-old[i].y)) > .1) {
            Restore(window,state); state.suspended = YES;
            Log(@"Physical half-turn verification failed; restored owned transform");
            return;
        }
    }
}
static void Reconcile(void) {
    if (!Ready || Busy || !NSThread.isMainThread) return;
    Busy = YES;
    @try {
        if (Enabled && B8Disabled(Disabled)) Enabled = NO;
        for (UIWindow *window in Windows.allObjects) {
            MSXMWindowState *state = State(window);
            if (!state->mutationDepth) Apply(window,state);
        }
    } @finally { Busy = NO; }
}
static void Mutate(UIWindow *window, void (^original)(void)) {
    if (!Ready || Busy || !NSThread.isMainThread || object_getClass(window) != WindowClass) { original(); return; }
    [Windows addObject:window];
    MSXMWindowState *state = State(window);
    // Use per-window depth: a native update may also reposition a notification
    // window, which needs its own independent logical-layout transaction.
    BOOL mirror = state.applied;
    if (!mirror && !state.suspended && Enabled && !window.hidden && IsTarget(window) &&
        B8Orientation() == UIInterfaceOrientationPortraitUpsideDown) {
        MWTransform after; CGPoint old[3]; MWPoint pivot;
        mirror = Plan(window,&after,old,&pivot) == XMPlanApply;
    }
    void (^transaction)(void) = ^{
        XMRunGeometryMutation(&state->mutationDepth, ^{ Restore(window,state); }, original,
            ^{ Apply(window,state); });
    };
    // An animated logical frame plus an immediate mirrored translation has
    // incompatible presentation endpoints. Commit the owned outer geometry
    // atomically; native child transforms and alpha animations remain native.
    if (mirror) {
        XMClearGeometryAnimations(window.layer);
        [UIView performWithoutAnimation:transaction];
    }
    else transaction();
}

static void Frame(id self,SEL cmd,CGRect value) { Mutate(self,^{ OriginalFrame(self,cmd,value); }); }
static void Bounds(id self,SEL cmd,CGRect value) { Mutate(self,^{ OriginalBounds(self,cmd,value); }); }
static void Center(id self,SEL cmd,CGPoint value) { Mutate(self,^{ OriginalCenter(self,cmd,value); }); }
static void Transform(id self,SEL cmd,CGAffineTransform value) {
    MSXMWindowState *state = objc_getAssociatedObject(self,&StateKey);
    if (state.applied && MWNear(Math(value),Math(state.after))) { OriginalTransform(self,cmd,value); return; }
    Mutate(self,^{ OriginalTransform(self,cmd,value); });
}
static void Root(id self,SEL cmd,id value) { Mutate(self,^{ OriginalRoot(self,cmd,value); }); }
static void Scene(id self,SEL cmd,id value) { Mutate(self,^{ OriginalScene(self,cmd,value); }); }
static void Hidden(id self,SEL cmd,BOOL value) { Mutate(self,^{ OriginalHidden(self,cmd,value); }); }
static void Layout(id self,SEL cmd) { Mutate(self,^{ OriginalLayout(self,cmd); }); }

static BOOL IsPandaClass(Class cls) {
    const char *name = cls ? class_getImageName(cls) : NULL;
    if (!name) return NO;
    const char *base = strrchr(name,'/');
    return !strcmp(base ? base+1 : name,"MangoPanda.dylib");
}
static BOOL PandaMethod(Class cls, SEL selector, const char *type) {
    Method method = class_getInstanceMethod(cls,selector);
    if (!method || strcmp(method_getTypeEncoding(method),type)) return NO;
    const void *pointer = (const void *)method_getImplementation(method);
#if __has_feature(ptrauth_calls)
    pointer = ptrauth_strip(pointer,ptrauth_key_function_pointer);
#endif
    Dl_info info = {0};
    return dladdr(pointer,&info) && info.dli_fname &&
           !strcmp(strrchr(info.dli_fname,'/') ? strrchr(info.dli_fname,'/')+1 : info.dli_fname,"MangoPanda.dylib");
}
static BOOL Signature(SEL selector, NSArray<NSString *> *arguments) {
    Method method = class_getInstanceMethod(WindowClass,selector);
    if (!method || method_getNumberOfArguments(method) != arguments.count+2) return NO;
    char type[256] = {0}; method_getReturnType(method,type,sizeof(type));
    if (strcmp(type,"v")) return NO;
    for (NSUInteger i = 0; i < arguments.count; ++i) {
        memset(type,0,sizeof(type)); method_getArgumentType(method,(unsigned)i+2,type,sizeof(type));
        if (strcmp(type,arguments[i].UTF8String)) return NO;
    }
    return YES;
}
static void Install(void) {
    static unsigned attempts;
    if (Ready || B8Disabled(Disabled) || B8LegacyOrientationLoaded()) return;
    WindowClass = objc_getClass("XMFloatingWindow"); PortraitClass = objc_getClass("XMPortraitVC");
    if (!B8VerifiedMango() || !IsPandaClass(WindowClass) || !IsPandaClass(PortraitClass)) {
        if (++attempts < 40) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ Install(); });
        else Log(@"Not installed: matching Beta8 XiaoMang classes unavailable");
        return;
    }
    if (![WindowClass isSubclassOfClass:UIWindow.class] || ![PortraitClass isSubclassOfClass:UIViewController.class] ||
        !PandaMethod(WindowClass,@selector(hitTest:withEvent:),"@40@0:8{CGPoint=dd}16@32") ||
        !PandaMethod(PortraitClass,@selector(shouldAutorotate),"B16@0:8") ||
        !PandaMethod(PortraitClass,@selector(supportedInterfaceOrientations),"Q16@0:8")) {
        Log(@"Not installed: XiaoMang class or native method identity mismatch"); return;
    }
    NSArray *rect = @[[NSString stringWithUTF8String:@encode(CGRect)]];
    NSArray *point = @[[NSString stringWithUTF8String:@encode(CGPoint)]];
    NSArray *transform = @[[NSString stringWithUTF8String:@encode(CGAffineTransform)]];
    if (!Signature(@selector(setFrame:),rect) || !Signature(@selector(setBounds:),rect) ||
        !Signature(@selector(setCenter:),point) || !Signature(@selector(setTransform:),transform) ||
        !Signature(@selector(setRootViewController:),@[@"@"]) || !Signature(@selector(setWindowScene:),@[@"@"]) ||
        !Signature(@selector(setHidden:),@[[NSString stringWithUTF8String:@encode(BOOL)]]) ||
        !Signature(@selector(layoutSubviews),@[])) { Log(@"Not installed: window geometry method ABI mismatch"); return; }
    Windows = [NSHashTable weakObjectsHashTable]; Enabled = YES;
    MSHookMessageEx(WindowClass,@selector(setFrame:),(IMP)Frame,(IMP *)&OriginalFrame);
    MSHookMessageEx(WindowClass,@selector(setBounds:),(IMP)Bounds,(IMP *)&OriginalBounds);
    MSHookMessageEx(WindowClass,@selector(setCenter:),(IMP)Center,(IMP *)&OriginalCenter);
    MSHookMessageEx(WindowClass,@selector(setTransform:),(IMP)Transform,(IMP *)&OriginalTransform);
    MSHookMessageEx(WindowClass,@selector(setRootViewController:),(IMP)Root,(IMP *)&OriginalRoot);
    MSHookMessageEx(WindowClass,@selector(setWindowScene:),(IMP)Scene,(IMP *)&OriginalScene);
    MSHookMessageEx(WindowClass,@selector(setHidden:),(IMP)Hidden,(IMP *)&OriginalHidden);
    MSHookMessageEx(WindowClass,@selector(layoutSubviews),(IMP)Layout,(IMP *)&OriginalLayout);
    Ready = YES;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (object_getClass(window) == WindowClass) [Windows addObject:window];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) if (object_getClass(window) == WindowClass) [Windows addObject:window];
#pragma clang diagnostic pop
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange" object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            Reconcile(); dispatch_async(dispatch_get_main_queue(),^{ Reconcile(); });
        }];
    Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(Timer,^{ Reconcile(); if (!Enabled) dispatch_source_cancel(Timer); });
    dispatch_resume(Timer);
    Log(@"Beta8 floating-ball, panel and notification window adapter installed"); Reconcile();
}
__attribute__((constructor)) static void StartXiaoMang(void) {
    @autoreleasepool { dispatch_async(dispatch_get_main_queue(),^{ Install(); }); }
}
