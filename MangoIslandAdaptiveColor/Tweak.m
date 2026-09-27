#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

// Beta7-1 MangoOSRendering uses CFPreferencesCopyMultiple for group-specific
// tint configuration and compiles an embedded Metal shader at runtime.
// This isolated tweak never touches the supplied Mango binaries on disk.
// Disabled by default. It changes only the pair of Island tint values passed
// to Mango's preference loader, and the two known mix operations in the exact
// source of Mango's own shader. All other groups keep their original shader.

static NSString * const EnabledPath = @"/var/mobile/Library/Preferences/com.chenxun.mangoislandadaptivecolor.enable";
static NSString * const LogPath = @"/var/mobile/Library/Logs/MangoIslandAdaptiveColor.log";
static CFStringRef const MangoDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const LightKey = CFSTR("Island.LightTintColor");
static CFStringRef const DarkKey = CFSTR("Island.DarkTintColor");

// On failure these are still near-black / near-white Mango tints. The alpha
// is a deliberately uncommon opt-in marker; the shader additionally requires
// the exact RGB sentinel to prevent tint changes to unrelated glass groups.
static CFStringRef const LightMarker = CFSTR("#FEFEFD5D");
static CFStringRef const DarkMarker = CFSTR("#0101025D");

static CFDictionaryRef (*OriginalCopyMultiple)(CFArrayRef, CFStringRef, CFStringRef, CFStringRef);
static id<MTLLibrary> (*OriginalNewLibrary)(id, SEL, NSString *, MTLCompileOptions *, NSError **);
static BOOL Enabled, ShaderSeen, ShaderPatched;

static void LogLine(NSString *line) {
    int fd = open(LogPath.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW, 0600);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_nlink != 1) { close(fd); return; }
    if (st.st_size > 65536) (void)ftruncate(fd, 0);
    NSData *data = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, line] dataUsingEncoding:NSUTF8StringEncoding];
    (void)write(fd, data.bytes, data.length);
    close(fd);
}

static CFDictionaryRef CopyMultiple(CFArrayRef keys, CFStringRef app, CFStringRef user, CFStringRef host) {
    CFDictionaryRef original = OriginalCopyMultiple(keys, app, user, host);
    if (!Enabled || !app || !CFEqual(app, MangoDomain)) return original;
    BOOL light = !keys || CFArrayContainsValue(keys, CFRangeMake(0, CFArrayGetCount(keys)), LightKey);
    BOOL dark = !keys || CFArrayContainsValue(keys, CFRangeMake(0, CFArrayGetCount(keys)), DarkKey);
    if (!light && !dark) return original;
    CFMutableDictionaryRef edited = original ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, original)
                                             : CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!edited) return original;
    if (light) CFDictionarySetValue(edited, LightKey, LightMarker);
    if (dark) CFDictionarySetValue(edited, DarkKey, DarkMarker);
    if (original) CFRelease(original);
    LogLine(@"[ISLAND] tint-marker supplied to Mango group configuration");
    return edited;
}

static NSString *const FlatOld = @"flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const CurvedOld = @"float3 outRGB = mix(bg.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const PixelEntry = @"float4 mangoGlassPixel(";
static NSString *const AdaptiveFunction =
@"float3 mangoIslandAdaptiveColor(float3 background, float4 tint)\n"
 @"{\n"
 @"    // 0x5D alpha plus either near-white or near-black RGB identifies Island.\n"
 @"    bool markerAlpha = abs(tint.a - (93.0 / 255.0)) < 0.0008;\n"
 @"    bool markerLight = abs(tint.r - (254.0 / 255.0)) < 0.0008 &&\n"
 @"                       abs(tint.g - (254.0 / 255.0)) < 0.0008 &&\n"
 @"                       abs(tint.b - (253.0 / 255.0)) < 0.0008;\n"
 @"    bool markerDark = abs(tint.r - (1.0 / 255.0)) < 0.0008 &&\n"
 @"                      abs(tint.g - (1.0 / 255.0)) < 0.0008 &&\n"
 @"                      abs(tint.b - (2.0 / 255.0)) < 0.0008;\n"
 @"    if (markerAlpha && (markerLight || markerDark)) {\n"
 @"        float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));\n"
 @"        float bright = smoothstep(0.18, 0.72, luminance);\n"
 @"        // Keep the body dark enough for Mango's own white active content.\n"
 @"        float3 target = mix(float3(0.92), float3(0.025), bright);\n"
 @"        float opacity = mix(0.16, 0.60, bright);\n"
 @"        return mix(background, target, opacity);\n"
 @"    }\n"
 @"    return mix(background, tint.rgb, tint.a);\n"
 @"}\n\n";

static NSUInteger Occurrences(NSString *haystack, NSString *needle) {
    NSUInteger count = 0, pos = 0;
    while (pos < haystack.length) {
        NSRange found = [haystack rangeOfString:needle options:0 range:NSMakeRange(pos, haystack.length - pos)];
        if (found.location == NSNotFound) break;
        count++; pos = NSMaxRange(found);
    }
    return count;
}

static id<MTLLibrary> NewLibrary(id self, SEL cmd, NSString *source, MTLCompileOptions *options, NSError **error) {
    if (!Enabled || ![source isKindOfClass:NSString.class] ||
        [source rangeOfString:@"mangoGlassFragment"].location == NSNotFound) {
        return OriginalNewLibrary(self, cmd, source, options, error);
    }
    ShaderSeen = YES;
    // Never perform an approximate rewrite when Mango updates the shader.
    if (Occurrences(source, PixelEntry) != 1 || Occurrences(source, FlatOld) != 1 ||
        Occurrences(source, CurvedOld) != 1 ||
        [source rangeOfString:@"struct Uniforms"].location == NSNotFound) {
        LogLine(@"[SHADER] Mango source differs; original used");
        return OriginalNewLibrary(self, cmd, source, options, error);
    }
    NSString *edited = [source stringByReplacingOccurrencesOfString:FlatOld
                                                           withString:@"flat.rgb = mangoIslandAdaptiveColor(flat.rgb, u.tintColor);"];
    edited = [edited stringByReplacingOccurrencesOfString:CurvedOld
                                               withString:@"float3 outRGB = mangoIslandAdaptiveColor(bg.rgb, u.tintColor);"];
    edited = [edited stringByReplacingOccurrencesOfString:PixelEntry
                                               withString:[AdaptiveFunction stringByAppendingString:PixelEntry]];
    NSError *attemptError = nil;
    id<MTLLibrary> result = OriginalNewLibrary(self, cmd, edited, options, &attemptError);
    if (result) {
        ShaderPatched = YES;
        LogLine(@"[SHADER] Island adaptive mix compiled; other groups retain original mix");
        return result;
    }
    LogLine([NSString stringWithFormat:@"[SHADER] modified source failed (%@); retrying original", attemptError.localizedDescription ?: @"unknown"]);
    return OriginalNewLibrary(self, cmd, source, options, error);
}

__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.backboardd"]) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
        Enabled = access(EnabledPath.fileSystemRepresentation, F_OK) == 0;
        if (!Enabled) { LogLine(@"[SESSION] 0.1.0 disabled; no hooks installed"); return; }

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        Class cls = device ? object_getClass(device) : Nil;
        SEL selector = @selector(newLibraryWithSource:options:error:);
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (!method || method_getNumberOfArguments(method) != 5) {
            LogLine(@"[SESSION] Metal method not verified; no hooks installed");
            return;
        }
        char ret[32] = {0}, arg[32] = {0};
        method_getReturnType(method, ret, sizeof(ret));
        method_getArgumentType(method, 2, arg, sizeof(arg));
        if (ret[0] != '@' || arg[0] != '@') {
            LogLine(@"[SESSION] Metal signature mismatch; no hooks installed");
            return;
        }

        // Install source hook before Mango's custom filter compiles its shader.
        MSHookMessageEx(cls, selector, (IMP)NewLibrary, (IMP *)&OriginalNewLibrary);
        // MangoOSRendering imports this exact CF function. We only alter its
        // Island keys in its own domain, without modifying stored preferences.
        MSHookFunction((void *)CFPreferencesCopyMultiple, (void *)CopyMultiple, (void **)&OriginalCopyMultiple);
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.0 enabled MetalClass=%@ shaderSeen=%d patched=%d",
                 NSStringFromClass(cls), ShaderSeen, ShaderPatched]);
    }
}
