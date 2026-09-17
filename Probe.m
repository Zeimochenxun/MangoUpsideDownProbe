#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#ifdef SF_SPRINGBOARD
#import <UIKit/UIKit.h>
#endif
#include <dlfcn.h>
#include <notify.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <string.h>

// No method hooks, orientation setters, synthesized touches, or display creation.
// Private getter ABI must match runtime metadata before any invocation.
static int SFLogFD = -1;
static BOOL SFCapturing = NO;
static NSString *SFProcess;

static void SFLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void SFLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (SFLogFD < 0) return;
    struct stat st;
    if (fstat(SFLogFD, &st) == 0 && st.st_size > 2 * 1024 * 1024) {
        if (ftruncate(SFLogFD, 0) != 0) return;
    }
    NSString *line = [NSString stringWithFormat:@"%.3f pid=%d %@ %@\n",
                      NSDate.date.timeIntervalSince1970, getpid(), SFProcess, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = data.bytes;
    size_t remaining = data.length;
    while (remaining) {
        ssize_t count = write(SFLogFD, bytes, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        bytes += count;
        remaining -= (size_t)count;
    }
}

static void SFOpenLog(void) {
    for (NSString *directory in @[@"/var/mobile/Library/Logs", @"/tmp"]) {
        NSString *path = [directory stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"SystemFlipProbe-%@.log", SFProcess]];
        SFLogFD = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (SFLogFD >= 0) {
            NSLog(@"[SystemFlipProbe] log=%@", path);
            SFLog(@"START version=0.1.0 mode=read-only os=%@ log=%@", NSProcessInfo.processInfo.operatingSystemVersionString, path);
            break;
        }
    }
    if (SFLogFD < 0) NSLog(@"[SystemFlipProbe] Cannot open log: %s", strerror(errno));
}

static NSMethodSignature *SFSignature(id target, SEL selector) {
    if (!target) return nil;
    Method method = class_getInstanceMethod(object_getClass(target), selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
}

static BOOL SFMatch(id target, SEL selector, const char *ret, NSUInteger args,
                    const char *a2, const char *a3) {
    NSMethodSignature *sig = SFSignature(target, selector);
    BOOL match = sig && sig.numberOfArguments == args && strcmp(sig.methodReturnType, ret) == 0;
    if (match && a2) match = strcmp([sig getArgumentTypeAtIndex:2], a2) == 0;
    if (match && a3) match = strcmp([sig getArgumentTypeAtIndex:3], a3) == 0;
    if (!match) SFLog(@"SKIP class=%@ selector=%@ signature-missing-or-mismatch", NSStringFromClass(object_getClass(target)), NSStringFromSelector(selector));
    return match;
}

#ifndef SF_SPRINGBOARD
static id SFObject(id target, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!SFMatch(target, selector, @encode(id), 2, NULL, NULL)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}
#endif

static NSString *SFUnsigned(id target, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!SFMatch(target, selector, @encode(unsigned int), 2, NULL, NULL)) return @"unavailable";
    unsigned int value = ((unsigned int (*)(id, SEL))objc_msgSend)(target, selector);
    return [NSString stringWithFormat:@"%u", value];
}

static NSString *SFRect(CGRect r) {
    return [NSString stringWithFormat:@"[%.3f,%.3f,%.3f,%.3f]", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static void SFMethod(Class cls, BOOL classMethod, NSString *name) {
    Method m = classMethod ? class_getClassMethod(cls, NSSelectorFromString(name)) : class_getInstanceMethod(cls, NSSelectorFromString(name));
    SFLog(@"METHOD %c[%@ %@] types=%s", classMethod ? '+' : '-', NSStringFromClass(cls), name, m ? method_getTypeEncoding(m) : "MISSING");
}

static void SFMetadata(void) {
    Class server = NSClassFromString(@"CAWindowServer");
    Class display = NSClassFromString(@"CAWindowServerDisplay");
    SFMethod(server, YES, @"serverIfRunning");
    SFMethod(server, NO, @"displays");
    for (NSString *name in @[@"orientation", @"setOrientation:", @"bounds", @"displayId", @"name", @"deviceName", @"contextIdAtPosition:", @"convertPoint:toContextId:", @"convertPoint:fromContextId:"]) SFMethod(display, NO, name);
    // Report address availability only. Do not infer C signatures or invoke symbols.
    const char *symbols[] = {"kCAWindowServerOrientation_Portrait", "kCAWindowServerOrientation_PortraitUpsideDown", "BKSHIDServicesSetDeviceInterfaceOrientation", "BKSHIDServicesGetCALayerTransform", "CARenderServerSetAXMatrix"};
    for (unsigned i = 0; i < sizeof(symbols) / sizeof(symbols[0]); i++) {
        void *address = dlsym(RTLD_DEFAULT, symbols[i]);
        Dl_info info = {0};
        if (address) dladdr(address, &info);
        SFLog(@"SYMBOL %s loaded=%d image=%s", symbols[i], address != NULL, info.dli_fname ?: "unavailable");
    }
}

#ifndef SF_SPRINGBOARD
static void SFDisplaySnapshot(void) {
    // serverIfRunning only: never call +server or +serverWithOptions: to create one.
    id server = SFObject(NSClassFromString(@"CAWindowServer"), @"serverIfRunning");
    if (!server) { SFLog(@"DISPLAY serverIfRunning=nil"); return; }
    id displays = SFObject(server, @"displays");
    if (![displays isKindOfClass:NSArray.class]) { SFLog(@"DISPLAY displays-not-array"); return; }
    NSUInteger count = 0;
    for (id display in (NSArray *)displays) {
        if (++count > 8) break;
        SFLog(@"DISPLAY class=%@ id=%@ name=%@ device=%@ orientation=%@",
              NSStringFromClass([display class]), SFUnsigned(display, @"displayId"),
              SFObject(display, @"name"), SFObject(display, @"deviceName"), SFObject(display, @"orientation"));
        SEL boundsSel = NSSelectorFromString(@"bounds");
        if (!SFMatch(display, boundsSel, @encode(CGRect), 2, NULL, NULL)) continue;
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(display, boundsSel);
        SFLog(@"DISPLAY bounds=%@ units=server-defined", SFRect(bounds));
        if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width <= 0 || bounds.size.height <= 0) continue;
        SEL hit = NSSelectorFromString(@"contextIdAtPosition:");
        SEL to = NSSelectorFromString(@"convertPoint:toContextId:");
        SEL from = NSSelectorFromString(@"convertPoint:fromContextId:");
        if (!SFMatch(display, hit, @encode(unsigned int), 3, @encode(CGPoint), NULL) ||
            !SFMatch(display, to, @encode(CGPoint), 4, @encode(CGPoint), @encode(unsigned int)) ||
            !SFMatch(display, from, @encode(CGPoint), 4, @encode(CGPoint), @encode(unsigned int))) continue;
        const CGPoint fractions[] = {{.1,.1}, {.9,.1}, {.5,.5}, {.1,.9}, {.9,.9}};
        for (unsigned i = 0; i < 5; ++i) {
            CGPoint p = {bounds.origin.x + fractions[i].x * bounds.size.width, bounds.origin.y + fractions[i].y * bounds.size.height};
            unsigned int context = ((unsigned int (*)(id, SEL, CGPoint))objc_msgSend)(display, hit, p);
            if (!context) { SFLog(@"MAP sample=%u context=0", i); continue; }
            CGPoint local = ((CGPoint (*)(id, SEL, CGPoint, unsigned int))objc_msgSend)(display, to, p, context);
            CGPoint roundtrip = ((CGPoint (*)(id, SEL, CGPoint, unsigned int))objc_msgSend)(display, from, local, context);
            SFLog(@"MAP sample=%u context=%u server=[%.3f,%.3f] local=[%.3f,%.3f] roundtrip=[%.3f,%.3f]",
                  i, context, p.x, p.y, local.x, local.y, roundtrip.x, roundtrip.y);
        }
    }
}
#endif

#ifdef SF_SPRINGBOARD
static NSString *SFAffine(CGAffineTransform t) {
    return [NSString stringWithFormat:@"[%.4f,%.4f,%.4f,%.4f,%.3f,%.3f]", t.a, t.b, t.c, t.d, t.tx, t.ty];
}
static NSString *SFLayerMatrix(CATransform3D t) {
    return [NSString stringWithFormat:@"[%.4f,%.4f,%.4f,%.4f;%.4f,%.4f,%.4f,%.4f;%.4f,%.4f,%.4f,%.4f;%.4f,%.4f,%.4f,%.4f]",
            t.m11,t.m12,t.m13,t.m14,t.m21,t.m22,t.m23,t.m24,t.m31,t.m32,t.m33,t.m34,t.m41,t.m42,t.m43,t.m44];
}
static void SFWindowSnapshot(void) {
    UIScreen *screen = UIScreen.mainScreen;
    SFLog(@"SCREEN bounds=%@ native=%@ coordinate=%@ fixed=%@ scale=%.3f", SFRect(screen.bounds), SFRect(screen.nativeBounds), SFRect(screen.coordinateSpace.bounds), SFRect(screen.fixedCoordinateSpace.bounds), screen.scale);
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        SFLog(@"SCENE class=%@ state=%ld orientation=%ld coordinate=%@", NSStringFromClass(ws.class), (long)ws.activationState, (long)ws.interfaceOrientation, SFRect(ws.coordinateSpace.bounds));
        [windows addObjectsFromArray:ws.windows];
    }
    // Include system windows that are not exposed by connected window scenes.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    NSUInteger count = 0;
    for (UIWindow *w in windows) {
        if (++count > 96) break;
        SFLog(@"WINDOW class=%@ context=%@ hidden=%d level=%.2f orientation=%ld bounds=%@ center=[%.3f,%.3f] transform=%@ safe=[%.3f,%.3f,%.3f,%.3f]",
              NSStringFromClass(w.class), SFUnsigned(w, @"_contextId"), w.hidden, w.windowLevel,
              (long)w.windowScene.interfaceOrientation, SFRect(w.bounds), w.center.x, w.center.y, SFAffine(w.transform), w.safeAreaInsets.top, w.safeAreaInsets.left, w.safeAreaInsets.bottom, w.safeAreaInsets.right);
        SFLog(@"LAYER context=%@ model=%@ presentation=%@", SFUnsigned(w, @"_contextId"), SFLayerMatrix(w.layer.transform), w.layer.presentationLayer ? SFLayerMatrix(w.layer.presentationLayer.transform) : @"nil");
    }
}
#endif

static void SFSnapshot(NSString *label, unsigned sample) {
    @autoreleasepool {
        SFLog(@"CAPTURE label=%@ sample=%u", label, sample);
        @try {
#ifdef SF_SPRINGBOARD
            SFWindowSnapshot();
#else
            SFDisplaySnapshot();
#endif
        } @catch (NSException *exception) {
            SFLog(@"EXCEPTION name=%@ reason=%@", exception.name, exception.reason);
        }
        SFLog(@"END label=%@ sample=%u", label, sample);
    }
}

__attribute__((constructor)) static void SFInit(void) {
    @autoreleasepool {
        SFProcess = NSProcessInfo.processInfo.processName;
#ifdef SF_SPRINGBOARD
        if (![SFProcess isEqualToString:@"SpringBoard"]) return;
#else
        if (![SFProcess isEqualToString:@"backboardd"]) return;
#endif
        dispatch_async(dispatch_get_main_queue(), ^{
            SFOpenLog();
            if (SFLogFD < 0) return;
            SFMetadata();
            for (NSString *label in @[@"portrait", @"upside-down", @"landscape", @"lock-screen"]) {
                NSString *name = [@"com.chenxun.systemflipprobe.capture." stringByAppendingString:label];
                int token = 0;
                uint32_t status = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int unusedToken) {
                    if (SFCapturing) { SFLog(@"BUSY label=%@", label); return; }
                    SFCapturing = YES;
                    SFSnapshot(label, 0);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ SFSnapshot(label, 1); });
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ SFSnapshot(label, 2); SFCapturing = NO; });
                });
                SFLog(@"NOTIFY label=%@ status=%u", label, status);
            }
            // Metadata-only startup. Geometry snapshots require an explicit capture request.
        });
    }
}
