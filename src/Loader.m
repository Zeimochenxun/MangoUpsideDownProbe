// The suite only decides what to load at process startup. Never dlclose a hook.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <roothide.h>
#import <string.h>
#import "Policy.h"

static NSString * const SuiteDomain = @"com.chenxun.mangosuite";

static BOOL ReadFlag(NSDictionary *snapshot, NSString *key) {
    id value = snapshot[key];
    // Missing preferences preserve the enabled state of the four original packages.
    // Invalid types fail closed instead of treating e.g. the string "false" as YES.
    return value == nil ? YES : ([value isKindOfClass:NSNumber.class] && [value boolValue]);
}

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

        // Read the mobile user's saved file directly: backboardd must see exactly
        // the same configuration as SpringBoard, independent of daemon CF domains.
        NSString *preferences = [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:
                                 [SuiteDomain stringByAppendingPathExtension:@"plist"]];
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:preferences];
        NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:preferences];
        if (exists && ![snapshot isKindOfClass:NSDictionary.class]) {
            NSLog(@"[MangoSuite] invalid preferences; modules not loaded");
            return;
        }

        MSState state = {
            .enabled = ReadFlag(snapshot, @"Enabled"),
            .idle = ReadFlag(snapshot, @"IdleEnabled"),
            .adaptive = ReadFlag(snapshot, @"AdaptiveEnabled"),
            .world = ReadFlag(snapshot, @"WorldEnabled"),
            .split = ReadFlag(snapshot, @"SplitEnabled"),
            .idleEmergency = [NSFileManager.defaultManager fileExistsAtPath:@"/var/mobile/Library/Logs/MangoIdleIsland/DISABLED"],
            .worldEmergency = [NSFileManager.defaultManager fileExistsAtPath:@"/var/mobile/Library/Preferences/MangoUpsideDownWorld.disabled"],
            .splitEmergency = [NSFileManager.defaultManager fileExistsAtPath:@"/var/mobile/Library/Preferences/MangoSplitUpsideDownFix.disabled"],
        };
        // Fail closed if a package manager was bypassed and an old orientation
        // hook is still present. The deb declares the same conflicts.
        state.legacyOrientation = HasImage("MangoUpsideDownFix.dylib") ||
                                  HasImage("MangoOrientationProbe.dylib");
        unsigned modules = MSModulesForProcess(state, springboard ? MS_SPRINGBOARD : MS_BACKBOARD);
        NSLog(@"[MangoSuite] version=1.0.0~alpha1 process=%@ startup-mask=%u changes=require-userspace-restart", process, modules);
        if (state.legacyOrientation) NSLog(@"[MangoSuite] legacy orientation hook detected; orientation modules suppressed");

        // The renderer process must receive the shader hook during startup.
        // Within SpringBoard, establish orientation before the delayed idle scan.
        if (modules & MS_ADAPTIVE) LoadModule(@"MangoIslandAdaptiveColor");
        if (modules & MS_WORLD) LoadModule(@"MangoUpsideDownWorld");
        if (modules & MS_SPLIT) LoadModule(@"MangoSplitUpsideDownFix");
        if (modules & MS_IDLE) LoadModule(@"MangoIdleIsland");
    }
}
