// The suite only decides what to load at process startup. Never dlclose a hook.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <roothide.h>
#import <string.h>
#import "Policy.h"
#import "SuitePreferences.h"
#import "Beta9Compatibility.h"

static BOOL HasImage(const char *filename) {
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *base = strrchr(name, '/');
        if (strcmp(base ? base + 1 : name, filename) == 0) return YES;
    }
    return NO;
}

static void LoadModule(NSString *name) {
    NSString *path = [NSString stringWithUTF8String:jbroot("/Library/MangoSuite/Modules")];
    path = [path stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"dylib"]];
    if (HasImage(path.lastPathComponent.UTF8String)) {
        NSLog(@"[MangoSuite] %@ already loaded; skipping duplicate", name);
        return;
    }
    dlerror();
    // Handles deliberately stay open for the entire process lifetime.
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *error = dlerror();
        NSLog(@"[MangoSuite] failed to load %@: %s", name, error ?: "unknown");
    } else {
        NSLog(@"[MangoSuite] loaded %@", name);
    }
}

__attribute__((constructor)) static void StartSuite(void) {
    @autoreleasepool {
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) {
            NSLog(@"[MangoSuite] unsupported OS; modules not loaded");
            return;
        }

        NSString *process = NSProcessInfo.processInfo.processName;
        BOOL springboard = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
        BOOL backboard = [process isEqualToString:@"backboardd"];
        if (!springboard && !backboard) return;

        // Read installed identities before hooks load. Adaptive must intercept
        // shader construction before MangoOSRendering initializes in backboardd.
        // This is a compatibility check, not an authorization or signature check.
        NSError *compatibilityError = nil;
        if (!MSValidateBeta9Files(&compatibilityError)) {
            NSLog(@"[MangoSuite] Beta9 modules not loaded: %@", compatibilityError.localizedDescription);
            return;
        }

        NSError *readError = nil;
        NSDictionary *snapshot = MSReadPreferences(&readError);
        if (!snapshot) {
            NSLog(@"[MangoSuite] preferences unavailable; modules not loaded: %@", readError);
            return;
        }

        MSState state = {
            .enabled = MSPreferenceFlag(snapshot, @"Enabled"),
            .idle = MSPreferenceFlag(snapshot, @"IdleEnabled"),
            .adaptive = MSPreferenceFlag(snapshot, @"AdaptiveEnabled"),
            .world = MSPreferenceFlag(snapshot, @"WorldEnabled"),
            .split = MSPreferenceFlag(snapshot, @"SplitEnabled"),
            .idleEmergency = MSHasEmergencyMarker(@"IdleEnabled"),
            .worldEmergency = MSHasEmergencyMarker(@"WorldEnabled"),
            .splitEmergency = MSHasEmergencyMarker(@"SplitEnabled"),
        };
        // Fail closed if a package manager was bypassed and an old orientation
        // hook is still present. The deb declares the same conflicts.
        state.legacyOrientation = HasImage("MangoUpsideDownFix.dylib") ||
                                  HasImage("MangoOrientationProbe.dylib");
        BOOL optical = MSPreferenceFlag(snapshot,@"RimGeometryEnabled") || MSPreferenceFlag(snapshot,@"GlassAnimationEnabled") ||
                       MSPreferenceFlag(snapshot,@"ShortHaloEnabled") || MSPreferenceFlag(snapshot,@"EdgeColorEnabled");
        unsigned modules = MSModulesWithOptics(state, springboard ? MS_SPRINGBOARD : MS_BACKBOARD, optical);
        NSLog(@"[MangoSuite] version=1.2.0~beta9.2 process=%@ startup-mask=%u changes=require-userspace-restart", process, modules);
        if (state.legacyOrientation) NSLog(@"[MangoSuite] legacy orientation hook detected; orientation modules suppressed");

        // The renderer process must receive the shader hook during startup.
        // Within SpringBoard, establish orientation before the delayed idle scan.
        if (modules & MS_ADAPTIVE) LoadModule(@"MangoIslandAdaptiveColor");
        if (modules & MS_WORLD) LoadModule(@"MangoUpsideDownWorld");
        if (modules & MS_SPLIT) LoadModule(@"MangoSplitUpsideDownFix");
        if (modules & MS_IDLE) LoadModule(@"MangoIdleIsland");
    }
}
