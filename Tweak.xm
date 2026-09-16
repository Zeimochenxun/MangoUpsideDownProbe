// Experimental positioning fix. Private names below are evidenced in the
// supplied Mango image or the user's 04_final_parent_chain.log; see EVIDENCE.md.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <substrate.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <string.h>
#include <errno.h>
#include "Geometry.h"

static const char *kDisabled = "/var/mobile/Library/Preferences/MangoUpsideDownFix.disabled";
static const char *kNoProbe = "/var/mobile/Library/Preferences/MangoUpsideDownFix.noprobe";
static const char *kLogPath = "/var/mobile/Library/Logs/MangoUpsideDownFix.log";
// A host that never reaches the aperture path is released instead of being
// retried forever; the cap bounds work if Mango churns short-lived hosts.
static const NSUInteger kPendingCap = 64;
static const double kPendingTTL = 30.0;
static Class gContainerClass, gWindowClass, gContentClass;
static NSHashTable<UIView *> *gContainers;
static NSMutableArray *gPending;
static dispatch_source_t gTimer;
static BOOL gInstalled, gEnabled, gProbe, gResolving, gProbeQuery;
static unsigned gOwnWrite, gAttempts, gLayoutDepth, gPendingSeen, gPendingExpired;
static double gPendingLog, gExpiryLog, gInsideLog, gWindowHitLog, gWindowInsideLog;
static char kStateKey;

// Our own class, not a Mango class. References to the private hierarchy are weak.
@interface MUDFFixState : NSObject
@property(nonatomic, strong) NSHashTable<UIView *> *hosts;
@property(nonatomic, weak) UIView *parent;
@property(nonatomic) CGAffineTransform baseline;
@property(nonatomic) CGAffineTransform appliedTransform;
@property(nonatomic) BOOL applied;
@property(nonatomic) BOOL suspended;
@property(nonatomic) unsigned mutationDepth;
@property(nonatomic) double lastLog;
@property(nonatomic) double lastChainLog;
@property(nonatomic) BOOL loggedInteraction;
@end
@implementation MUDFFixState
@end

// A Mango host seen before it was attached to the aperture window. The weak
// reference means a discarded host cannot keep a private view alive.
@interface MUDFPendingHost : NSObject
@property(nonatomic, weak) UIView *host;
@property(nonatomic) double firstSeen;
@end
@implementation MUDFPendingHost
@end

static void Log(NSString *message) {
    if (![NSThread isMainThread]) return;
    NSLog(@"[MangoUDFix] %@", message);
    mkdir("/var/mobile/Library/Logs", 0755);
    int fd = open(kLogPath, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW, 0600);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return; }
    if (st.st_size > 512*1024) ftruncate(fd, 0);
    NSData *bytes = [[NSString stringWithFormat:@"%.3f [MangoUDFix] %@\n",
                      NSDate.timeIntervalSinceReferenceDate, message]
                    dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *p = (const uint8_t *)bytes.bytes;
    size_t left = bytes.length;
    while (left) {
        ssize_t n = write(fd, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        p += n; left -= (size_t)n;
    }
    close(fd);
}

static MUDFAffine Affine(CGAffineTransform t) {
    return (MUDFAffine){t.a,t.b,t.c,t.d,t.tx,t.ty};
}
static CGAffineTransform CGAffine(MUDFAffine t) {
    return CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty);
}
static MUDFRect MUDFRectFromCGRect(CGRect r) {
    return (MUDFRect){r.origin.x,r.origin.y,r.size.width,r.size.height};
}
static CGRect CGRectFromMUDF(MUDFRect r) {
    return CGRectMake(r.x,r.y,r.width,r.height);
}
static BOOL Near(CGAffineTransform a, CGAffineTransform b) {
    return MUDFAffineNear(Affine(a), Affine(b));
}
static MUDFFixState *State(UIView *v) {
    return (MUDFFixState *)objc_getAssociatedObject(v, &kStateKey);
}
static void StateLog(MUDFFixState *s, NSString *message) {
    double now = CACurrentMediaTime();
    if (now-s.lastLog < 1.0) return;
    s.lastLog = now; Log(message);
}
// Rate limiter for diagnostics that can fire at event or layout frequency.
static void RateLog(double *slot, double interval, NSString *message) {
    double now = CACurrentMediaTime();
    if (now-*slot < interval) return;
    *slot = now; Log(message);
}

static NSInteger MangoOrientation(void) {
    Class c = objc_getClass("DecoratedAppSceneView");
    SEL sel = sel_registerName("mango_currentInterfaceOrientation");
    Method m = c ? class_getClassMethod(c, sel) : NULL;
    if (!m || method_getNumberOfArguments(m) != 2) return -1;
    char type[64] = {0}; method_getReturnType(m, type, sizeof(type));
    if (strcmp(type, @encode(NSInteger)) != 0) return -1;
    return ((NSInteger (*)(id,SEL))objc_msgSend)((id)c, sel);
}

static void WriteTransform(UIView *v, CGAffineTransform t) {
    // Only our translation changes are non-animated. Never remove system
    // animation keys, change anchorPoint, or modify a child content transform.
    ++gOwnWrite;
    @try { [UIView performWithoutAnimation:^{ v.transform = t; }]; }
    @finally { --gOwnWrite; }
}

static void Restore(UIView *v, MUDFFixState *s, NSString *reason) {
    if (!s.applied) return;
    if (Near(v.transform, s.appliedTransform)) {
        WriteTransform(v, s.baseline);
        if (reason) Log([NSString stringWithFormat:@"RESTORE %@ container=%p", reason, (__bridge void *)v]);
    } else {
        // A direct CALayer write or another hook bypassed our setter tracking.
        // Do not overwrite an unknown transform; freeze this instance until respring.
        s.suspended = YES;
        Log(@"CONFLICT untracked transform change; instance suspended, respring required for clean reset");
    }
    s.applied = NO;
}

static UIView *FindAncestor(UIView *host, Class cls) {
    UIView *v = host;
    for (unsigned i=0; v && i<16; ++i, v=v.superview)
        if ([v isKindOfClass:cls]) return v;
    return nil;
}

static UIView *CurrentHost(UIView *container, MUDFFixState *s) {
    for (UIView *host in s.hosts.allObjects)
        if (FindAncestor(host, gContainerClass) == container) return host;
    return nil;
}

static BOOL AffineHierarchy(UIView *v) {
    for (unsigned depth=0; v && depth<20; ++depth, v=v.superview) {
        if (!CATransform3DIsAffine(v.layer.transform) ||
            !CATransform3DIsIdentity(v.layer.sublayerTransform)) return NO;
        if ([v isKindOfClass:[UIWindow class]]) return YES;
    }
    return NO;
}

static BOOL ContentIsUpsideDown(UIView *host, UIView *container, id<UICoordinateSpace> fixed) {
    UIView *content = FindAncestor(host, gContentClass);
    if (!content || FindAncestor(content, gContainerClass) != container) return NO;
    CGPoint o = [content convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x = [content convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y = [content convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    double ax=x.x-o.x, ay=x.y-o.y, bx=y.x-o.x, by=y.y-o.y;
    return isfinite(ax) && isfinite(ay) && isfinite(bx) && isfinite(by) &&
           ax < -1e-5 && by < -1e-5 && fabs(ay) < fabs(ax)*1e-3 &&
           fabs(bx) < fabs(by)*1e-3;
}

static void Update(UIView *v) {
    MUDFFixState *s = State(v);
    if (!s || s.mutationDepth || gOwnWrite || gLayoutDepth || ![NSThread isMainThread]) return;
    if (s.applied && !Near(v.transform, s.appliedTransform)) {
        Restore(v, s, @"transform-conflict"); return;
    }
    if (s.suspended) return;
    if (!gEnabled || MangoOrientation() != UIInterfaceOrientationPortraitUpsideDown) {
        Restore(v, s, gEnabled ? @"orientation" : @"disabled"); return;
    }
    UIView *host = CurrentHost(v, s);
    UIView *parent = v.superview;
    UIWindow *window = v.window;
    if (!host || !parent || ![window isKindOfClass:gWindowClass] ||
        window.screen != UIScreen.mainScreen) {
        Restore(v, s, @"host-or-window-detached"); return;
    }
    if (s.applied && s.parent != parent) Restore(v, s, @"parent-changed");
    if (s.suspended) return;
    s.parent = parent;
    id<UICoordinateSpace> fixed = window.screen.fixedCoordinateSpace;
    if (!AffineHierarchy(host) || !ContentIsUpsideDown(host, v, fixed)) {
        Restore(v, s, @"unsupported-or-transitioning-coordinate-space");
        StateLog(s, @"SKIP content basis is not the evidenced 180-degree affine configuration");
        return;
    }
    CGPoint o=[parent convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x=[parent convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y=[parent convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    MUDFAffine map={x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y};
    MUDFRect current=MUDFRectFromCGRect([v convertRect:v.bounds toCoordinateSpace:fixed]);
    MUDFRect baseline=current;
    CGAffineTransform base = s.applied ? s.baseline : v.transform;
    if (s.applied) {
        MUDFPoint own={s.appliedTransform.tx-base.tx, s.appliedTransform.ty-base.ty};
        baseline=MUDFBaselineRect(current,map,own);
    }
    MUDFPoint delta; MUDFRect target;
    MUDFPlanResult result=MUDFPlan(MUDFRectFromCGRect(fixed.bounds),baseline,map,&delta,&target);
    if (result != MUDFPlanOK) {
        Restore(v,s,@"geometry-guard");
        StateLog(s,result==MUDFPlanAlreadyAtOtherEdge ?
                 @"SKIP baseline already lies in lower screen half" : @"SKIP invalid geometry");
        return;
    }
    CGAffineTransform desired=CGAffine(MUDFWithTranslation(Affine(base),delta));
    s.baseline=base;
    s.appliedTransform=desired;
    s.applied=YES;
    if (!Near(v.transform,desired)) WriteTransform(v,desired);
    // A post-write check proves model geometry only; not animation or hit testing.
    CGRect after=[v convertRect:v.bounds toCoordinateSpace:fixed];
    if (!MUDFFiniteRect(MUDFRectFromCGRect(after)) || fabs(CGRectGetMinY(after)-target.y) > 1.0 ||
        fabs(CGRectGetMinX(after)-target.x) > 1.0) {
        Restore(v,s,@"post-write-mismatch"); s.suspended=YES;
        Log(@"SUSPEND geometry verification failed for this instance"); return;
    }
    StateLog(s,[NSString stringWithFormat:
        @"APPLY orientation=2 container=%p baselineFixed=%@ targetFixed=%@ actualFixed=%@ deltaParent={%.3f,%.3f} hostAlpha=%.3f containerAlpha=%.3f",
        (__bridge void *)v,NSStringFromCGRect(CGRectFromMUDF(baseline)),
        NSStringFromCGRect(CGRectFromMUDF(target)),NSStringFromCGRect(after),
        delta.x,delta.y,host.alpha,v.alpha]);
}

static void UpdateAll(void) {
    if (![NSThread isMainThread]) return;
    for (UIView *v in gContainers.allObjects) Update(v);
}

static void RefreshEnabled(void) {
    if (gEnabled && access(kDisabled,F_OK)==0) {
        gEnabled=NO; gProbe=NO;
        [gPending removeAllObjects];
        UpdateAll();
        Log(@"DISABLED marker detected; known translations restored; remove marker and respring to re-enable");
    }
}

static MUDFFixState *BeginMutation(UIView *v) {
    if (gOwnWrite || ![NSThread isMainThread]) return nil;
    MUDFFixState *s=State(v);
    if (!s || s.suspended) return nil;
    if (s.mutationDepth==0) Restore(v,s,nil);
    ++s.mutationDepth;
    return s;
}
static void EndMutation(UIView *v, MUDFFixState *s) {
    if (!s) return;
    --s.mutationDepth;
    if (s.mutationDepth==0) Update(v);
}

// These are PUBLIC UIView selectors, checked at runtime on the evidenced
// SBSystemApertureContainerView class. No global UIView or UIWindow hooks.
static void (*OrigLayout)(id,SEL);
static void HookLayout(id self,SEL cmd) {
    MUDFFixState *s=BeginMutation(self);
    BOOL main=[NSThread isMainThread];
    if(main)++gLayoutDepth;
    @try { OrigLayout(self,cmd); }
    @finally {
        if(main)--gLayoutDepth;
        EndMutation(self,s);
        // A Mango callback may have first registered this container during orig.
        if(main && !s)Update(self);
    }
}
static void (*OrigFrame)(id,SEL,CGRect);
static void HookFrame(id self,SEL cmd,CGRect value) {
    MUDFFixState *s=BeginMutation(self);
    @try { OrigFrame(self,cmd,value); } @finally { EndMutation(self,s); }
}
static void (*OrigBounds)(id,SEL,CGRect);
static void HookBounds(id self,SEL cmd,CGRect value) {
    MUDFFixState *s=BeginMutation(self);
    @try { OrigBounds(self,cmd,value); } @finally { EndMutation(self,s); }
}
static void (*OrigCenter)(id,SEL,CGPoint);
static void HookCenter(id self,SEL cmd,CGPoint value) {
    MUDFFixState *s=BeginMutation(self);
    @try { OrigCenter(self,cmd,value); } @finally { EndMutation(self,s); }
}
static void (*OrigTransform)(id,SEL,CGAffineTransform);
static void HookTransform(id self,SEL cmd,CGAffineTransform value) {
    MUDFFixState *s=BeginMutation(self);
    @try { OrigTransform(self,cmd,value); } @finally { EndMutation(self,s); }
}
static void (*OrigMove)(id,SEL);
static void HookMove(id self,SEL cmd) {
    MUDFFixState *s=BeginMutation(self);
    @try { OrigMove(self,cmd); } @finally { EndMutation(self,s); }
}

// Associates a Mango host with its aperture container. Returns NO while the
// host is not yet under a container inside the aperture window, which is the
// state the compact island was previously discarded in.
static BOOL TrackHost(UIView *host) {
    UIView *v = FindAncestor(host, gContainerClass);
    if (!v || ![v.window isKindOfClass:gWindowClass]) return NO;
    MUDFFixState *s = State(v);
    if (!s) {
        s = [MUDFFixState new]; s.hosts = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(v, &kStateKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gContainers addObject:v];
        Log([NSString stringWithFormat:@"TRACK Mango host=%p container=%p",
             (__bridge void *)host, (__bridge void *)v]);
    }
    [s.hosts addObject:host];
    // A layout in progress can have intermediate geometry; validate again after
    // it returns. Immediate update is guarded by the container mutation depth.
    Update(v);
    __weak UIView *weakView = v;
    dispatch_async(dispatch_get_main_queue(), ^{ if (weakView) Update(weakView); });
    return YES;
}

static void AddPending(UIView *host) {
    for (MUDFPendingHost *p in gPending) if (p.host == host) return;
    if (gPending.count >= kPendingCap) {
        RateLog(&gPendingLog, 5.0, [NSString stringWithFormat:
            @"PENDING cap %lu reached; not queueing more unattached hosts this cycle",
            (unsigned long)kPendingCap]);
        return;
    }
    MUDFPendingHost *p = [MUDFPendingHost new];
    p.host = host; p.firstSeen = CACurrentMediaTime();
    [gPending addObject:p];
    ++gPendingSeen;
    RateLog(&gPendingLog, 1.0, [NSString stringWithFormat:
        @"PENDING host=%p queued (no aperture container yet); queued=%lu seen=%u",
        (__bridge void *)host, (unsigned long)gPending.count, gPendingSeen]);
}

// Re-checks queued hosts on the main queue. Hosts that attach later get the
// same treatment as hosts that were already attached at callback time.
// TrackHost can re-enter this through layout, so the queue is walked over a
// snapshot and entries are removed by identity, never by index.
static void ResolvePending(void) {
    if (!gPending.count || gResolving || ![NSThread isMainThread]) return;
    gResolving = YES;
    @try {
        double now = CACurrentMediaTime();
        for (MUDFPendingHost *p in [gPending copy]) {
            UIView *host = p.host;
            if (!host) { [gPending removeObject:p]; continue; }
            if (gEnabled && TrackHost(host)) {
                [gPending removeObject:p];
                Log([NSString stringWithFormat:@"PENDING host=%p resolved after %.2fs",
                     (__bridge void *)host, now-p.firstSeen]);
                continue;
            }
            if (now-p.firstSeen > kPendingTTL) {
                [gPending removeObject:p]; ++gPendingExpired;
                RateLog(&gExpiryLog, 5.0, [NSString stringWithFormat:
                    @"PENDING host=%p expired after %.0fs without an aperture container; expired=%u",
                    (__bridge void *)host, kPendingTTL, gPendingExpired]);
            }
        }
    } @finally { gResolving = NO; }
}

// ---- Touch diagnosis (observation only) ----
// These hooks never change a return value. They answer three questions from
// the alpha1 report: does the event reach the moved container, does the
// aperture window claim the touch region, and is the container's own reported
// hit area where the pixels are.

static NSString *InteractionSummary(UIView *v) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"userInteraction=%d hidden=%d alpha=%.3f recognizers=%lu",
        v.isUserInteractionEnabled, v.isHidden, v.alpha,
        (unsigned long)v.gestureRecognizers.count];
    for (UIView *a = v; a; a = a.superview) {
        if (!a.isUserInteractionEnabled || a.isHidden || a.alpha < 0.01) {
            [out appendFormat:@" firstNonInteractive=%s(%p)",
                class_getName([a class]), (__bridge void *)a];
            break;
        }
        if ([a isKindOfClass:[UIWindow class]]) break;
    }
    return out;
}

// Asks each ancestor, by public API, whether it accepts the same touch point
// after the container moved. This identifies an ancestor that owns a touch
// region a translation cannot move -- SBFTouchPassThroughView is the parent in
// the evidenced chain -- without hooking those shared SpringBoard classes.
static NSString *AncestorAcceptance(UIView *v, CGPoint local, UIEvent *event) {
    NSMutableString *out = [NSMutableString stringWithString:@" chain="];
    UIView *first = nil;
    // These queries re-enter the hooked pointInside:, so suppress nested
    // probe logging rather than reporting our own questions as real events.
    gProbeQuery = YES;
    @try {
        for (UIView *a = v.superview; a; a = a.superview) {
            CGPoint p = [v convertPoint:local toView:a];
            BOOL accepts = [a pointInside:p withEvent:event];
            [out appendFormat:@"%s%s ", class_getName([a class]), accepts ? ":yes" : ":NO"];
            if (!accepts && !first) first = a;
            if ([a isKindOfClass:[UIWindow class]]) break;
        }
    } @finally { gProbeQuery = NO; }
    if (first)
        [out appendFormat:@"firstRejectingAncestor=%s(%p)",
            class_getName([first class]), (__bridge void *)first];
    else
        [out appendString:@"allAncestorsAcceptPoint"];
    return out;
}

// Logs where the container reports its own hit region versus where its model
// geometry now is, in fixed screen coordinates.
static void LogHitChain(UIView *v, MUDFFixState *s, CGPoint local, UIView *result, UIEvent *event) {
    UIWindow *window = v.window;
    if (!window) return;
    double now = CACurrentMediaTime();
    // The first hit on a tracked container is always logged, then rate-limited,
    // so the ancestor queries below run at most about twice a second.
    if (s.loggedInteraction && now-s.lastChainLog < 0.5) return;
    s.loggedInteraction = YES; s.lastChainLog = now;
    id<UICoordinateSpace> fixed = window.screen.fixedCoordinateSpace;
    CGRect rect = [v convertRect:v.bounds toCoordinateSpace:fixed];
    CGPoint fixedPoint = [v convertPoint:local toCoordinateSpace:fixed];
    Log([NSString stringWithFormat:
        @"PROBE hitTest container=%p applied=%d localPoint={%.2f,%.2f} fixedPoint={%.2f,%.2f} "
        @"containerFixed=%@ insideBounds=%d result=%s(%p) %@%@",
        (__bridge void *)v, s.applied, local.x, local.y, fixedPoint.x, fixedPoint.y,
        NSStringFromCGRect(rect), CGRectContainsPoint(v.bounds, local),
        result ? class_getName([result class]) : "nil", (__bridge void *)result,
        InteractionSummary(v), AncestorAcceptance(v, local, event)]);
}

static UIView *(*OrigHitTest)(id,SEL,CGPoint,UIEvent *);
static UIView *HookHitTest(id self,SEL cmd,CGPoint point,UIEvent *event) {
    UIView *result = OrigHitTest(self,cmd,point,event);
    if (!gProbe || gProbeQuery || ![NSThread isMainThread]) return result;
    MUDFFixState *s = State(self);
    if (s) @try { LogHitChain(self,s,point,result,event); } @catch (__unused id e) {}
    return result;
}

static BOOL (*OrigPointInside)(id,SEL,CGPoint,UIEvent *);
static BOOL HookPointInside(id self,SEL cmd,CGPoint point,UIEvent *event) {
    BOOL inside = OrigPointInside(self,cmd,point,event);
    if (!gProbe || gProbeQuery || ![NSThread isMainThread]) return inside;
    MUDFFixState *s = State(self);
    if (s && s.applied) @try {
        UIView *v = (UIView *)self;
        BOOL boundsSays = CGRectContainsPoint(v.bounds, point);
        // A disagreement here means the container overrides its hit region
        // rather than deriving it from bounds, which a translation cannot move.
        if (inside != boundsSays)
            RateLog(&gInsideLog, 1.0, [NSString stringWithFormat:
                @"PROBE pointInside container=%p DISAGREES point={%.2f,%.2f} returned=%d bounds=%d bounds=%@",
                (__bridge void *)v, point.x, point.y, inside, boundsSays,
                NSStringFromCGRect(v.bounds)]);
    } @catch (__unused id e) {}
    return inside;
}

// Window-level probe: shows whether the event even descends into the moved
// container, or is claimed/rejected above it.
static BOOL AnyAppliedInWindow(UIWindow *window) {
    for (UIView *c in gContainers.allObjects) {
        MUDFFixState *s = State(c);
        if (s.applied && c.window == window) return YES;
    }
    return NO;
}

static UIView *(*OrigWindowHitTest)(id,SEL,CGPoint,UIEvent *);
static UIView *HookWindowHitTest(id self,SEL cmd,CGPoint point,UIEvent *event) {
    UIView *result = OrigWindowHitTest(self,cmd,point,event);
    if (!gProbe || gProbeQuery || ![NSThread isMainThread]) return result;
    @try {
        UIWindow *window = (UIWindow *)self;
        if (!AnyAppliedInWindow(window)) return result;
        BOOL reachedTracked = NO;
        for (UIView *a = result; a; a = a.superview) if (State(a)) { reachedTracked = YES; break; }
        id<UICoordinateSpace> fixed = window.screen.fixedCoordinateSpace;
        CGPoint fixedPoint = [window convertPoint:point toCoordinateSpace:fixed];
        RateLog(&gWindowHitLog, 0.5, [NSString stringWithFormat:
            @"PROBE windowHitTest window=%p point={%.2f,%.2f} fixedPoint={%.2f,%.2f} "
            @"result=%s(%p) reachedTrackedContainer=%d",
            (__bridge void *)window, point.x, point.y, fixedPoint.x, fixedPoint.y,
            result ? class_getName([result class]) : "nil", (__bridge void *)result,
            reachedTracked]);
    } @catch (__unused id e) {}
    return result;
}

static BOOL (*OrigWindowPointInside)(id,SEL,CGPoint,UIEvent *);
static BOOL HookWindowPointInside(id self,SEL cmd,CGPoint point,UIEvent *event) {
    BOOL inside = OrigWindowPointInside(self,cmd,point,event);
    if (!gProbe || gProbeQuery || ![NSThread isMainThread]) return inside;
    @try {
        UIWindow *window = (UIWindow *)self;
        // If the window rejects a point over the moved island, the touch region
        // is owned above the container and moving geometry cannot fix it.
        if (!inside && AnyAppliedInWindow(window))
            RateLog(&gWindowInsideLog, 1.0, [NSString stringWithFormat:
                @"PROBE windowPointInside window=%p REJECTED point={%.2f,%.2f} while a moved container is present; bounds=%@",
                (__bridge void *)window, point.x, point.y, NSStringFromCGRect(window.bounds)]);
    } @catch (__unused id e) {}
    return inside;
}

static void (*OrigHostLayout)(id,SEL,id);
static void HookHostLayout(id self,SEL cmd,id object) {
    OrigHostLayout(self,cmd,object);
    if (!gEnabled || ![NSThread isMainThread] || ![object isKindOfClass:[UIView class]]) return;
    UIView *host=(UIView *)object;
    if (TrackHost(host)) return;
    // Previously dropped here. The compact and media islands report their host
    // before it is attached, so queue it and re-check instead. Attachment often
    // completes within the same turn of the run loop, so try once more soon
    // rather than waiting for the next timer tick.
    AddPending(host);
    dispatch_async(dispatch_get_main_queue(), ^{ ResolvePending(); });
}

static BOOL Signature(Class cls,SEL sel,const char *ret,NSArray<NSString *> *args) {
    Method m=cls ? class_getInstanceMethod(cls,sel) : NULL;
    if (!m || method_getNumberOfArguments(m)!=args.count+2) return NO;
    char t[512]={0}; method_getReturnType(m,t,sizeof(t));
    if (strcmp(t,ret)!=0) return NO;
    for (NSUInteger i=0;i<args.count;++i) {
        memset(t,0,sizeof(t)); method_getArgumentType(m,(unsigned)i+2,t,sizeof(t));
        if (strcmp(t,args[i].UTF8String)!=0) return NO;
    }
    return YES;
}
static BOOL SubclassOf(Class cls,Class parent) {
    for (Class c=cls;c;c=class_getSuperclass(c)) if(c==parent)return YES;
    return NO;
}
static BOOL VerifiedMango(void) {
    const uint8_t uuid[16]={0x67,0xc0,0xd7,0xc2,0x44,0x87,0x3f,0xd2,0x95,0x35,0x06,0x77,0x45,0xae,0x4b,0x8f};
    for (uint32_t i=0;i<_dyld_image_count();++i) {
        const char *name=_dyld_get_image_name(i);
        if(!name)continue;
        const char *base=strrchr(name,'/');base=base?base+1:name;
        if(strcmp(base,"mango.dylib")!=0)continue;
        const struct mach_header *raw=_dyld_get_image_header(i);
        if(!raw || raw->magic!=MH_MAGIC_64)return NO;
        const struct mach_header_64 *h=(const struct mach_header_64 *)raw;
        const uint8_t *p=(const uint8_t *)(h+1),*end=p+h->sizeofcmds;
        for(uint32_t n=0;n<h->ncmds;++n) {
            if((size_t)(end-p)<sizeof(struct load_command))return NO;
            const struct load_command *lc=(const struct load_command *)p;
            if(lc->cmdsize<sizeof(*lc) || lc->cmdsize>(size_t)(end-p))return NO;
            if(lc->cmd==LC_UUID && lc->cmdsize>=sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)p)->uuid,uuid,16)==0;
            p+=lc->cmdsize;
        }
        return NO;
    }
    return NO;
}

static void Install(void) {
    if(gInstalled || access(kDisabled,F_OK)==0)return;
    NSOperatingSystemVersion os=NSProcessInfo.processInfo.operatingSystemVersion;
    if(os.majorVersion!=16 || os.minorVersion!=5 || os.patchVersion!=0) {
        Log(@"NO HOOKS this experimental build is restricted to iOS 16.5");return;
    }
    Class element=objc_getClass("MangoPillElement");
    gContainerClass=objc_getClass("SBSystemApertureContainerView");
    gWindowClass=objc_getClass("SBSystemApertureWindow");
    gContentClass=objc_getClass("_SBSystemApertureContainerViewContentView");
    if(!VerifiedMango() || !element || !gContainerClass || !gWindowClass || !gContentClass) {
        if(++gAttempts<40)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{Install();});
        else Log(@"NO HOOKS matching Mango UUID/classes not found within 20 seconds");
        return;
    }
    if(!SubclassOf(gContainerClass,[UIView class]) || !SubclassOf(gContentClass,[UIView class]) ||
       !SubclassOf(gWindowClass,[UIWindow class])) { Log(@"NO HOOKS class hierarchy mismatch");return; }
    SEL host=sel_registerName("layoutHostContainerViewDidLayoutSubviews:");
    NSArray *rectArgs=@[[NSString stringWithUTF8String:@encode(CGRect)]];
    NSArray *pointArgs=@[[NSString stringWithUTF8String:@encode(CGPoint)]];
    NSArray *transformArgs=@[[NSString stringWithUTF8String:@encode(CGAffineTransform)]];
    NSArray *hitArgs=@[[NSString stringWithUTF8String:@encode(CGPoint)],@"@"];
    const char *boolRet=@encode(BOOL);
    if(!Signature(element,host,"v",@[@"@"]) ||
       !Signature(gContainerClass,@selector(layoutSubviews),"v",@[]) ||
       !Signature(gContainerClass,@selector(setFrame:),"v",rectArgs) ||
       !Signature(gContainerClass,@selector(setBounds:),"v",rectArgs) ||
       !Signature(gContainerClass,@selector(setCenter:),"v",pointArgs) ||
       !Signature(gContainerClass,@selector(setTransform:),"v",transformArgs) ||
       !Signature(gContainerClass,@selector(didMoveToWindow),"v",@[])) {
        Log(@"NO HOOKS method signature mismatch");return;
    }
    gContainers=[NSHashTable weakObjectsHashTable];
    gPending=[NSMutableArray array];
    gEnabled=YES;
    MSHookMessageEx(gContainerClass,@selector(layoutSubviews),(IMP)HookLayout,(IMP *)&OrigLayout);
    MSHookMessageEx(gContainerClass,@selector(setFrame:),(IMP)HookFrame,(IMP *)&OrigFrame);
    MSHookMessageEx(gContainerClass,@selector(setBounds:),(IMP)HookBounds,(IMP *)&OrigBounds);
    MSHookMessageEx(gContainerClass,@selector(setCenter:),(IMP)HookCenter,(IMP *)&OrigCenter);
    MSHookMessageEx(gContainerClass,@selector(setTransform:),(IMP)HookTransform,(IMP *)&OrigTransform);
    MSHookMessageEx(gContainerClass,@selector(didMoveToWindow),(IMP)HookMove,(IMP *)&OrigMove);
    MSHookMessageEx(element,host,(IMP)HookHostLayout,(IMP *)&OrigHostLayout);
    // Observation-only touch probe. Separate opt-out, because a diagnostic
    // should be removable without giving up the placement fix. Like the alpha1
    // geometry hooks, these are hooked on the specific aperture subclasses;
    // MSHookMessageEx adds the override there rather than editing UIView.
    if(access(kNoProbe,F_OK)==0) {
        Log(@"PROBE disabled by marker; placement fix active without touch diagnostics");
    } else if(!Signature(gContainerClass,@selector(hitTest:withEvent:),"@",hitArgs) ||
              !Signature(gContainerClass,@selector(pointInside:withEvent:),boolRet,hitArgs) ||
              !Signature(gWindowClass,@selector(hitTest:withEvent:),"@",hitArgs) ||
              !Signature(gWindowClass,@selector(pointInside:withEvent:),boolRet,hitArgs)) {
        Log(@"PROBE not installed; hit-test signature mismatch");
    } else {
        MSHookMessageEx(gContainerClass,@selector(hitTest:withEvent:),(IMP)HookHitTest,(IMP *)&OrigHitTest);
        MSHookMessageEx(gContainerClass,@selector(pointInside:withEvent:),(IMP)HookPointInside,(IMP *)&OrigPointInside);
        MSHookMessageEx(gWindowClass,@selector(hitTest:withEvent:),(IMP)HookWindowHitTest,(IMP *)&OrigWindowHitTest);
        MSHookMessageEx(gWindowClass,@selector(pointInside:withEvent:),(IMP)HookWindowPointInside,(IMP *)&OrigWindowPointInside);
        gProbe=YES;
        Log(@"PROBE installed on the aperture container and window; returns are unchanged");
    }
    gInstalled=YES;
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            RefreshEnabled();ResolvePending();UpdateAll();
            dispatch_async(dispatch_get_main_queue(),^{ResolvePending();UpdateAll();});
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                ResolvePending();UpdateAll();});
        }];
    // Low-rate recovery/reconciliation, not an animation driver or touch hook.
    gTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(gTimer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),
                              250*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gTimer,^{
        RefreshEnabled();ResolvePending();UpdateAll();
        if(!gEnabled)dispatch_source_cancel(gTimer);
    });
    dispatch_resume(gTimer);
    Log(@"INSTALLED 0.2.0-alpha2; scoped translation, pending host tracking, read-only touch probe");
}

__attribute__((constructor)) static void StartFix(void) {
    @autoreleasepool { dispatch_async(dispatch_get_main_queue(),^{Install();}); }
}
