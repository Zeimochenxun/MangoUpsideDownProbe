#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <roothide.h>
#include <string.h>
#include <unistd.h>
#include "OrientationPolicy.h"
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

// These UUIDs identify the unmodified supplied Beta9 modules. They do not
// bypass or replace Mango's own licensing / runtime challenge checks.
static inline const struct mach_header *B9Image(const char *filename,
                                               const uint8_t expected[16]) {
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *base = strrchr(name, '/');
        if (strcmp(base ? base + 1 : name, filename)) continue;
        const struct mach_header_64 *h = (const void *)_dyld_get_image_header(i);
        if (!h || h->magic != MH_MAGIC_64 || h->sizeofcmds > 1024 * 1024) return NULL;
        const uint8_t *p = (const void *)(h + 1), *end = p + h->sizeofcmds;
        for (uint32_t n = 0; n < h->ncmds; ++n) {
            if ((size_t)(end - p) < sizeof(struct load_command)) return NULL;
            const struct load_command *lc = (const void *)p;
            if (lc->cmdsize < sizeof(*lc) || lc->cmdsize > (size_t)(end - p)) return NULL;
            if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)p)->uuid, expected, 16) ? NULL : (const void *)h;
            p += lc->cmdsize;
        }
        return NULL;
    }
    return NULL;
}

static inline const struct mach_header *B9Hello(void) {
    const uint8_t uuid[16] = {0x2e,0x84,0x7f,0xea,0x97,0xb0,0x37,0x39,
                             0x90,0x97,0x3c,0xed,0xcc,0x5e,0x1d,0x1a};
    return B9Image("MangoHello.dylib", uuid);
}

static inline BOOL B9ClassIsHello(Class cls) {
    const char *origin = cls ? class_getImageName(cls) : NULL;
    if (!origin) return NO;
    const char *base = strrchr(origin, '/');
    return !strcmp(base ? base + 1 : origin, "MangoHello.dylib");
}

static inline BOOL B9VerifiedMango(void) {
    const uint8_t panda[16] = {0x20,0x81,0xda,0x7e,0x6c,0x9b,0x30,0xaa,
                             0x9b,0x3e,0x2d,0xa9,0x62,0x8a,0x5b,0x95};
    if (!B9Hello() || !B9Image("MangoPanda.dylib", panda)) return NO;
    Class pill = objc_getClass("MangoPillElement");
    Class scene = objc_getClass("DecoratedAppSceneView");
    Class floating = objc_getClass("DecoratedFloatingView");
    if (!B9ClassIsHello(pill) || !B9ClassIsHello(scene) || !B9ClassIsHello(floating)) return NO;
    Method pan = class_getInstanceMethod(pill, sel_registerName("handlePanGesture:"));
    Method host = class_getInstanceMethod(pill, sel_registerName("layoutHostContainerViewDidLayoutSubviews:"));
    Method orientation = class_getClassMethod(scene, sel_registerName("mango_currentInterfaceOrientation"));
    return pan && host && orientation &&
        !strcmp(method_getTypeEncoding(pan), "v24@0:8@16") &&
        !strcmp(method_getTypeEncoding(host), "v24@0:8@16") &&
        !strcmp(method_getTypeEncoding(orientation), "q16@0:8");
}

static inline BOOL B9IMPIsHello(IMP imp) {
    if (!imp) return NO;
    const void *pointer = (const void *)imp;
#if __has_feature(ptrauth_calls)
    pointer = ptrauth_strip(pointer, ptrauth_key_function_pointer);
#endif
    Dl_info info = {0};
    return dladdr(pointer, &info) && info.dli_fbase == (const void *)B9Hello();
}

static inline NSInteger B9MangoOrientation(void) {
    Class scene = objc_getClass("DecoratedAppSceneView");
    SEL getter = sel_registerName("mango_currentInterfaceOrientation");
    Method m = scene ? class_getClassMethod(scene, getter) : NULL;
    if (!B9ClassIsHello(scene) || !m || strcmp(method_getTypeEncoding(m), "q16@0:8"))
        return UIInterfaceOrientationUnknown;
    return ((NSInteger (*)(id, SEL))objc_msgSend)((id)scene, getter);
}

static inline NSInteger B9SystemOrientation(void) {
    if (!NSThread.isMainThread) return UIInterfaceOrientationUnknown;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSInteger system = UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
    return system;
}

static inline NSInteger B9Orientation(void) {
    NSInteger mango = B9MangoOrientation();
    if (!NSThread.isMainThread || (mango != UIInterfaceOrientationUnknown &&
                                  mango != UIInterfaceOrientationPortrait)) return mango;
    return MSB8ResolvedOrientation(mango, B9SystemOrientation());
}

static inline BOOL B9Disabled(const char *path) {
    if (!access(path, F_OK)) return YES;
    const char *mapped = jbroot(path);
    return mapped && !access(mapped, F_OK);
}

static inline BOOL B9LegacyOrientationLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *base = strrchr(name, '/'); base = base ? base + 1 : name;
        if (!strcmp(base, "MangoUpsideDownFix.dylib") || !strcmp(base, "MangoOrientationProbe.dylib"))
            return YES;
    }
    return NO;
}
