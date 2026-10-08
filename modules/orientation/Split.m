// Beta8 Mango split windows only. No UIView/UIWindow-wide hooks.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>
#import "Beta9Identity.h"
#import "../../src/RuntimeDiagnostics.h"
#import "../../src/RuntimeSettings.h"
#include "SplitReconcile.h"
#include "RecoveryPolicy.h"
#include <math.h>

static const char *Disabled = "/var/mobile/Library/Preferences/MangoSplitUpsideDownFix.disabled";
static NSHashTable<UIWindow *> *Windows;
static BOOL Ready, Enabled, Busy;
static Class SceneClass, FloatingClass, LauncherClass;
static dispatch_source_t Timer;
static CADisplayLink *RecoveryLink;
static CFTimeInterval RecoveryUntil;
static char StateKey;
static char DiagnosticKey;
static NSString *DiagnosticSource = @"unknown";
static BOOL DiagnosticPass, DiagnosticActive;
static NSInteger DiagnosticMango, DiagnosticSystem, DiagnosticResolved, DiagnosticSampleResolved;
static NSHashTable<UIWindow *> *DiagnosticWindows, *DiagnosticSeen;
static unsigned DiagnosticSamples;

@interface MSB8SplitDiagnosticState : NSObject
@property(nonatomic) double lastSample, lastLog;
@property(nonatomic) BOOL sampled, target, hasModel;
@property(nonatomic) MWTransform model;
@property(nonatomic,copy) NSString *windowKey, *callbackKey;
@end
@implementation MSB8SplitDiagnosticState
@end

typedef struct {
    BOOL enabled, due, hasRead;
    unsigned reads;
    MWTransform model;
    MSSplitOwnership ownership;
    MSSplitSnapshot first, last;
    MSSplitSnapshot samples[4];
} MSSplitDiagnosticObservation;
static MSSplitDiagnosticObservation *DiagnosticRead;

@interface MSB8SplitState : NSObject
@property(nonatomic) MSSplitOwnership ownership;
@end
@implementation MSB8SplitState
@end

static MWTransform Math(CGAffineTransform t) { return (MWTransform){t.a,t.b,t.c,t.d,t.tx,t.ty}; }
static CGAffineTransform CG(MWTransform t) { return CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty); }
static void Log(NSString *s) {
    NSLog(@"[MangoSuiteSplit] %@", s);
    if (MSDiagnosticsActive()) MSDiagnosticsLog(@"Split", s);
}
static MSB8SplitState *State(UIWindow *w) { return objc_getAssociatedObject(w, &StateKey); }

static BOOL ContainsMangoTarget(UIWindow *window) {
    // Beta8's launcher controller can exist before its DecoratedFloatingView
    // has attached. Its class and lifecycle IMPs are verified at installation.
    if (LauncherClass && [window.rootViewController isKindOfClass:LauncherClass]) return YES;
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

// Diagnostic records never decide eligibility or write a view. At most 32
// live windows have diagnostic state, and a pass samples at most 32 windows.
static MSB8SplitDiagnosticState *DiagnosticState(UIWindow *w) {
    if (!w || !NSThread.isMainThread || !MSDiagnosticsActive()) return nil;
    MSB8SplitDiagnosticState *state = objc_getAssociatedObject(w, &DiagnosticKey);
    if (state) return state;
    if (!DiagnosticWindows) DiagnosticWindows = [NSHashTable weakObjectsHashTable];
    if (DiagnosticWindows.count >= 32) return nil;
    state = [MSB8SplitDiagnosticState new];
    objc_setAssociatedObject(w, &DiagnosticKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [DiagnosticWindows addObject:w];
    return state;
}

static NSString *DiagnosticTransform(MWTransform t) {
    return [NSString stringWithFormat:@"[%g,%g,%g,%g,%g,%g]", t.a,t.b,t.c,t.d,t.tx,t.ty];
}

static NSString *DiagnosticReads(MSSplitDiagnosticObservation observation) {
    NSMutableString *maps = [NSMutableString stringWithString:@"["];
    for (unsigned i = 0; i < observation.reads && i < 4; ++i) {
        MSSplitSnapshot s = observation.samples[i];
        MWTransform basis = {s.points[1].x-s.points[0].x,s.points[1].y-s.points[0].y,
            s.points[2].x-s.points[0].x,s.points[2].y-s.points[0].y,s.points[0].x,s.points[0].y};
        [maps appendFormat:@"%@{eligible:%d,model:%@,basis:%@}",i ? @"," : @"",s.eligible,
            DiagnosticTransform(s.transform),DiagnosticTransform(basis)];
    }
    [maps appendString:@"]"]; return maps;
}

static NSString *DiagnosticTarget(UIWindow *w) {
    if (LauncherClass && [w.rootViewController isKindOfClass:LauncherClass]) return @"launcher-root";
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:w];
    for (NSUInteger i = 0; i < queue.count; ++i) {
        if (queue.count > 2048) return @"traversal-cap";
        UIView *view = queue[i];
        if ([view isKindOfClass:SceneClass]) return @"scene";
        if ([view isKindOfClass:FloatingClass]) return @"floating";
        [queue addObjectsFromArray:view.subviews];
    }
    return @"none";
}

static NSString *DiagnosticSafeReason(UIWindow *w) {
    if (object_getClass(w) != UIWindow.class) return @"class";
    if (w.screen != UIScreen.mainScreen) return @"screen";
    if (!CATransform3DIsAffine(w.layer.transform)) return @"layer";
    if (!CATransform3DIsIdentity(w.layer.sublayerTransform)) return @"sublayer";
    CGPoint anchor = w.layer.anchorPoint;
    if (fabs(anchor.x - .5) > 1e-6 || fabs(anchor.y - .5) > 1e-6) return @"anchor";
    CGRect expected = w.screen.fixedCoordinateSpace.bounds;
    CGSize actual = w.bounds.size;
    if (!isfinite(actual.width) || !isfinite(actual.height) ||
        fabs(actual.width - expected.size.width) > 2 || fabs(actual.height - expected.size.height) > 2) return @"bounds";
    CGRect fixed = [w convertRect:w.bounds toCoordinateSpace:w.screen.fixedCoordinateSpace];
    if (!isfinite(fixed.origin.x) || !isfinite(fixed.origin.y) ||
        !isfinite(fixed.size.width) || !isfinite(fixed.size.height) ||
        !(fabs(CGRectGetMidX(fixed) - CGRectGetMidX(expected)) < 2) ||
        !(fabs(CGRectGetMidY(fixed) - CGRectGetMidY(expected)) < 2) ||
        !(fabs(fixed.size.width - expected.size.width) < 2) ||
        !(fabs(fixed.size.height - expected.size.height) < 2)) return @"footprint";
    return @"ok";
}

static MSSplitDiagnosticObservation DiagnosticPrepare(UIWindow *w) {
    MSSplitDiagnosticObservation observation = {0};
    if (!DiagnosticPass || !MSDiagnosticsActive() || DiagnosticSamples >= 32 ||
        [DiagnosticSeen containsObject:w]) return observation;
    @try {
    MSB8SplitDiagnosticState *state = DiagnosticState(w);
    if (!state) return observation;
    [DiagnosticSeen addObject:w]; ++DiagnosticSamples;
    observation.enabled = YES;
    observation.due = !state.sampled || CACurrentMediaTime() - state.lastSample >= 1;
    observation.model = Math(w.transform);
    MSB8SplitState *owned = State(w);
    if (owned) observation.ownership = owned.ownership;
    return observation;
    } @catch (__unused NSException *exception) { return (MSSplitDiagnosticObservation){0}; }
}

static void DiagnosticFinish(UIWindow *w, MSSplitDiagnosticObservation observation,
                             MSB8SplitState *owned, unsigned result) {
    if (!observation.enabled || !MSDiagnosticsActive() || (!observation.due && !result)) return;
    @try {
    MSB8SplitDiagnosticState *state = DiagnosticState(w);
    if (!state) return;
    double now = CACurrentMediaTime();
    if (!result && now - state.lastLog < 1 && state.windowKey) return;
    NSString *targetReason = DiagnosticTarget(w), *safeReason = DiagnosticSafeReason(w);
    BOOL target = ![targetReason isEqualToString:@"none"] && ![targetReason isEqualToString:@"traversal-cap"];
    BOOL safe = [safeReason isEqualToString:@"ok"];
    MWTransform model = Math(w.transform), basis = {NAN,NAN,NAN,NAN,NAN,NAN};
    id<UICoordinateSpace> fixed = w.screen.fixedCoordinateSpace;
    CGRect footprint = CGRectNull, screen = CGRectNull;
    if (fixed) {
        CGPoint o = [w convertPoint:CGPointZero toCoordinateSpace:fixed];
        CGPoint x = [w convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
        CGPoint y = [w convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
        basis = (MWTransform){x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y};
        footprint = [w convertRect:w.bounds toCoordinateSpace:fixed]; screen = fixed.bounds;
    }
    MSSplitOwnership before = observation.ownership, after = {0};
    if (owned) after = owned.ownership;
    NSString *key = [NSString stringWithFormat:
        @"enabled=%d active=%d rawMango=%ld systemStatusBar=%ld decisionResolved=%ld sampleResolved=%ld "
         "tracked=%d target=%@ safe=%@ observedEligible=%d rootVC=%@ sceneOrientation=%ld "
         "modelBefore=%@ modelAfter=%@ basis=%@ bounds=%@ anchor=%@ fixedFootprint=%@ screen=%@ "
         "ownershipBefore={applied:%d,suspended:%d,before:%@,after:%@} "
         "ownershipAfter={applied:%d,suspended:%d,before:%@,after:%@} "
         "reads=%u readSamples=%@ readEligibleFirst=%d readEligibleLast=%d readModelFirst=%@ "
         "readBasisUpright=%d readBasisInverted=%d readModelIdentity=%d "
         "result=%u restored=%d released=%d applied=%d rejected=%d",
        Enabled,DiagnosticActive,(long)DiagnosticMango,(long)DiagnosticSystem,
        (long)DiagnosticResolved,(long)DiagnosticSampleResolved,[Windows containsObject:w],
        targetReason,safeReason,target && safe,NSStringFromClass(w.rootViewController.class) ?: @"nil",
        (long)w.windowScene.interfaceOrientation,DiagnosticTransform(observation.model),DiagnosticTransform(model),
        DiagnosticTransform(basis),NSStringFromCGRect(w.bounds),NSStringFromCGPoint(w.layer.anchorPoint),
        NSStringFromCGRect(footprint),NSStringFromCGRect(screen),
        before.applied,before.suspended,DiagnosticTransform(before.before),DiagnosticTransform(before.after),
        after.applied,after.suspended,DiagnosticTransform(after.before),DiagnosticTransform(after.after),
        observation.reads,DiagnosticReads(observation),observation.hasRead ? observation.first.eligible : -1,
        observation.hasRead ? observation.last.eligible : -1,
        observation.hasRead ? DiagnosticTransform(observation.first.transform) : @"unread",
        observation.hasRead ? MSSplitUpright(observation.first) : -1,
        observation.hasRead ? MSSplitInverted(observation.first) : -1,
        observation.hasRead ? MWNear(observation.first.transform,(MWTransform){1,0,0,1,0,0}) : -1,
        result,!!(result & MSSplitRestored),!!(result & MSSplitReleased),
        !!(result & MSSplitApplied),!!(result & MSSplitRejected)];
    BOOL first = !state.sampled, lostTarget = state.sampled && state.target && !target;
    BOOL modelChanged = state.hasModel && !MWNear(state.model,model);
    state.lastSample = now; state.sampled = YES; state.target = target;
    state.hasModel = YES; state.model = model;
    if ([state.windowKey isEqualToString:key]) return;
    state.windowKey = key; state.lastLog = now;
    MSDiagnosticsLog(@"Split", [NSString stringWithFormat:
        @"WINDOW source=%@ window=%p newWindow=%d targetLost=%d observedModelChanged=%d %@",
        DiagnosticSource,(__bridge void *)w,first,lostTarget,modelChanged,key]);
    } @catch (__unused NSException *exception) { /* Diagnostic failure never changes reconciliation. */ }
}

static void DiagnosticBegin(BOOL active, NSInteger resolved, NSArray<UIWindow *> *all) {
    DiagnosticPass = MSDiagnosticsActive();
    if (!DiagnosticPass) return;
    @try {
    DiagnosticActive = active; DiagnosticResolved = resolved;
    // These raw values are an immediate, independent main-thread sample. The
    // stored decisionResolved is the actual existing B9Orientation call above.
    DiagnosticMango = B9MangoOrientation(); DiagnosticSystem = B9SystemOrientation();
    DiagnosticSampleResolved = MSB8ResolvedOrientation(DiagnosticMango,DiagnosticSystem);
    DiagnosticSeen = [NSHashTable weakObjectsHashTable]; DiagnosticSamples = 0;
    NSUInteger candidates = 0;
    for (UIWindow *w in all) if (object_getClass(w) == UIWindow.class) ++candidates;
    NSString *key = [NSString stringWithFormat:
        @"enabled=%d active=%d rawMango=%ld systemStatusBar=%ld decisionResolved=%ld sampleResolved=%ld "
         "allWindows=%lu plainCandidates=%lu trackedWindows=%lu liveDiagnosticWindows=%lu sampleLimit=32 launcherHook=%d",
        Enabled,active,(long)DiagnosticMango,(long)DiagnosticSystem,(long)resolved,(long)DiagnosticSampleResolved,
        (unsigned long)all.count,(unsigned long)candidates,(unsigned long)Windows.count,
        (unsigned long)DiagnosticWindows.count,LauncherClass != Nil];
    static NSString *lastKey; static double lastLog;
    double now = CACurrentMediaTime();
    if (![lastKey isEqualToString:key] && now - lastLog >= 1) {
        lastKey = key; lastLog = now;
        MSDiagnosticsLog(@"Split", [NSString stringWithFormat:@"PASS source=%@ %@",DiagnosticSource,key]);
    }
    } @catch (__unused NSException *exception) { DiagnosticPass = NO; DiagnosticSeen = nil; }
}

static MSSplitSnapshot Snapshot(void *context) {
    UIWindow *w = (__bridge UIWindow *)context;
    MSSplitSnapshot sample = {.transform = Math(w.transform)};
    sample.eligible = ContainsMangoTarget(w) && SafeWindow(w);
    // Eligibility is a pre-write guard. The write can change UIKit's window
    // footprint while it settles; Beta8.2 still sampled these points to verify
    // the value it had just written, without another SafeWindow veto.
    id<UICoordinateSpace> fixed = w.screen.fixedCoordinateSpace;
    const CGPoint local[3] = {CGPointZero, CGPointMake(1,0), CGPointMake(0,1)};
    for (unsigned i = 0; i < 3; ++i) {
        CGPoint p = [w convertPoint:local[i] toCoordinateSpace:fixed];
        sample.points[i] = (MWPoint){p.x,p.y};
    }
    CGRect screen = fixed.bounds;
    sample.center = (MWPoint){w.center.x,w.center.y};
    sample.pivot = (MWPoint){CGRectGetMidX(screen),CGRectGetMidY(screen)};
    if (DiagnosticRead && DiagnosticRead->enabled && MSDiagnosticsActive()) {
        if (!DiagnosticRead->hasRead) { DiagnosticRead->first = sample; DiagnosticRead->hasRead = YES; }
        if (DiagnosticRead->reads < 4) DiagnosticRead->samples[DiagnosticRead->reads] = sample;
        DiagnosticRead->last = sample; ++DiagnosticRead->reads;
    }
    return sample;
}

static void WriteSnapshot(void *context, MWTransform transform) {
    Write((__bridge UIWindow *)context, CG(transform));
}

static void Update(UIWindow *w, BOOL active) {
    MSB8SplitState *state = State(w);
    MSSplitDiagnosticObservation observation = DiagnosticPrepare(w);
    if (!state) {
        if (!active || !ContainsMangoTarget(w) || !SafeWindow(w)) {
            DiagnosticFinish(w, observation, nil, 0); return;
        }
        state = [MSB8SplitState new];
        objc_setAssociatedObject(w, &StateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    MSSplitOwnership ownership = state.ownership;
    unsigned result = 0;
    MSSplitDiagnosticObservation *previousRead = DiagnosticRead;
    DiagnosticRead = observation.enabled ? &observation : NULL;
    @try {
        result = MSSplitReconcileRecovery(&ownership, active, MSRuntimeFlag(@"LauncherRecoveryEnabled"), Snapshot, WriteSnapshot, (__bridge void *)w);
    } @finally { state.ownership = ownership; DiagnosticRead = previousRead; }
    DiagnosticFinish(w, observation, state, result);
    if (result & MSSplitReleased) Log(@"Owned split transform replaced externally; ownership released");
    if (result & MSSplitRejected) Log(@"Split coordinate verification failed; correction suspended until geometry changes");
}

static void Reconcile(void) {
    if (!Ready || Busy || !NSThread.isMainThread) return;
    Busy = YES;
    @try {
        if (Enabled && B9Disabled(Disabled)) Enabled = NO;
        NSInteger resolved = UIInterfaceOrientationUnknown;
        resolved = B9Orientation();
        static double lastInverted=-INFINITY;
        if (MSRuntimeFlag(@"LauncherRecoveryEnabled")) resolved=MSRecoverOrientation(resolved,MSNativeInversionRequested(),CACurrentMediaTime(),&lastInverted);
        BOOL active = Enabled && resolved == UIInterfaceOrientationPortraitUpsideDown;
        NSArray<UIWindow *> *all = nil;
        if (active) {
            all = AllWindows();
            for (UIWindow *w in all)
                if (object_getClass(w) == UIWindow.class && ContainsMangoTarget(w)) [Windows addObject:w];
        }
        if (MSDiagnosticsActive()) {
            @try {
                if (!all) all = AllWindows();
                DiagnosticBegin(active, resolved, all);
            } @catch (__unused NSException *exception) { DiagnosticPass = NO; }
        }
        for (UIWindow *w in Windows.allObjects) Update(w, active);
        // Inactive windows can lack patch ownership. The fallback observes
        // exact plain UIWindows only; it never adds them to the real Windows.
        if (DiagnosticPass && MSDiagnosticsActive())
            for (UIWindow *w in all) {
                if (DiagnosticSamples >= 32) break;
                if (object_getClass(w) != UIWindow.class || [DiagnosticSeen containsObject:w]) continue;
                MSSplitDiagnosticObservation observation = DiagnosticPrepare(w);
                DiagnosticFinish(w, observation, State(w), 0);
            }
    } @finally { DiagnosticPass = NO; DiagnosticSeen = nil; Busy = NO; }
}

static void ReconcileFrom(NSString *source) {
    NSString *previous = DiagnosticSource; DiagnosticSource = source;
    @try { Reconcile(); } @finally { DiagnosticSource = previous; }
}

@interface MSSplitRecoveryObserver : NSObject
- (void)tick:(CADisplayLink *)link;
@end
@implementation MSSplitRecoveryObserver
- (void)tick:(CADisplayLink *)link {
    if (!Enabled || !MSRuntimeFlag(@"LauncherRecoveryEnabled") || CACurrentMediaTime() > RecoveryUntil) {
        link.paused = YES; return;
    }
    ReconcileFrom(@"reopen-presentation-frame");
}
@end
static void ArmRecovery(void) {
    if (!MSRuntimeFlag(@"LauncherRecoveryEnabled")) return;
    RecoveryUntil = CACurrentMediaTime()+1.2;
    RecoveryLink.paused = NO;
}

// Mango-owned class lifecycle callbacks give immediate updates as split
// windows attach or relayout. A slow timer handles direction changes and
// windows not enumerated by public scene APIs; it is not an animation driver.
static void (*SceneMove)(id,SEL), (*FloatingMove)(id,SEL);
static void (*SceneLayout)(id,SEL), (*FloatingLayout)(id,SEL);
static void (*LauncherRotation)(id,SEL), (*LauncherLayout)(id,SEL);
static void AfterLifecycle(UIView *view, NSString *source) {
    if (!Ready || Busy || !NSThread.isMainThread) return;
    UIWindow *w = view.window;
    if (object_getClass(w) == UIWindow.class) [Windows addObject:w];
    ReconcileFrom(source);
    ArmRecovery();
    // Dock/library reopen may reset the window after this native callback.
    dispatch_async(dispatch_get_main_queue(), ^{ ReconcileFrom(@"reopen-next-turn"); });
}
static void (*FloatingHidden)(id,SEL,BOOL), (*SceneHidden)(id,SEL,BOOL);
static void HookFloatingHidden(id self,SEL cmd,BOOL hidden) { FloatingHidden(self,cmd,hidden); if (!hidden) AfterLifecycle(self,@"floating-reveal"); }
static void HookSceneHidden(id self,SEL cmd,BOOL hidden) { SceneHidden(self,cmd,hidden); if (!hidden) AfterLifecycle(self,@"scene-reveal"); }
static void HookSceneMove(id self,SEL cmd) { SceneMove(self,cmd); AfterLifecycle(self,@"scene-move"); }
static void HookFloatingMove(id self,SEL cmd) { FloatingMove(self,cmd); AfterLifecycle(self,@"floating-move"); }
static void HookSceneLayout(id self,SEL cmd) { SceneLayout(self,cmd); AfterLifecycle(self,@"scene-layout"); }
static void HookFloatingLayout(id self,SEL cmd) { FloatingLayout(self,cmd); AfterLifecycle(self,@"floating-layout"); }
static void AfterLauncherLifecycle(UIViewController *controller, NSString *source) {
    if (!Ready || !NSThread.isMainThread) return;
    if (controller.isViewLoaded) AfterLifecycle(controller.view,source);
}

typedef struct {
    BOOL enabled, loaded, owns;
    void *window;
    MWTransform model;
    int applied, suspended;
} MSSplitLauncherDiagnostic;

static MSSplitLauncherDiagnostic DiagnosticLauncherRead(UIViewController *controller,
                                                        UIWindow * __weak *window) {
    MSSplitLauncherDiagnostic sample = {.model = {NAN,NAN,NAN,NAN,NAN,NAN}};
    if (!Ready || !NSThread.isMainThread || !MSDiagnosticsActive()) return sample;
    @try {
    sample.loaded = controller.isViewLoaded;
    if (sample.loaded) {
        UIWindow *w = controller.view.window;
        if (w && !DiagnosticState(w)) return sample;
        *window = w; sample.window = (__bridge void *)w;
        if (w) {
            sample.model = Math(w.transform);
            MSB8SplitState *state = State(w);
            if (state) {
                MSSplitOwnership owned = state.ownership;
                sample.applied = owned.applied; sample.suspended = owned.suspended;
                sample.owns = MWOwns(sample.model,owned.after,owned.applied,owned.suspended);
            }
        }
    }
    sample.enabled = YES;
    return sample;
    } @catch (__unused NSException *exception) { return (MSSplitLauncherDiagnostic){0}; }
}

static void DiagnosticLauncherFinish(UIViewController *controller, NSString *source,
                                      MSSplitLauncherDiagnostic before, UIWindow *beforeWindow) {
    if (!NSThread.isMainThread || !MSDiagnosticsActive()) return;
    @try {
    __weak UIWindow *afterWindow = nil;
    MSSplitLauncherDiagnostic after = DiagnosticLauncherRead(controller,&afterWindow);
    if (!before.enabled && !after.enabled) return;
    BOOL changedWindow = before.enabled && after.enabled && before.window != after.window;
    BOOL changedModel = before.enabled && after.enabled && before.window && before.window == after.window &&
        !MWNear(before.model,after.model);
    NSString *key = [NSString stringWithFormat:
        @"source=%@ controller=%p beforeRead=%d afterRead=%d beforeLoaded=%d afterLoaded=%d "
         "beforeWindow=%p afterWindow=%p modelBefore=%@ modelAfter=%@ "
         "beforeApplied=%d afterApplied=%d beforeSuspended=%d afterSuspended=%d "
         "beforeMatchesOwned=%d afterMatchesOwned=%d windowChanged=%d modelChangedDuringCallback=%d",
        source,(__bridge void *)controller,before.enabled,after.enabled,before.loaded,after.loaded,
        before.window,after.window,DiagnosticTransform(before.model),DiagnosticTransform(after.model),
        before.applied,after.applied,before.suspended,after.suspended,before.owns,after.owns,
        changedWindow,changedModel];
    // This only brackets the supplied original callback. Nested native work
    // can run here too, so it does not identify a particular transform writer.
    MSB8SplitDiagnosticState *state = DiagnosticState(afterWindow ?: beforeWindow);
    double now = CACurrentMediaTime();
    if (state) {
        if ([state.callbackKey isEqualToString:key] ||
            (!changedWindow && !changedModel && now - state.lastLog < 1)) return;
        state.callbackKey = key; state.lastLog = now;
    } else {
        static NSString *lastKey; static double lastLog;
        if ([lastKey isEqualToString:key] || now - lastLog < 1) return;
        lastKey = key; lastLog = now;
    }
    MSDiagnosticsLog(@"Split", [@"CALLBACK " stringByAppendingString:key]);
    } @catch (__unused NSException *exception) { /* Still call the existing lifecycle path. */ }
}

static void HookLauncherRotation(id self,SEL cmd) {
    __weak UIWindow *window = nil;
    MSSplitLauncherDiagnostic before = DiagnosticLauncherRead(self,&window);
    LauncherRotation(self,cmd);
    DiagnosticLauncherFinish(self,@"launcher-rotation",before,window);
    AfterLauncherLifecycle(self,@"launcher-rotation");
}
static void HookLauncherLayout(id self,SEL cmd) {
    __weak UIWindow *window = nil;
    MSSplitLauncherDiagnostic before = DiagnosticLauncherRead(self,&window);
    LauncherLayout(self,cmd);
    DiagnosticLauncherFinish(self,@"launcher-layout",before,window);
    AfterLauncherLifecycle(self,@"launcher-layout");
}

static BOOL VoidMethod(Class cls, SEL selector) {
    Method m = class_getInstanceMethod(cls, selector);
    return m && !strcmp(method_getTypeEncoding(m), "v16@0:8");
}

static void Install(void) {
    static unsigned attempts;
    if (Ready || B9Disabled(Disabled) || B9LegacyOrientationLoaded()) return;
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
    SceneClass = objc_getClass("DecoratedAppSceneView");
    FloatingClass = objc_getClass("DecoratedFloatingView");
    if (!B9VerifiedMango() || !SceneClass || !FloatingClass) {
        if (++attempts < 40) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ Install(); });
        else Log(@"Split unavailable: matching Beta9 images/classes not loaded");
        return;
    }
    for (Class cls in @[SceneClass, FloatingClass])
        if (!VoidMethod(cls, @selector(didMoveToWindow)) || !VoidMethod(cls, @selector(layoutSubviews))) {
            Log(@"Split unavailable: Mango lifecycle method ABI mismatch"); return;
        }
    // Only the supplied Hello controller may provide these extra entry points.
    // Its native portrait launcher update writes child transforms to identity;
    // those local transforms inherit our window turn and remain native-owned.
    Class launcher = objc_getClass("ViewController");
    SEL rotation = sel_registerName("mango_updateLauncherRotation");
    SEL layout = @selector(viewDidLayoutSubviews);
    if (B9ClassIsHello(launcher) && VoidMethod(launcher, rotation) && VoidMethod(launcher, layout) &&
        B9IMPIsHello(class_getMethodImplementation(launcher, rotation)) &&
        B9IMPIsHello(class_getMethodImplementation(launcher, layout))) LauncherClass = launcher;
    Windows = [NSHashTable weakObjectsHashTable]; Enabled = YES; Ready = YES;
    static MSSplitRecoveryObserver *observer;
    observer = [MSSplitRecoveryObserver new];
    RecoveryLink = [CADisplayLink displayLinkWithTarget:observer selector:@selector(tick:)];
    RecoveryLink.preferredFramesPerSecond = 60;
    [RecoveryLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    RecoveryLink.paused = YES;
    MSHookMessageEx(SceneClass,@selector(didMoveToWindow),(IMP)HookSceneMove,(IMP *)&SceneMove);
    MSHookMessageEx(FloatingClass,@selector(didMoveToWindow),(IMP)HookFloatingMove,(IMP *)&FloatingMove);
    MSHookMessageEx(SceneClass,@selector(layoutSubviews),(IMP)HookSceneLayout,(IMP *)&SceneLayout);
    MSHookMessageEx(FloatingClass,@selector(layoutSubviews),(IMP)HookFloatingLayout,(IMP *)&FloatingLayout);
    Method sceneHidden = class_getInstanceMethod(SceneClass, @selector(setHidden:));
    Method floatingHidden = class_getInstanceMethod(FloatingClass, @selector(setHidden:));
    if (sceneHidden && !strcmp(method_getTypeEncoding(sceneHidden), "v20@0:8B16"))
        MSHookMessageEx(SceneClass,@selector(setHidden:),(IMP)HookSceneHidden,(IMP *)&SceneHidden);
    if (floatingHidden && !strcmp(method_getTypeEncoding(floatingHidden), "v20@0:8B16"))
        MSHookMessageEx(FloatingClass,@selector(setHidden:),(IMP)HookFloatingHidden,(IMP *)&FloatingHidden);
    if (LauncherClass) {
        MSHookMessageEx(LauncherClass,rotation,(IMP)HookLauncherRotation,(IMP *)&LauncherRotation);
        MSHookMessageEx(LauncherClass,layout,(IMP)HookLauncherLayout,(IMP *)&LauncherLayout);
    }
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            ReconcileFrom(@"orientation-notification");
            dispatch_async(dispatch_get_main_queue(), ^{ ReconcileFrom(@"orientation-notification-deferred"); });
        }];
    Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),350*NSEC_PER_MSEC,75*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(Timer, ^{ ReconcileFrom(@"timer"); if (!Enabled) dispatch_source_cancel(Timer); });
    dispatch_resume(Timer);
    Log(@"Beta9 split installed; pre-existing rotations preserved"); ReconcileFrom(@"install");
}

__attribute__((constructor)) static void StartSplit(void) {
    @autoreleasepool { dispatch_async(dispatch_get_main_queue(), ^{ Install(); }); }
}
