// MangoUpsideDownWorld placement module.
//
// This is the proven placement half of MangoUpsideDownFix, adapted to live
// inside the World package. World owns the SBSystemApertureWindow half-turn;
// this module owns only a scoped translation on Mango-confirmed
// SBSystemApertureContainerView instances that are still on the wrong physical
// edge after that turn.
//
// Key safety rule: placement is allowed only while the aperture window itself
// already has an inverted basis in UIScreen.fixedCoordinateSpace. Therefore a
// failed/disabled World cannot cause this module to move the island by itself.

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

static const char *WPDisabled = "/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled";
static const char *WPLogPath = "/var/mobile/Library/Logs/MangoUpsideDownWorld.log";
static const NSUInteger WPPendingCap = 64;
static const double WPPendingTTL = 30.0;

static Class WPContainerClass, WPWindowClass;
static NSHashTable<UIView *> *WPContainers;
static NSMutableArray *WPPending;
static dispatch_source_t WPTimer;
static BOOL WPInstalled, WPEnabled, WPResolving;
static unsigned WPOwnWrite, WPLayoutDepth, WPAttempts, WPPendingSeen, WPPendingExpired;
static double WPPendingLog, WPExpiryLog;
static char WPStateKey;

@interface MWPState : NSObject
@property(nonatomic, strong) NSHashTable<UIView *> *hosts;
@property(nonatomic, weak) UIView *parent;
@property(nonatomic) CGAffineTransform baseline;
@property(nonatomic) CGAffineTransform appliedTransform;
@property(nonatomic) BOOL applied;
@property(nonatomic) BOOL suspended;
@property(nonatomic) unsigned mutationDepth;
@property(nonatomic) double lastLog;
@end
@implementation MWPState
@end

@interface MWPPendingHost : NSObject
@property(nonatomic, weak) UIView *host;
@property(nonatomic) double firstSeen;
@end
@implementation MWPPendingHost
@end

static void WPLog(NSString *message) {
    if (![NSThread isMainThread]) return;
    NSString *line = [NSString stringWithFormat:@"PLACEMENT %@", message];
    NSLog(@"[MangoUDWorld] %@", line);
    mkdir("/var/mobile/Library/Logs", 0755);
    int fd = open(WPLogPath, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW, 0600);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return; }
    if (st.st_size > 512*1024) ftruncate(fd, 0);
    NSData *bytes = [[NSString stringWithFormat:@"%.3f %@\n",
                      NSDate.timeIntervalSinceReferenceDate, line]
                     dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *p = (const uint8_t *)bytes.bytes;
    size_t left = bytes.length;
    while (left) {
        ssize_t n = write(fd, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        p += n;
        left -= (size_t)n;
    }
    close(fd);
}

static void WPRateLog(double *slot, double interval, NSString *message) {
    double now = CACurrentMediaTime();
    if (now - *slot < interval) return;
    *slot = now;
    WPLog(message);
}

static MUDFAffine WPAffine(CGAffineTransform t) {
    return (MUDFAffine){t.a,t.b,t.c,t.d,t.tx,t.ty};
}
static CGAffineTransform WPCGAffine(MUDFAffine t) {
    return CGAffineTransformMake(t.a,t.b,t.c,t.d,t.tx,t.ty);
}
static MUDFRect WPRect(CGRect r) {
    return (MUDFRect){r.origin.x,r.origin.y,r.size.width,r.size.height};
}
static CGRect WPCGRect(MUDFRect r) {
    return CGRectMake(r.x,r.y,r.width,r.height);
}
static BOOL WPNear(CGAffineTransform a, CGAffineTransform b) {
    return MUDFAffineNear(WPAffine(a), WPAffine(b));
}
static MWPState *WPState(UIView *v) {
    return (MWPState *)objc_getAssociatedObject(v, &WPStateKey);
}

static void WPStateLog(MWPState *s, NSString *message) {
    double now = CACurrentMediaTime();
    if (now - s.lastLog < 1.0) return;
    s.lastLog = now;
    WPLog(message);
}

static NSInteger WPOrientation(void) {
    Class c = objc_getClass("DecoratedAppSceneView");
    SEL sel = sel_registerName("mango_currentInterfaceOrientation");
    Method m = c ? class_getClassMethod(c, sel) : NULL;
    if (!m || method_getNumberOfArguments(m) != 2) return -1;
    char type[64] = {0};
    method_getReturnType(m, type, sizeof(type));
    if (strcmp(type, @encode(NSInteger)) != 0) return -1;
    return ((NSInteger (*)(id,SEL))objc_msgSend)((id)c, sel);
}

static UIView *WPFindAncestor(UIView *host, Class cls) {
    UIView *v = host;
    for (unsigned i = 0; v && i < 20; ++i, v = v.superview)
        if ([v isKindOfClass:cls]) return v;
    return nil;
}

static UIView *WPCurrentHost(UIView *container, MWPState *s) {
    for (UIView *host in s.hosts.allObjects)
        if (WPFindAncestor(host, WPContainerClass) == container) return host;
    return nil;
}

static BOOL WPAffineHierarchy(UIView *v) {
    for (unsigned depth = 0; v && depth < 24; ++depth, v = v.superview) {
        if (!CATransform3DIsAffine(v.layer.transform) ||
            !CATransform3DIsIdentity(v.layer.sublayerTransform)) return NO;
        if ([v isKindOfClass:UIWindow.class]) return YES;
    }
    return NO;
}

// World turns SBSystemApertureWindow by 180 degrees. Require that actual
// runtime condition before this module is allowed to move a container.
static BOOL WPWindowIsWorldTurned(UIWindow *window) {
    if (!window || window.screen != UIScreen.mainScreen) return NO;
    id<UICoordinateSpace> fixed = window.screen.fixedCoordinateSpace;
    CGPoint o = [window convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x = [window convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y = [window convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    double dx = x.x-o.x, dy = y.y-o.y;
    double skewX = y.x-o.x, skewY = x.y-o.y;
    return isfinite(dx) && isfinite(dy) && isfinite(skewX) && isfinite(skewY) &&
           dx < -1e-5 && dy < -1e-5 &&
           fabs(skewY) <= fabs(dx)*1e-3 && fabs(skewX) <= fabs(dy)*1e-3;
}

static void WPWriteTransform(UIView *v, CGAffineTransform t) {
    ++WPOwnWrite;
    @try {
        [UIView performWithoutAnimation:^{ v.transform = t; }];
    } @finally {
        --WPOwnWrite;
    }
}

static void WPRestore(UIView *v, MWPState *s, NSString *reason) {
    if (!s.applied) return;
    if (WPNear(v.transform, s.appliedTransform)) {
        WPWriteTransform(v, s.baseline);
        if (reason) WPLog([NSString stringWithFormat:@"RESTORE %@ container=%p",
                           reason, (__bridge void *)v]);
    } else {
        s.suspended = YES;
        WPLog(@"CONFLICT untracked container transform; placement suspended until respring");
    }
    s.applied = NO;
}

static void WPUpdate(UIView *v) {
    MWPState *s = WPState(v);
    if (!s || s.mutationDepth || WPOwnWrite || WPLayoutDepth || ![NSThread isMainThread]) return;

    if (s.applied && !WPNear(v.transform, s.appliedTransform)) {
        WPRestore(v, s, @"transform-conflict");
        return;
    }
    if (s.suspended) return;

    if (!WPEnabled || access(WPDisabled, F_OK) == 0 ||
        WPOrientation() != UIInterfaceOrientationPortraitUpsideDown) {
        WPRestore(v, s, @"orientation-or-disabled");
        return;
    }

    UIView *host = WPCurrentHost(v, s);
    UIView *parent = v.superview;
    UIWindow *window = v.window;
    if (!host || !parent || ![window isKindOfClass:WPWindowClass] ||
        window.screen != UIScreen.mainScreen) {
        WPRestore(v, s, @"host-or-window-detached");
        return;
    }

    // The old standalone Fix could move the container without World. The
    // integrated version must not: wait until World has really turned the
    // aperture window. This also makes install/constructor ordering harmless.
    if (!WPWindowIsWorldTurned(window)) {
        WPRestore(v, s, @"waiting-for-world-turn");
        return;
    }

    if (s.applied && s.parent != parent) WPRestore(v, s, @"parent-changed");
    if (s.suspended) return;
    s.parent = parent;

    if (!WPAffineHierarchy(host)) {
        WPRestore(v, s, @"non-affine-hierarchy");
        WPStateLog(s, @"SKIP non-affine hierarchy");
        return;
    }

    id<UICoordinateSpace> fixed = window.screen.fixedCoordinateSpace;
    CGPoint o = [parent convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x = [parent convertPoint:CGPointMake(1,0) toCoordinateSpace:fixed];
    CGPoint y = [parent convertPoint:CGPointMake(0,1) toCoordinateSpace:fixed];
    MUDFAffine map = {x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y};

    MUDFRect current = WPRect([v convertRect:v.bounds toCoordinateSpace:fixed]);
    MUDFRect baseline = current;
    CGAffineTransform base = s.applied ? s.baseline : v.transform;

    if (s.applied) {
        MUDFPoint own = {s.appliedTransform.tx-base.tx,
                         s.appliedTransform.ty-base.ty};
        baseline = MUDFBaselineRect(current, map, own);
    }

    MUDFPoint delta;
    MUDFRect target;
    MUDFPlanResult result = MUDFPlan(WPRect(fixed.bounds), baseline, map, &delta, &target);

    if (result == MUDFPlanAlreadyAtOtherEdge) {
        // The World window turn already put this island on physical bottom,
        // which is visual top while the phone is upside down. If an older
        // placement translation is still present, remove it now.
        WPRestore(v, s, @"world-already-placed");
        WPStateLog(s, @"SKIP already at physical lower edge");
        return;
    }

    if (result != MUDFPlanOK) {
        WPRestore(v, s, @"geometry-guard");
        WPStateLog(s, @"SKIP invalid placement geometry");
        return;
    }

    CGAffineTransform desired = WPCGAffine(MUDFWithTranslation(WPAffine(base), delta));
    s.baseline = base;
    s.appliedTransform = desired;
    s.applied = YES;

    if (!WPNear(v.transform, desired)) WPWriteTransform(v, desired);

    CGRect after = [v convertRect:v.bounds toCoordinateSpace:fixed];
    if (!MUDFFiniteRect(WPRect(after)) ||
        fabs(CGRectGetMinY(after)-target.y) > 1.0 ||
        fabs(CGRectGetMinX(after)-target.x) > 1.0) {
        WPRestore(v, s, @"post-write-mismatch");
        s.suspended = YES;
        WPLog(@"SUSPEND post-write geometry verification failed");
        return;
    }

    WPStateLog(s, [NSString stringWithFormat:
        @"APPLY container=%p baselineFixed=%@ targetFixed=%@ actualFixed=%@ deltaParent={%.3f,%.3f}",
        (__bridge void *)v,
        NSStringFromCGRect(WPCGRect(baseline)),
        NSStringFromCGRect(WPCGRect(target)),
        NSStringFromCGRect(after), delta.x, delta.y]);
}

static void WPUpdateAll(void) {
    if (![NSThread isMainThread]) return;
    for (UIView *v in WPContainers.allObjects) WPUpdate(v);
}

static MWPState *WPBeginMutation(UIView *v) {
    if (WPOwnWrite || ![NSThread isMainThread]) return nil;
    MWPState *s = WPState(v);
    if (!s || s.suspended) return nil;
    if (s.mutationDepth == 0) WPRestore(v, s, nil);
    ++s.mutationDepth;
    return s;
}

static void WPEndMutation(UIView *v, MWPState *s) {
    if (!s) return;
    --s.mutationDepth;
    if (s.mutationDepth == 0) WPUpdate(v);
}

static void (*WPOrigLayout)(id,SEL);
static void WPHookLayout(id self, SEL cmd) {
    MWPState *s = WPBeginMutation(self);
    BOOL main = [NSThread isMainThread];
    if (main) ++WPLayoutDepth;
    @try { WPOrigLayout(self,cmd); }
    @finally {
        if (main) --WPLayoutDepth;
        WPEndMutation(self,s);
        if (main && !s) WPUpdate(self);
    }
}

static void (*WPOrigFrame)(id,SEL,CGRect);
static void WPHookFrame(id self, SEL cmd, CGRect value) {
    MWPState *s = WPBeginMutation(self);
    @try { WPOrigFrame(self,cmd,value); }
    @finally { WPEndMutation(self,s); }
}

static void (*WPOrigBounds)(id,SEL,CGRect);
static void WPHookBounds(id self, SEL cmd, CGRect value) {
    MWPState *s = WPBeginMutation(self);
    @try { WPOrigBounds(self,cmd,value); }
    @finally { WPEndMutation(self,s); }
}

static void (*WPOrigCenter)(id,SEL,CGPoint);
static void WPHookCenter(id self, SEL cmd, CGPoint value) {
    MWPState *s = WPBeginMutation(self);
    @try { WPOrigCenter(self,cmd,value); }
    @finally { WPEndMutation(self,s); }
}

static void (*WPOrigTransform)(id,SEL,CGAffineTransform);
static void WPHookTransform(id self, SEL cmd, CGAffineTransform value) {
    MWPState *s = WPBeginMutation(self);
    @try { WPOrigTransform(self,cmd,value); }
    @finally { WPEndMutation(self,s); }
}

static void (*WPOrigMove)(id,SEL);
static void WPHookMove(id self, SEL cmd) {
    MWPState *s = WPBeginMutation(self);
    @try { WPOrigMove(self,cmd); }
    @finally { WPEndMutation(self,s); }
}

static BOOL WPTrackHost(UIView *host) {
    UIView *container = WPFindAncestor(host, WPContainerClass);
    if (!container || ![container.window isKindOfClass:WPWindowClass]) return NO;

    MWPState *s = WPState(container);
    if (!s) {
        s = [MWPState new];
        s.hosts = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(container, &WPStateKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [WPContainers addObject:container];
        WPLog([NSString stringWithFormat:@"TRACK host=%p container=%p",
               (__bridge void *)host, (__bridge void *)container]);
    }

    [s.hosts addObject:host];
    WPUpdate(container);

    __weak UIView *weakContainer = container;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakContainer) WPUpdate(weakContainer);
    });
    return YES;
}

static void WPAddPending(UIView *host) {
    for (MWPPendingHost *p in WPPending) if (p.host == host) return;
    if (WPPending.count >= WPPendingCap) {
        WPRateLog(&WPPendingLog, 5.0,
                  [NSString stringWithFormat:@"PENDING cap %lu reached",
                   (unsigned long)WPPendingCap]);
        return;
    }
    MWPPendingHost *p = [MWPPendingHost new];
    p.host = host;
    p.firstSeen = CACurrentMediaTime();
    [WPPending addObject:p];
    ++WPPendingSeen;
    WPRateLog(&WPPendingLog, 1.0,
              [NSString stringWithFormat:@"PENDING host=%p queued count=%lu seen=%u",
               (__bridge void *)host, (unsigned long)WPPending.count, WPPendingSeen]);
}

static void WPResolvePending(void) {
    if (!WPPending.count || WPResolving || ![NSThread isMainThread]) return;
    WPResolving = YES;
    @try {
        double now = CACurrentMediaTime();
        for (MWPPendingHost *p in [WPPending copy]) {
            UIView *host = p.host;
            if (!host) { [WPPending removeObject:p]; continue; }
            if (WPEnabled && WPTrackHost(host)) {
                [WPPending removeObject:p];
                WPLog([NSString stringWithFormat:@"PENDING host=%p resolved after %.2fs",
                       (__bridge void *)host, now-p.firstSeen]);
                continue;
            }
            if (now-p.firstSeen > WPPendingTTL) {
                [WPPending removeObject:p];
                ++WPPendingExpired;
                WPRateLog(&WPExpiryLog, 5.0,
                          [NSString stringWithFormat:@"PENDING host=%p expired; expired=%u",
                           (__bridge void *)host, WPPendingExpired]);
            }
        }
    } @finally {
        WPResolving = NO;
    }
}

static void (*WPOrigHostLayout)(id,SEL,id);
static void WPHookHostLayout(id self, SEL cmd, id object) {
    WPOrigHostLayout(self,cmd,object);
    if (!WPEnabled || ![NSThread isMainThread] ||
        ![object isKindOfClass:UIView.class]) return;

    UIView *host = (UIView *)object;
    if (WPTrackHost(host)) return;

    // Compact/media hosts can be reported before they are attached to the
    // aperture hierarchy. Keep the alpha2 weak pending queue behavior.
    WPAddPending(host);
    dispatch_async(dispatch_get_main_queue(), ^{ WPResolvePending(); });
}

static BOOL WPSignature(Class cls, SEL sel, const char *ret, NSArray<NSString *> *args) {
    Method m = cls ? class_getInstanceMethod(cls,sel) : NULL;
    if (!m || method_getNumberOfArguments(m) != args.count+2) return NO;
    char t[512] = {0};
    method_getReturnType(m,t,sizeof(t));
    if (strcmp(t,ret) != 0) return NO;
    for (NSUInteger i=0; i<args.count; ++i) {
        memset(t,0,sizeof(t));
        method_getArgumentType(m,(unsigned)i+2,t,sizeof(t));
        if (strcmp(t,args[i].UTF8String) != 0) return NO;
    }
    return YES;
}

static BOOL WPSubclassOf(Class cls, Class parent) {
    for (Class c=cls; c; c=class_getSuperclass(c)) if (c==parent) return YES;
    return NO;
}

static BOOL WPVerifiedMango(void) {
    const uint8_t uuid[16] = {0x67,0xc0,0xd7,0xc2,0x44,0x87,0x3f,0xd2,
                              0x95,0x35,0x06,0x77,0x45,0xae,0x4b,0x8f};
    for (uint32_t i=0; i<_dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *base = strrchr(name,'/');
        base = base ? base+1 : name;
        if (!strcmp(base,"MangoUpsideDownFix.dylib")) {
            WPLog(@"NO HOOKS legacy standalone Fix is still loaded; respring after package replacement");
            return NO;
        }
        if (strcmp(base,"mango.dylib") != 0) continue;

        const struct mach_header *raw = _dyld_get_image_header(i);
        if (!raw || raw->magic != MH_MAGIC_64) return NO;
        const struct mach_header_64 *h = (const struct mach_header_64 *)raw;
        const uint8_t *p = (const uint8_t *)(h+1), *end = p+h->sizeofcmds;
        for (uint32_t n=0; n<h->ncmds; ++n) {
            if ((size_t)(end-p) < sizeof(struct load_command)) return NO;
            const struct load_command *lc = (const struct load_command *)p;
            if (lc->cmdsize < sizeof(*lc) || lc->cmdsize > (size_t)(end-p)) return NO;
            if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)p)->uuid,uuid,16) == 0;
            p += lc->cmdsize;
        }
        return NO;
    }
    return NO;
}

static void WPInstall(void) {
    if (WPInstalled || access(WPDisabled,F_OK)==0) return;

    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (os.majorVersion!=16 || os.minorVersion!=5 || os.patchVersion!=0) {
        WPLog(@"NO HOOKS placement module restricted to iOS 16.5");
        return;
    }

    Class element = objc_getClass("MangoPillElement");
    WPContainerClass = objc_getClass("SBSystemApertureContainerView");
    WPWindowClass = objc_getClass("SBSystemApertureWindow");

    if (!WPVerifiedMango() || !element || !WPContainerClass || !WPWindowClass) {
        if (++WPAttempts < 40)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{ WPInstall(); });
        else
            WPLog(@"NO HOOKS matching Mango UUID/classes unavailable within 20 seconds");
        return;
    }

    if (!WPSubclassOf(WPContainerClass,UIView.class) ||
        !WPSubclassOf(WPWindowClass,UIWindow.class)) {
        WPLog(@"NO HOOKS placement class hierarchy mismatch");
        return;
    }

    SEL host = sel_registerName("layoutHostContainerViewDidLayoutSubviews:");
    NSArray *rectArgs = @[[NSString stringWithUTF8String:@encode(CGRect)]];
    NSArray *pointArgs = @[[NSString stringWithUTF8String:@encode(CGPoint)]];
    NSArray *transformArgs = @[[NSString stringWithUTF8String:@encode(CGAffineTransform)]];

    if (!WPSignature(element,host,"v",@[@"@"]) ||
        !WPSignature(WPContainerClass,@selector(layoutSubviews),"v",@[]) ||
        !WPSignature(WPContainerClass,@selector(setFrame:),"v",rectArgs) ||
        !WPSignature(WPContainerClass,@selector(setBounds:),"v",rectArgs) ||
        !WPSignature(WPContainerClass,@selector(setCenter:),"v",pointArgs) ||
        !WPSignature(WPContainerClass,@selector(setTransform:),"v",transformArgs) ||
        !WPSignature(WPContainerClass,@selector(didMoveToWindow),"v",@[])) {
        WPLog(@"NO HOOKS placement method signature mismatch");
        return;
    }

    WPContainers = [NSHashTable weakObjectsHashTable];
    WPPending = [NSMutableArray array];
    WPEnabled = YES;

    MSHookMessageEx(WPContainerClass,@selector(layoutSubviews),(IMP)WPHookLayout,(IMP *)&WPOrigLayout);
    MSHookMessageEx(WPContainerClass,@selector(setFrame:),(IMP)WPHookFrame,(IMP *)&WPOrigFrame);
    MSHookMessageEx(WPContainerClass,@selector(setBounds:),(IMP)WPHookBounds,(IMP *)&WPOrigBounds);
    MSHookMessageEx(WPContainerClass,@selector(setCenter:),(IMP)WPHookCenter,(IMP *)&WPOrigCenter);
    MSHookMessageEx(WPContainerClass,@selector(setTransform:),(IMP)WPHookTransform,(IMP *)&WPOrigTransform);
    MSHookMessageEx(WPContainerClass,@selector(didMoveToWindow),(IMP)WPHookMove,(IMP *)&WPOrigMove);
    MSHookMessageEx(element,host,(IMP)WPHookHostLayout,(IMP *)&WPOrigHostLayout);

    WPInstalled = YES;

    [NSNotificationCenter.defaultCenter
        addObserverForName:@"MangoInterfaceOrientationDidChange"
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification *note) {
            WPResolvePending();
            WPUpdateAll();
            dispatch_async(dispatch_get_main_queue(), ^{
                WPResolvePending();
                WPUpdateAll();
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                WPResolvePending();
                WPUpdateAll();
            });
        }];

    WPTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(WPTimer,
                              dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),
                              250*NSEC_PER_MSEC,
                              50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(WPTimer, ^{
        if (access(WPDisabled,F_OK)==0 && WPEnabled) {
            WPEnabled = NO;
            [WPPending removeAllObjects];
            WPUpdateAll();
            WPLog(@"DISABLED restored owned placement transforms");
        } else {
            WPResolvePending();
            WPUpdateAll();
        }
        if (!WPEnabled) dispatch_source_cancel(WPTimer);
    });
    dispatch_resume(WPTimer);

    WPLog(@"INSTALLED integrated placement module; applies translation only when World window turn is active");
}

__attribute__((constructor)) static void StartWorldPlacement(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{ WPInstall(); });
    }
}
