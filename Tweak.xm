// Diagnostic source, NOT a positioning fix. Original methods run exactly once.
// Verified against Mango UUID 67C0D7C2-4487-3FD2-9535-067745AE4B8F.
// No binary offsets, no preference writes to Mango, no backboardd injection.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <substrate.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string.h>
#include <strings.h>
#include <errno.h>

static const char *kDisabled = "/var/mobile/Library/Preferences/MangoUpsideDownProbe.disabled";
static const char *kLog = "/var/mobile/Library/Logs/MangoUpsideDownProbe.log";
static NSHashTable<UIWindow *> *gFallbackWindows;
static NSHashTable<UIView *> *gHostViews;
static __weak UIViewController *gAperture;
static NSMapTable<id, NSNumber *> *gLastCapture;
static BOOL gInstalled;
static unsigned gTryCount;

static BOOL Enabled(void) { return access(kDisabled, F_OK) != 0; }

static void Log(NSString *line) {
    if (!Enabled() || ![NSThread isMainThread]) return;
    NSString *text = [NSString stringWithFormat:@"%.3f [MangoUDProbe] %@\n",
                      [NSDate timeIntervalSinceReferenceDate], line];
    NSLog(@"[MangoUDProbe] %@", line);
    mkdir("/var/mobile/Library/Logs", 0755);
    int fd = open(kLog, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
    if (fd < 0) return; // Unified log remains available if file access fails.
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return; }
    if (st.st_size > 1024 * 1024) ftruncate(fd, 0);
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *p = (const uint8_t *)data.bytes;
    size_t left = data.length;
    while (left) {
        ssize_t n = write(fd, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        p += n; left -= (size_t)n;
    }
    close(fd);
}

static NSString *Matrix(CATransform3D t) {
    return [NSString stringWithFormat:
        @"[%.4g %.4g %.4g %.4g; %.4g %.4g %.4g %.4g; %.4g %.4g %.4g %.4g; %.4g %.4g %.4g %.4g]",
        t.m11,t.m12,t.m13,t.m14,t.m21,t.m22,t.m23,t.m24,
        t.m31,t.m32,t.m33,t.m34,t.m41,t.m42,t.m43,t.m44];
}

static BOOL RateAllows(id object) {
    if (!Enabled() || ![NSThread isMainThread] || !object) return NO;
    double now = CACurrentMediaTime();
    NSNumber *last = [gLastCapture objectForKey:object];
    if (last && now - last.doubleValue < 0.8) return NO;
    [gLastCapture setObject:@(now) forKey:object];
    return YES;
}

static void CaptureView(UIView *v, NSString *reason) {
    if (!Enabled() || ![NSThread isMainThread] || ![v isKindOfClass:[UIView class]]) return;
    @try {
        UIWindow *w = v.window;
        UIScreen *screen = w.screen ?: [UIScreen mainScreen];
        CGRect b = v.bounds;
        CGPoint a = [v convertPoint:CGPointMake(CGRectGetMinX(b), CGRectGetMinY(b))
                  toCoordinateSpace:screen.fixedCoordinateSpace];
        CGPoint x = [v convertPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMinY(b))
                  toCoordinateSpace:screen.fixedCoordinateSpace];
        CGPoint y = [v convertPoint:CGPointMake(CGRectGetMinX(b), CGRectGetMaxY(b))
                  toCoordinateSpace:screen.fixedCoordinateSpace];
        Log([NSString stringWithFormat:
             @"%@ view=%@/%p window=%@/%p frame=%@ bounds=%@ center=%@ safe=%@ transform=%@ fixedBasis={%@,%@,%@} sceneOrientation=%ld",
             reason, NSStringFromClass(v.class), (__bridge void *)v,
             w ? NSStringFromClass(w.class) : @"nil", (__bridge void *)w,
             NSStringFromCGRect(v.frame), NSStringFromCGRect(b), NSStringFromCGPoint(v.center),
             NSStringFromUIEdgeInsets(v.safeAreaInsets), NSStringFromCGAffineTransform(v.transform),
             NSStringFromCGPoint(a), NSStringFromCGPoint(x), NSStringFromCGPoint(y),
             (long)w.windowScene.interfaceOrientation]);
        CALayer *presentation = (CALayer *)v.layer.presentationLayer;
        Log([NSString stringWithFormat:@"%@ layer=%@ sublayer=%@ presentationFrame=%@",
             reason, Matrix(v.layer.transform), Matrix(v.layer.sublayerTransform),
             presentation ? NSStringFromCGRect(presentation.frame) : @"nil"]);
        if (w && v != w) {
            Log([NSString stringWithFormat:@"%@ windowFrame=%@ windowBounds=%@ windowTransform=%@ windowLayer=%@ windowSafe=%@",
                 reason, NSStringFromCGRect(w.frame), NSStringFromCGRect(w.bounds),
                 NSStringFromCGAffineTransform(w.transform), Matrix(w.layer.transform),
                 NSStringFromUIEdgeInsets(w.safeAreaInsets)]);
        }
    } @catch (NSException *e) {
        Log([NSString stringWithFormat:@"capture exception class=%@", e.name]);
    }
}

static NSInteger MangoOrientation(void) {
    Class cls = objc_getClass("DecoratedAppSceneView");
    SEL sel = sel_registerName("mango_currentInterfaceOrientation");
    Method m = cls ? class_getClassMethod(cls, sel) : NULL;
    if (!m || method_getNumberOfArguments(m) != 2) return -1;
    char type[64] = {0}; method_getReturnType(m, type, sizeof(type));
    if (strcmp(type, @encode(NSInteger)) != 0) return -1;
    return ((NSInteger (*)(id, SEL))objc_msgSend)((id)cls, sel);
}

static UIViewController *FindAperture(UIViewController *vc, unsigned depth, unsigned *budget) {
    if (!vc || depth > 8 || *budget == 0) return nil;
    --*budget;
    Class cls = objc_getClass("SBSystemApertureViewController");
    if (cls && [vc isKindOfClass:cls]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *found = FindAperture(child, depth + 1, budget);
        if (found) return found;
    }
    return FindAperture(vc.presentedViewController, depth + 1, budget);
}

static void Snapshot(NSString *reason) {
    if (!Enabled() || ![NSThread isMainThread]) return;
    @try {
        UIScreen *s = UIScreen.mainScreen;
        Log([NSString stringWithFormat:@"SNAP %@ mangoOrientation=%ld statusBarOrientation=%ld deviceOrientation=%ld screen=%@ native=%@ scale=%.2f",
             reason, (long)MangoOrientation(), (long)UIApplication.sharedApplication.statusBarOrientation,
             (long)UIDevice.currentDevice.orientation, NSStringFromCGRect(s.bounds),
             NSStringFromCGRect(s.nativeBounds), s.scale]);
        UIViewController *vc = gAperture;
        if (!vc) {
            unsigned budget = 128;
            for (UIWindow *w in UIApplication.sharedApplication.windows) {
                vc = FindAperture(w.rootViewController, 0, &budget);
                if (vc) { gAperture = vc; break; }
            }
        }
        if (vc.isViewLoaded) CaptureView(vc.view, @"native-aperture-root");
        for (UIView *v in gHostViews.allObjects) CaptureView(v, @"Mango-layout-host");
        for (UIWindow *w in gFallbackWindows.allObjects) CaptureView(w, @"Mango-fallback-window");
    } @catch (NSException *e) { Log([NSString stringWithFormat:@"snapshot exception class=%@", e.name]); }
}

static NSArray<UIWindow *> *Windows(void) {
    NSMutableOrderedSet<UIWindow *> *set = [NSMutableOrderedSet orderedSet];
    [set addObjectsFromArray:UIApplication.sharedApplication.windows];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]])
            [set addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    return set.array;
}

static void (*OrigOrientation)(id, SEL, id);
static void HookOrientation(id self, SEL cmd, id note) {
    OrigOrientation(self, cmd, note);
    if (!Enabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        Log(@"MangoPillManager orientation callback returned (original dismissal policy preserved)");
        Snapshot(@"orientation-callback");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ Snapshot(@"orientation-settled"); });
    });
}

static void (*OrigLayoutHost)(id, SEL, id);
static void HookLayoutHost(id self, SEL cmd, id host) {
    OrigLayoutHost(self, cmd, host);
    if (!Enabled() || ![NSThread isMainThread]) return;
    if ([host isKindOfClass:[UIView class]]) {
        [gHostViews addObject:host];
        if (RateAllows(host)) CaptureView(host, @"layoutHostContainerViewDidLayoutSubviews");
    } else if (RateAllows(self)) {
        Log([NSString stringWithFormat:@"layout callback argument class=%@ (no guessed private getter used)",
             host ? NSStringFromClass([host class]) : @"nil"]);
    }
}

static UIEdgeInsets (*OrigOutsets)(id, SEL, NSInteger, UIEdgeInsets, UIEdgeInsets);
static UIEdgeInsets HookOutsets(id self, SEL cmd, NSInteger mode, UIEdgeInsets suggested, UIEdgeInsets maximum) {
    UIEdgeInsets result = OrigOutsets(self, cmd, mode, suggested, maximum);
    if (RateAllows(self)) {
        Log([NSString stringWithFormat:@"outsets mode=%ld mangoOrientation=%ld suggested=%@ maximum=%@ result=%@",
             (long)mode, (long)MangoOrientation(), NSStringFromUIEdgeInsets(suggested),
             NSStringFromUIEdgeInsets(maximum), NSStringFromUIEdgeInsets(result)]);
    }
    return result; // Do not swap top/bottom or reinterpret insets as a frame.
}

static void (*OrigFallback)(id, SEL, id);
static void HookFallback(id self, SEL cmd, id element) {
    BOOL observe = Enabled() && [NSThread isMainThread];
    NSArray<UIWindow *> *before = observe ? Windows() : nil;
    OrigFallback(self, cmd, element);
    if (!observe) return;
    Log(@"showFallbackPill: called (fallback route positively identified)");
    for (UIWindow *w in Windows()) {
        if (![before containsObject:w]) {
            [gFallbackWindows addObject:w];
            CaptureView(w, @"new-window-during-showFallbackPill");
        }
    }
    // An added window is a candidate until its geometry/hierarchy is checked.
}

static void (*OrigApertureAppear)(id, SEL, BOOL);
static void HookApertureAppear(id self, SEL cmd, BOOL animated) {
    OrigApertureAppear(self, cmd, animated);
    if (!Enabled() || ![NSThread isMainThread]) return;
    if ([self isKindOfClass:[UIViewController class]]) {
        gAperture = (UIViewController *)self;
        Snapshot(@"SBSystemApertureViewController.viewWillAppear");
    }
}

static BOOL Signature(Class c, SEL s, const char *ret, NSArray<NSString *> *args) {
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m || method_getNumberOfArguments(m) != args.count + 2) return NO;
    char type[512] = {0}; method_getReturnType(m, type, sizeof(type));
    if (strcmp(type, ret) != 0) return NO;
    for (NSUInteger i = 0; i < args.count; ++i) {
        memset(type, 0, sizeof(type));
        method_getArgumentType(m, (unsigned)i + 2, type, sizeof(type));
        if (strcmp(type, args[i].UTF8String) != 0) return NO;
    }
    return YES;
}

static BOOL VerifiedMangoLoaded(void) {
    const uint8_t expected[16] = {0x67,0xc0,0xd7,0xc2,0x44,0x87,0x3f,0xd2,0x95,0x35,0x06,0x77,0x45,0xae,0x4b,0x8f};
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *path = _dyld_get_image_name(i);
        if (!path) continue;
        const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
        if (strcasecmp(base, "mango.dylib") != 0) continue;
        const struct mach_header *raw = _dyld_get_image_header(i);
        if (!raw || raw->magic != MH_MAGIC_64) return NO;
        const struct mach_header_64 *h = (const struct mach_header_64 *)raw;
        const uint8_t *p = (const uint8_t *)(h + 1), *end = p + h->sizeofcmds;
        for (uint32_t n = 0; n < h->ncmds; ++n) {
            if (p + sizeof(struct load_command) > end) return NO;
            const struct load_command *c = (const struct load_command *)p;
            if (c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end - p)) return NO;
            if (c->cmd == LC_UUID && c->cmdsize >= sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)p)->uuid, expected, 16) == 0;
            p += c->cmdsize;
        }
        return NO;
    }
    return NO;
}

static void Heartbeat(unsigned remaining) {
    if (!Enabled() || remaining == 0) return;
    Snapshot(@"periodic");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ Heartbeat(remaining - 1); });
}

static void TryInstall(void) {
    if (gInstalled || !Enabled()) return;
    if (!VerifiedMangoLoaded()) {
        if (++gTryCount < 40) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                                            dispatch_get_main_queue(), ^{ TryInstall(); });
        else Log(@"No matching Mango UUID within 20 seconds; no hooks installed.");
        return;
    }
    Class manager = objc_getClass("MangoPillManager"), element = objc_getClass("MangoPillElement");
    Class aperture = objc_getClass("SBSystemApertureViewController");
    SEL orientation = sel_registerName("handleInterfaceOrientationChange:");
    SEL fallback = sel_registerName("showFallbackPill:");
    SEL layout = sel_registerName("layoutHostContainerViewDidLayoutSubviews:");
    SEL outsets = sel_registerName("preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:");
    SEL appear = sel_registerName("viewWillAppear:");
    NSArray *oneObject = @[@"@"];
    NSArray *outsetArgs = @[[NSString stringWithUTF8String:@encode(NSInteger)],
                            [NSString stringWithUTF8String:@encode(UIEdgeInsets)],
                            [NSString stringWithUTF8String:@encode(UIEdgeInsets)]];
    if (!Signature(manager, orientation, "v", oneObject) || !Signature(manager, fallback, "v", oneObject) ||
        !Signature(element, layout, "v", oneObject) || !Signature(element, outsets, @encode(UIEdgeInsets), outsetArgs)) {
        Log(@"Runtime signature mismatch; no hooks installed."); return;
    }
    gFallbackWindows = [NSHashTable weakObjectsHashTable];
    gHostViews = [NSHashTable weakObjectsHashTable];
    gLastCapture = [NSMapTable weakToStrongObjectsMapTable];
    MSHookMessageEx(manager, orientation, (IMP)HookOrientation, (IMP *)&OrigOrientation);
    MSHookMessageEx(manager, fallback, (IMP)HookFallback, (IMP *)&OrigFallback);
    MSHookMessageEx(element, layout, (IMP)HookLayoutHost, (IMP *)&OrigLayoutHost);
    MSHookMessageEx(element, outsets, (IMP)HookOutsets, (IMP *)&OrigOutsets);
    BOOL nativeSignature = Signature(aperture, appear, "v", @[@"B"]) || Signature(aperture, appear, "v", @[@"c"]);
    if (nativeSignature) MSHookMessageEx(aperture, appear, (IMP)HookApertureAppear, (IMP *)&OrigApertureAppear);
    gInstalled = YES;
    Log(@"Installed observational hooks; original behavior preserved.");
    Log(nativeSignature ? @"native-appear=yes" : @"native-appear=no");
    // Use the actual local notification observed in the supplied binary.
    // This is NSNotificationCenter, not a Darwin notification.
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange" object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (!Enabled()) return;
            id value = note.userInfo[@"orientation"];
            if ([value isKindOfClass:[NSNumber class]])
                Log([NSString stringWithFormat:@"local-notification orientation=%ld", (long)[value integerValue]]);
            Snapshot(@"local-notification");
        }];
    Heartbeat(300); // Ten minutes, two-second sampling, bounded 1 MiB file.
}

__attribute__((constructor)) static void StartProbe(void) {
    @autoreleasepool {
        if (!Enabled()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ TryInstall(); });
    }
}
