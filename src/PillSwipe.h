#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CGGeometry.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <string.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
#import "StartupDiagnostics.h"
#include "PillSwipePolicy.h"
#include "../modules/orientation/OrientationPolicy.h"

// Notification swipe direction for an upside-down interface (switch 7).
// Runtime-only (no UIKit link) because the loader is also injected into
// backboardd. It replaces nothing but the one gesture argument handed to
// -[MangoPillElement handlePanGesture:]; the recognizer itself is never
// mutated, no UIKit method is hooked, and the original always runs once.
// The verified handler sends its argument only -state, -view and
// -translationInView: (build-info/beta94-audit); anything else is forwarded.

static NSString *const MSPillHelloUUID = @"2E847FEA-97B0-3739-9097-3CEDCC5E1D1A";
static const NSInteger MSPillStateEnded = 3; // UIGestureRecognizerStateEnded

@interface MSPillPanProxy : NSObject
@property(nonatomic, strong) id gesture;
@property(nonatomic) CGPoint translation;
@end
@implementation MSPillPanProxy
- (NSInteger)state { return ((NSInteger (*)(id, SEL))objc_msgSend)(self.gesture, sel_registerName("state")); }
- (id)view { return ((id (*)(id, SEL))objc_msgSend)(self.gesture, sel_registerName("view")); }
- (CGPoint)translationInView:(__unused id)view { return self.translation; }
- (id)forwardingTargetForSelector:(__unused SEL)selector { return self.gesture; }
@end

static IMP MSPillOriginalPan;
static unsigned MSPillAttempts;
static BOOL MSPillInstalled;

static BOOL MSPillIMPIsBeta9Hello(IMP imp) {
    if (!imp) return NO;
    const void *pointer = (const void *)imp;
#if __has_feature(ptrauth_calls)
    pointer = ptrauth_strip(pointer, ptrauth_key_function_pointer);
#endif
    Dl_info info = {0};
    if (!dladdr(pointer, &info) || !info.dli_fbase || !info.dli_fname) return NO;
    const char *base = strrchr(info.dli_fname, '/');
    return !strcmp(base ? base + 1 : info.dli_fname, "MangoHello.dylib") &&
           [MSImageUUID((const struct mach_header *)info.dli_fbase) isEqualToString:MSPillHelloUUID];
}

static long MSPillOrientation(void) {
    long mango = 0, system = 0;
    Class scene = objc_getClass("DecoratedAppSceneView");
    SEL getter = sel_registerName("mango_currentInterfaceOrientation");
    Method method = scene ? class_getClassMethod(scene, getter) : NULL;
    if (method && !strcmp(method_getTypeEncoding(method), "q16@0:8"))
        mango = ((long (*)(id, SEL))objc_msgSend)((id)scene, getter);
    Class application = objc_getClass("UIApplication");
    id shared = application ? ((id (*)(id, SEL))objc_msgSend)((id)application, sel_registerName("sharedApplication")) : nil;
    if (shared) system = ((long (*)(id, SEL))objc_msgSend)(shared, sel_registerName("statusBarOrientation"));
    return MSB8ResolvedOrientation(mango, system);
}

// Returns a proxy only when the handler would otherwise see the wrong vertical
// direction; nil means "hand the real gesture to the original, unchanged".
static id MSPillProxyFor(id gesture) {
    if (!gesture || !NSThread.isMainThread) return nil;
    // Cheapest checks first: Changed callbacks arrive every frame.
    if (((NSInteger (*)(id, SEL))objc_msgSend)(gesture, sel_registerName("state")) != MSPillStateEnded) return nil;
    if (!MSRuntimeFlag(@"SwipeDirectionEnabled")) return nil;
    long orientation = MSPillOrientation();
    if (orientation != 2) return nil;
    id view = ((id (*)(id, SEL))objc_msgSend)(gesture, sel_registerName("view"));
    id window = view ? ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("window")) : nil;
    id screen = window ? ((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("screen")) : nil;
    id fixed = screen ? ((id (*)(id, SEL))objc_msgSend)(screen, sel_registerName("fixedCoordinateSpace")) : nil;
    if (!fixed) return nil;
    CGPoint local = ((CGPoint (*)(id, SEL, id))objc_msgSend)(gesture, sel_registerName("translationInView:"), view);
    SEL convert = sel_registerName("convertPoint:toCoordinateSpace:");
    CGPoint origin = ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(view, convert, CGPointMake(0, 0), fixed);
    CGPoint moved = ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(view, convert, local, fixed);
    double userY = MSPillSwipeY(orientation, local.y, moved.y - origin.y);
    BOOL change = MSPillSwipeChanges(local.y, userY);
    if (MSDiagnosticsActive())
        MSDiagnosticsLog(@"Startup", [NSString stringWithFormat:@"PILLSWIPE ended orientation=%ld localY=%.2f fixedY=%.2f handlerY=%.2f substituted=%d attempts=%u",
                                      orientation, local.y, moved.y - origin.y, change ? userY : local.y, change, MSPillAttempts]);
    if (!change) return nil;
    MSPillPanProxy *proxy = [MSPillPanProxy new];
    proxy.gesture = gesture;
    proxy.translation = CGPointMake(local.x, userY);
    return proxy;
}

static void MSPillPanHook(id controller, SEL selector, id gesture) {
    id argument = gesture;
    @try { id proxy = MSPillProxyFor(gesture); if (proxy) argument = proxy; }
    @catch (__unused NSException *exception) { argument = gesture; }
    ((void (*)(id, SEL, id))MSPillOriginalPan)(controller, selector, argument);
}

// MangoHello loads after this injection, so poll for its class like the World
// module does. Identity: Beta9-1 MangoHello UUID and the exact method type.
static void MSPillSwipeInstall(void) {
    if (MSPillInstalled) return;
    Class pill = objc_getClass("MangoPillElement");
    SEL selector = sel_registerName("handlePanGesture:");
    Method method = pill ? class_getInstanceMethod(pill, selector) : NULL;
    if (method && !strcmp(method_getTypeEncoding(method), "v24@0:8@16") &&
        MSPillIMPIsBeta9Hello(method_getImplementation(method))) {
        MSPillOriginalPan = method_getImplementation(method);
        class_replaceMethod(pill, selector, (IMP)MSPillPanHook, method_getTypeEncoding(method));
        MSPillInstalled = YES;
        NSLog(@"[MangoSuite] pill swipe installed attempts=%u", MSPillAttempts);
        return;
    }
    if (++MSPillAttempts < 40)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ MSPillSwipeInstall(); });
    else NSLog(@"[MangoSuite] pill swipe not installed: Beta9-1 MangoPillElement handler not found");
}
