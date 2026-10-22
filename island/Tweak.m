// 灵动岛: a Dynamic Island for notch iPhones on iOS 16.5, in SpringBoard.
//
// Two halves.
// - The disguise (Disguise.m). SpringBoard builds the island when the device
//   model value (MobileGestalt ArtworkDeviceSubType) says 14 Pro / 14 Pro Max.
//   The Settings pane asks this tweak, over request.plist + a Darwin
//   notification, to change that value (backed up, restorable) and respring.
//   Nothing is ever written without that explicit request, except undoing it:
//   a crash-loop guard and a restore file (DynamicIsland.restore).
// - Size and position (this file). Written so that turning the phone upside
//   down can never undo them, and adjusting can never undo the inversion.
//
// How the inversion stays intact. World/Suite turn the whole
// SBSystemApertureWindow by 180 degrees (and cancel the turn in the content
// view) while the phone is upside down, and give up on any of those views the
// moment somebody else writes its transform; Mango's own position/scale
// adjustment writes exactly such views, which is why adjusting used to switch
// the inversion off. This tweak never touches the window, the root view or the
// content view. It writes one transform on the pass-through view between the
// root and the island, expressed in the window's own coordinate space. That
// space is turned along with the window, so it reads the way the user sees the
// screen, upright and inverted alike: the same transform is right in both, and
// the turn simply composes on top. There is no orientation maths in here at all.
//
// Labels used in comments: [read] seen in a log or a binary, [inferred] follows
// from something read, [missing] not yet seen on a device.
// - [read] chain, EVIDENCE.md: SBSystemApertureWindow > 3x SBFTouchPassThroughView
//   > SBSystemApertureContainerView > ... ; the three pass-through views have
//   identity transforms; the window carries a 25/24 scale.
// - [inferred] the node written here is the second pass-through view; the
//   window's local space is visual space, and nothing else writes that view.
// - [missing] everything about how this behaves on the device. The first run
//   logs the whole chain and verifies every write; see README.md.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <math.h>
#import "IslandMath.h"
#import "IslandPolicy.h"
#import "Settings.h"
#import "Disguise.h"

static Class WindowClass, PassClass;
static char StateKey;
static BOOL Busy;
static NSString *RestoreNote = @"";

// ---- Log ----------------------------------------------------------------------

// Status lines for 导出诊断日志 in Settings; one rollover at 512KB.
static void Log(NSString *line) {
    NSString *path = DIFile(@"DynamicIsland.log");
    struct stat info;
    if (!stat(path.fileSystemRepresentation, &info) && info.st_size > 512 * 1024)
        rename(path.fileSystemRepresentation, [path stringByAppendingString:@".old"].fileSystemRepresentation);
    FILE *file = fopen(path.fileSystemRepresentation, "a");
    if (!file) return;
    char stamp[32];
    time_t now = time(NULL);
    struct tm local;
    localtime_r(&now, &local);
    strftime(stamp, sizeof stamp, "%m-%d %H:%M:%S", &local);
    fprintf(file, "%s %s\n", stamp, line.UTF8String);
    fclose(file);
}

// Log a line only when it differs from the last one under the same key.
static void LogChange(NSString *key, NSString *line) {
    static NSMutableDictionary<NSString *, NSString *> *last;
    if (!last) last = [NSMutableDictionary dictionary];
    if ([last[key] isEqualToString:line]) return;
    last[key] = line;
    Log(line);
}

static IMAffine ToIM(CGAffineTransform t) { return (IMAffine){t.a, t.b, t.c, t.d, t.tx, t.ty}; }
static CGAffineTransform ToCG(IMAffine t) { return CGAffineTransformMake(t.a, t.b, t.c, t.d, t.tx, t.ty); }
static IMPoint ToIP(CGPoint p) { return (IMPoint){p.x, p.y}; }

static NSString *Machine(void) {
    char buffer[64] = {0};
    size_t size = sizeof buffer;
    if (sysctlbyname("hw.machine", buffer, &size, NULL, 0) != 0) return @"?";
    return [NSString stringWithUTF8String:buffer] ?: @"?";
}

static double NativeHeight(void) { return UIScreen.mainScreen.nativeBounds.size.height; }

static NSInteger BarOrientation(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (NSInteger)UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
}

// ---- Settings cache -------------------------------------------------------------

static BOOL SettingsStale;
static NSDictionary *S(void) {
    static NSDictionary *snapshot;
    static CFTimeInterval last;
    CFTimeInterval now = CACurrentMediaTime();
    if (!snapshot || SettingsStale || now - last >= .25) {
        snapshot = DIReadSettings();
        last = now;
        SettingsStale = NO;
    }
    return snapshot;
}

// ---- Windows and nodes -----------------------------------------------------------

static NSArray<UIWindow *> *ApertureWindows(void) {
    NSMutableOrderedSet<UIWindow *> *found = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if ([window isKindOfClass:WindowClass]) [found addObject:window];
    // SpringBoard's system aperture window may have no UIWindowScene (the
    // supplied log shows sceneOrientation=0), so also ask the application.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        if ([window isKindOfClass:WindowClass]) [found addObject:window];
#pragma clang diagnostic pop
    NSMutableArray<UIWindow *> *result = [NSMutableArray array];
    for (UIWindow *window in found)
        if (window.screen == UIScreen.mainScreen) [result addObject:window];
    return result;
}

static IMWindowTurn TurnInFixed(UIWindow *w) {
    id<UICoordinateSpace> fixed = w.screen.fixedCoordinateSpace;
    CGPoint o = [w convertPoint:CGPointZero toCoordinateSpace:fixed];
    CGPoint x = [w convertPoint:CGPointMake(1, 0) toCoordinateSpace:fixed];
    CGPoint y = [w convertPoint:CGPointMake(0, 1) toCoordinateSpace:fixed];
    return IMClassifyWindowBasis(ToIP(o), ToIP(x), ToIP(y));
}
static IMWindowTurn TurnInModel(UIWindow *w) {
    CGAffineTransform t = w.transform;
    return IMClassifyWindowBasis((IMPoint){0, 0}, (IMPoint){t.a, t.b}, (IMPoint){t.c, t.d});
}
static NSString *TurnName(IMWindowTurn turn) {
    return turn == IMWindowUpright ? @"upright" : (turn == IMWindowTurned ? @"turned" : @"other");
}

@interface DINodeState : NSObject
@property(nonatomic) BOOL owned;
@property(nonatomic) CGAffineTransform applied;
@property(nonatomic, copy) NSString *failedFor;
@end
@implementation DINodeState
@end

// Everything below needs window > root > node with nothing but a translation
// between the node's parent and the window, so that "local" means one thing.
static NSString *Ineligible(UIWindow *w, UIView *node) {
    UIView *root = node.superview;
    if (!root || root.superview != w) return @"chain";
    if (w.screen != UIScreen.mainScreen) return @"screen";
    for (UIView *v in @[w, root, node])
        if (!CATransform3DIsAffine(v.layer.transform) || !CATransform3DIsIdentity(v.layer.sublayerTransform)) return @"layer";
    CGPoint o = [root.layer convertPoint:CGPointZero toLayer:w.layer];
    CGPoint x = [root.layer convertPoint:CGPointMake(1, 0) toLayer:w.layer];
    CGPoint y = [root.layer convertPoint:CGPointMake(0, 1) toLayer:w.layer];
    if (!IMBasisIsTranslation(ToIP(o), ToIP(x), ToIP(y))) return @"parent-basis";
    CGRect b = node.bounds;
    CGPoint ap = node.layer.anchorPoint, pos = node.layer.position;
    if (!isfinite(b.origin.x) || !isfinite(b.origin.y) || !isfinite(b.size.width) || !isfinite(b.size.height) ||
        !isfinite(ap.x) || !isfinite(ap.y) || !isfinite(pos.x) || !isfinite(pos.y))
        return @"node-geometry";
    return nil;
}

static void Write(UIView *node, CGAffineTransform t) {
    [UIView performWithoutAnimation:^{ node.transform = t; }];
}

// After a write: three points of the node, measured through the layer tree into
// the window's local space, must land where the adjustment says. No fixed-space
// or orientation reading is involved, so this holds turned and upright.
static BOOL Verify(UIWindow *w, UIView *node, IMAdjust adj, double unit, IMPoint pivot, IMPoint anchorLocal, NSString **detail) {
    CGRect b = node.bounds;
    CGPoint ap = node.layer.anchorPoint;
    CGPoint inBounds = CGPointMake(CGRectGetMinX(b) + ap.x * b.size.width, CGRectGetMinY(b) + ap.y * b.size.height);
    const CGPoint offsets[3] = {{0, 0}, {40, 0}, {0, 40}};
    for (int i = 0; i < 3; i++) {
        CGPoint q = CGPointMake(inBounds.x + offsets[i].x, inBounds.y + offsets[i].y);
        CGPoint got = [node.layer convertPoint:q toLayer:w.layer];
        IMPoint want = IMAdjustMap(adj, unit, pivot, (IMPoint){anchorLocal.x + offsets[i].x, anchorLocal.y + offsets[i].y});
        if (!isfinite(got.x) || !isfinite(got.y) || fabs(got.x - want.x) > 0.6 || fabs(got.y - want.y) > 0.6) {
            if (detail) *detail = [NSString stringWithFormat:@"probe %d want {%.2f,%.2f} got {%.2f,%.2f}", i, want.x, want.y, got.x, got.y];
            return NO;
        }
    }
    return YES;
}

typedef struct { unsigned nodes, owned, conflict, failed, ineligible; } Tally;

static void ProcessNode(UIWindow *w, UIView *node, BOOL wanted, IMAdjust adj, double unit, NSString *signature, Tally *tally, NSString **reason) {
    DINodeState *state = objc_getAssociatedObject(node, &StateKey);
    if (!state) {
        state = [DINodeState new];
        objc_setAssociatedObject(node, &StateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Log([NSString stringWithFormat:@"NODE new %p %@ superview=%@", (__bridge void *)node, NSStringFromClass(node.class), NSStringFromClass(node.superview.class)]);
    }
    tally->nodes++;
    CGAffineTransform current = node.transform;

    NSString *bad = Ineligible(w, node);
    if (bad) {
        // Hand back what is ours, but never write anything else.
        if (state.owned) {
            if (IMAffineNear(ToIM(current), ToIM(state.applied))) Write(node, CGAffineTransformIdentity);
            state.owned = NO;
        }
        tally->ineligible++;
        *reason = bad;
        LogChange(@"ineligible", [NSString stringWithFormat:@"NODE %p not eligible: %@", (__bridge void *)node, bad]);
        return;
    }

    UIView *root = node.superview;
    CGPoint anchorLocal = [root.layer convertPoint:node.layer.position toLayer:w.layer];
    CGRect wb = w.bounds;
    IMPoint pivot = {CGRectGetMinX(wb) + wb.size.width / 2, CGRectGetMinY(wb) + adj.anchorY / unit};
    IMAffine desired = IMNodeTransform(adj, unit, pivot, ToIP(anchorLocal));
    BOOL want = wanted && ![state.failedFor isEqualToString:signature] && IMAffineFinite(desired);

    switch (IMOwnDecide(want, state.owned, ToIM(current), ToIM(state.applied), desired)) {
        case IMOwnKeep:
            break;
        case IMOwnConflict:
            tally->conflict++;
            *reason = @"foreign-transform";
            LogChange(@"conflict", [NSString stringWithFormat:@"NODE %p has a transform that is not ours %@; left alone", (__bridge void *)node, NSStringFromCGAffineTransform(current)]);
            return;
        case IMOwnRelease:
            if (IMAffineNear(ToIM(current), ToIM(state.applied))) Write(node, CGAffineTransformIdentity);
            state.owned = NO;
            LogChange(@"release", [NSString stringWithFormat:@"NODE %p released", (__bridge void *)node]);
            break;
        case IMOwnWrite: {
            state.applied = ToCG(desired);
            state.owned = YES;
            Write(node, ToCG(desired));
            NSString *detail = nil;
            if (!Verify(w, node, adj, unit, pivot, ToIP(anchorLocal), &detail)) {
                if (IMAffineNear(ToIM(node.transform), desired)) Write(node, CGAffineTransformIdentity);
                state.owned = NO;
                state.failedFor = signature;
                tally->failed++;
                *reason = @"verify";
                Log([NSString stringWithFormat:@"VERIFY FAILED node=%p %@ unit=%.5f pivot={%.2f,%.2f} anchor={%.2f,%.2f} desired=%@ (write taken back)",
                     (__bridge void *)node, detail, unit, pivot.x, pivot.y, anchorLocal.x, anchorLocal.y, NSStringFromCGAffineTransform(ToCG(desired))]);
                return;
            }
            LogChange(@"apply", [NSString stringWithFormat:@"APPLY node=%p scale=%.3f offset={%.1f,%.1f} unit=%.5f transform=%@ turnFixed=%@ turnModel=%@",
                                 (__bridge void *)node, adj.scale, adj.offsetX, adj.offsetY, unit, NSStringFromCGAffineTransform(ToCG(desired)),
                                 TurnName(TurnInFixed(w)), TurnName(TurnInModel(w))]);
            break;
        }
    }
    if (state.owned) tally->owned++;
}

// One line per structure change: the class chain and the numbers that matter,
// so the first device run says what is really there.
static void DumpChain(UIWindow *w) {
    static NSMutableSet<NSString *> *seen;
    static unsigned dumps;
    if (!seen) seen = [NSMutableSet set];
    NSMutableString *shape = [NSMutableString stringWithFormat:@"window %@", NSStringFromClass(w.class)];
    for (UIView *root in w.subviews) {
        [shape appendFormat:@"|%@", NSStringFromClass(root.class)];
        for (UIView *node in root.subviews) [shape appendFormat:@">%@", NSStringFromClass(node.class)];
    }
    if ([seen containsObject:shape] || dumps >= 12) return;
    [seen addObject:shape];
    dumps++;
    NSMutableString *text = [NSMutableString stringWithFormat:@"CHAIN window %@ bounds=%@ transform=%@ unit=%.5f turnFixed=%@ turnModel=%@",
                             NSStringFromClass(w.class), NSStringFromCGRect(w.bounds), NSStringFromCGAffineTransform(w.transform),
                             IMWindowUnit(ToIM(w.transform)), TurnName(TurnInFixed(w)), TurnName(TurnInModel(w))];
    for (UIView *root in w.subviews) {
        [text appendFormat:@"\n  root %@ frame=%@ transform=%@ subviews=%lu", NSStringFromClass(root.class),
         NSStringFromCGRect(root.frame), NSStringFromCGAffineTransform(root.transform), (unsigned long)root.subviews.count];
        for (UIView *node in root.subviews) {
            [text appendFormat:@"\n    node %@ %p frame=%@ bounds=%@ center=%@ anchor=%@ transform=%@ subviews=%lu",
             NSStringFromClass(node.class), (__bridge void *)node, NSStringFromCGRect(node.frame), NSStringFromCGRect(node.bounds),
             NSStringFromCGPoint(node.center), NSStringFromCGPoint(node.layer.anchorPoint), NSStringFromCGAffineTransform(node.transform),
             (unsigned long)node.subviews.count];
            for (UIView *child in node.subviews)
                [text appendFormat:@"\n      %@ frame=%@ transform=%@", NSStringFromClass(child.class), NSStringFromCGRect(child.frame), NSStringFromCGAffineTransform(child.transform)];
        }
    }
    Log(text);
}

static void WriteStatus(NSDictionary *status) {
    static NSDictionary *last;
    if ([status isEqualToDictionary:last]) return;
    last = status;
    NSMutableDictionary *full = [status mutableCopy];
    full[@"time"] = @(NSDate.date.timeIntervalSince1970);
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:full format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    [data writeToFile:DIFile(@"status.plist") options:NSDataWritingAtomic error:nil];
}

static void Reconcile(void) {
    if (Busy || ![NSThread isMainThread]) return;
    Busy = YES;
    @try {
        NSDictionary *settings = S();
        BOOL killed = access(DI_DISABLED_PATH, F_OK) == 0;
        BOOL enabled = DIFlag(settings, @"AdjustEnabled", YES);
        IMAdjust adj = DIAdjust(settings);
        BOOL wanted = !killed && enabled && !IMIsIdentity(adj);
        NSString *signature = [NSString stringWithFormat:@"%d|%.3f|%.3f|%.3f|%.2f", wanted, adj.scale, adj.offsetX, adj.offsetY, adj.anchorY];

        Tally tally = {0};
        NSString *reason = @"";
        NSString *turnFixed = @"none", *turnModel = @"none";
        NSArray<UIWindow *> *windows = ApertureWindows();
        for (UIWindow *w in windows) {
            DumpChain(w);
            turnFixed = TurnName(TurnInFixed(w));
            turnModel = TurnName(TurnInModel(w));
            double unit = IMWindowUnit(ToIM(w.transform));
            for (UIView *root in w.subviews) {
                if (![root isKindOfClass:PassClass]) continue;
                for (UIView *node in root.subviews)
                    if ([node isKindOfClass:PassClass]) ProcessNode(w, node, wanted, adj, unit, signature, &tally, &reason);
            }
        }
        LogChange(@"orientation", [NSString stringWithFormat:@"ORIENTATION statusBar=%ld turnFixed=%@ turnModel=%@", (long)BarOrientation(), turnFixed, turnModel]);

        NSString *state;
        if (killed) state = @"kill-switch";
        else if (!enabled) state = @"off";
        else if (IMIsIdentity(adj)) state = @"default";
        else if (!windows.count) state = @"no-window";
        else if (tally.failed) state = @"verify-failed";
        else if (tally.conflict) state = @"conflict";
        else if (tally.owned) state = @"applied";
        else if (tally.ineligible) state = [@"ineligible:" stringByAppendingString:reason];
        else state = @"waiting";

        WriteStatus(@{@"version": @DI_VERSION, @"ios": NSProcessInfo.processInfo.operatingSystemVersionString, @"machine": Machine(),
                      @"nativeHeight": @(NativeHeight()), @"windows": @(windows.count), @"nodes": @(tally.nodes), @"owned": @(tally.owned),
                      @"adjust": state, @"turnFixed": turnFixed, @"turnModel": turnModel, @"statusBar": @(BarOrientation()),
                      @"scale": @(adj.scale), @"offsetX": @(adj.offsetX), @"offsetY": @(adj.offsetY), @"guardArmed": @(DIGuardArmed()),
                      @"restoreNote": RestoreNote});
        LogChange(@"state", [NSString stringWithFormat:@"STATE adjust=%@ windows=%lu nodes=%u owned=%u conflict=%u failed=%u ineligible=%u",
                             state, (unsigned long)windows.count, tally.nodes, tally.owned, tally.conflict, tally.failed, tally.ineligible]);
    } @catch (NSException *exception) {
        // Never let this tweak take SpringBoard down with it.
        LogChange(@"exception", [NSString stringWithFormat:@"EXCEPTION in Reconcile: %@ %@", exception.name, exception.reason]);
    } @finally {
        Busy = NO;
    }
}

// ---- Requests from the Settings pane -----------------------------------------------

static NSString *LastRequest;

static void HandleRequest(void) {
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:DIFile(@"request.plist")];
    NSString *identifier = request[@"id"], *action = request[@"action"];
    if (![identifier isKindOfClass:NSString.class] || ![action isKindOfClass:NSString.class] || [identifier isEqualToString:LastRequest]) return;
    LastRequest = identifier;
    double age = NSDate.timeIntervalSinceReferenceDate - [request[@"time"] doubleValue];
    if (!isfinite(age) || age > 30 || age < -5) {
        Log([NSString stringWithFormat:@"REQUEST %@ ignored (age %.1fs)", action, age]);
        return;
    }
    NSInteger mode = [request[@"mode"] integerValue];
    NSDictionary *result;
    if ([action isEqualToString:@"status"]) result = DIDisguiseStatus(NativeHeight());
    else if ([action isEqualToString:@"apply"]) result = DIDisguiseApply(mode, NativeHeight());
    else if ([action isEqualToString:@"restore"]) result = DIDisguiseRestore(NativeHeight());
    else {
        Log([NSString stringWithFormat:@"REQUEST %@ unknown", action]);
        return;
    }
    if (![action isEqualToString:@"status"])
        Log([NSString stringWithFormat:@"REQUEST %@ mode=%ld -> ok=%@ %@", action, (long)mode, result[@"ok"], result[@"message"]]);
    NSMutableDictionary *answer = [result mutableCopy];
    answer[@"id"] = identifier;
    answer[@"action"] = action;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:answer format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    [data writeToFile:DIFile(@"result.plist") options:NSDataWritingAtomic error:nil];
    if ([result[@"respring"] boolValue])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!DIRespring()) Log(@"RESPRING unavailable: FBSystemService exitAndRelaunch: missing");
        });
}

static void OnNotification(__unused CFNotificationCenterRef center, __unused void *observer, CFStringRef name, __unused const void *object, __unused CFDictionaryRef info) {
    NSString *which = [(__bridge NSString *)name copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([which isEqualToString:DINotifySettings]) {
            SettingsStale = YES;
            Reconcile();
        } else if ([which isEqualToString:DINotifyRequest]) {
            @try {
                HandleRequest();
            } @catch (NSException *exception) {
                Log([NSString stringWithFormat:@"EXCEPTION in HandleRequest: %@ %@", exception.name, exception.reason]);
            }
        }
    });
}

// ---- Restore file and the slow tick -------------------------------------------------

static BOOL RestoreFileTried;

static void RestoreByFile(void) {
    if (RestoreFileTried || access(DI_RESTORE_PATH, F_OK) != 0) return;
    RestoreFileTried = YES;
    unlink(DI_RESTORE_PATH);
    NSDictionary *result = DIDisguiseRestore(NativeHeight());
    Log([NSString stringWithFormat:@"RESTORE FILE -> ok=%@ %@", result[@"ok"], result[@"message"]]);
    if ([result[@"respring"] boolValue])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DIRespring(); });
}

static void Tick(void) {
    static unsigned count;
    Reconcile();
    if (++count % 20 == 0) {  // every 5 seconds
        DIGuardTick();
        RestoreByFile();
    }
}

// ---- Install -------------------------------------------------------------------------

static unsigned Attempts;
static void Install(void) {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (os.majorVersion != 16) {
        Log([NSString stringWithFormat:@"NO ADJUST: written for iOS 16, this is %ld.%ld", (long)os.majorVersion, (long)os.minorVersion]);
        return;
    }
    WindowClass = objc_getClass("SBSystemApertureWindow");
    PassClass = objc_getClass("SBFTouchPassThroughView");
    if (!WindowClass || !PassClass || ![WindowClass isSubclassOfClass:UIWindow.class] || ![PassClass isSubclassOfClass:UIView.class]) {
        if (++Attempts < 40) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ Install(); });
        else Log(@"NO ADJUST: SBSystemApertureWindow / SBFTouchPassThroughView not found");
        return;
    }
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    for (NSString *name in @[DINotifySettings, DINotifyRequest])
        CFNotificationCenterAddObserver(center, NULL, OnNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    NSTimer *timer = [NSTimer timerWithTimeInterval:.25 repeats:YES block:^(__unused NSTimer *t) { Tick(); }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    Log([NSString stringWithFormat:@"INSTALLED 灵动岛 %@ ios=%@ machine=%@ nativeHeight=%.0f statusBar=%ld", @DI_VERSION,
         NSProcessInfo.processInfo.operatingSystemVersionString, Machine(), NativeHeight(), (long)BarOrientation()]);
    Reconcile();
}

__attribute__((constructor)) static void DynamicIslandInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        [NSFileManager.defaultManager createDirectoryAtPath:DIDirectory() withIntermediateDirectories:YES attributes:nil error:nil];

        // Undo the disguise before anything else if the last launch after applying
        // it died young, or if the user left the restore file. File operations
        // only here: UIKit is not up yet.
        BOOL tripped = DIGuardStartup();
        BOOL byFile = access(DI_RESTORE_PATH, F_OK) == 0;
        if (tripped || byFile) {
            NSString *note = nil;
            BOOL done = DIDisguiseRestoreFromState(&note);
            RestoreNote = [NSString stringWithFormat:@"%@: %@", tripped ? @"崩溃保护" : @"还原文件", note ?: @""];
            Log([NSString stringWithFormat:@"%@ restore at launch -> done=%d %@", tripped ? @"GUARD" : @"FILE", done, note]);
            if (done && byFile) unlink(DI_RESTORE_PATH);
            if (done)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DIRespring(); });
        }
        dispatch_async(dispatch_get_main_queue(), ^{ Install(); });
    }
}
