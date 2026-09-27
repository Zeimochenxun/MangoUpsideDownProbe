#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <math.h>

// Beta7-1 MangoOSRendering uses CFPreferencesCopyMultiple for group-specific
// tint configuration and compiles an embedded Metal shader at runtime.
// This isolated tweak never touches the supplied Mango binaries on disk.
// Enabled on installation. It changes only the pair of Island tint values passed
// to Mango's preference loader, and the two known mix operations in the exact
// source of Mango's own shader. All other groups keep their original shader.

static NSString * const LogDir = @"/var/mobile/Library/Logs/MangoIslandAdaptiveColor";
static CFStringRef const MangoDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const LightKey = CFSTR("Island.LightTintColor");
static CFStringRef const DarkKey = CFSTR("Island.DarkTintColor");
static CFStringRef const AdaptationKey = CFSTR("MangoIslandAdaptiveColor.Adaptation");

// Near-white / near-black RGB values identify Island inside Mango's shader.
// The alpha is copied from the user's original RGBA preference so the existing
// Tint Strength control remains authoritative.

static CFDictionaryRef (*OriginalCopyMultiple)(CFArrayRef, CFStringRef, CFStringRef, CFStringRef);
static id<MTLLibrary> (*OriginalNewLibrary)(id, SEL, NSString *, MTLCompileOptions *, NSError **);
static BOOL ShaderSeen, ShaderPatched;

static NSString *AlphaSuffix(CFDictionaryRef values, CFStringRef key) {
    if (!values) return @"1A";
    CFTypeRef raw = CFDictionaryGetValue(values, key);
    if (!raw || CFGetTypeID(raw) != CFStringGetTypeID()) return @"1A";
    NSString *color = (__bridge NSString *)raw;
    if (color.length != 9 || ![color hasPrefix:@"#"]) return @"1A";
    NSString *hex = [color substringFromIndex:1];
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
    if ([hex rangeOfCharacterFromSet:invalid].location != NSNotFound) return @"1A";
    return [[hex substringFromIndex:6] uppercaseString];
}

static double AdaptationAmount(CFStringRef app, CFStringRef user, CFStringRef host) {
    const void *rawKeys[] = { AdaptationKey };
    CFArrayRef keys = CFArrayCreate(kCFAllocatorDefault, rawKeys, 1, &kCFTypeArrayCallBacks);
    if (!keys) return 1.0;
    CFDictionaryRef values = OriginalCopyMultiple(keys, app, user, host);
    CFRelease(keys);
    double amount = 1.0;
    if (values) {
        CFTypeRef raw = CFDictionaryGetValue(values, AdaptationKey);
        if (raw && CFGetTypeID(raw) == CFNumberGetTypeID()) {
            double candidate = 1.0;
            if (CFNumberGetValue((CFNumberRef)raw, kCFNumberDoubleType, &candidate) && isfinite(candidate)) {
                amount = fmin(1.0, fmax(0.0, candidate));
            }
        }
        CFRelease(values);
    }
    return amount;
}

static void LogLine(NSString *line) {
    const char *parent = "/var/mobile/Library/Logs";
    const char *directory = LogDir.fileSystemRepresentation;
    struct stat st;
    if (mkdir(parent, 0755) && lstat(parent, &st)) return;
    if (lstat(parent, &st) || !S_ISDIR(st.st_mode)) return;
    if (mkdir(directory, 0700) && lstat(directory, &st)) return;
    if (lstat(directory, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid()) return;
    NSString *path = [LogDir stringByAppendingPathComponent:@"Status.log"];
    int fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW, 0600);
    if (fd < 0) return;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_nlink != 1) { close(fd); return; }
    if (st.st_size > 65536) (void)ftruncate(fd, 0);
    NSData *data = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, line] dataUsingEncoding:NSUTF8StringEncoding];
    (void)write(fd, data.bytes, data.length);
    close(fd);
}

static CFDictionaryRef CopyMultiple(CFArrayRef keys, CFStringRef app, CFStringRef user, CFStringRef host) {
    CFDictionaryRef original = OriginalCopyMultiple(keys, app, user, host);
    if (!app || !CFEqual(app, MangoDomain)) return original;
    BOOL light = !keys || CFArrayContainsValue(keys, CFRangeMake(0, CFArrayGetCount(keys)), LightKey);
    BOOL dark = !keys || CFArrayContainsValue(keys, CFRangeMake(0, CFArrayGetCount(keys)), DarkKey);
    if (!light && !dark) return original;
    CFMutableDictionaryRef edited = original ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, original)
                                             : CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!edited) return original;
    unsigned adaptationLevel = (unsigned)lround(AdaptationAmount(app, user, host) * 14.0);
    if (light) {
        // Red 0xF0..0xFE carries 15 adaptation levels while the other two
        // channels keep this a safe near-white fallback if shader patching fails.
        NSString *marker = [NSString stringWithFormat:@"#%02XFEFD%@", 0xF0 + adaptationLevel, AlphaSuffix(original, LightKey)];
        CFDictionarySetValue(edited, LightKey, (__bridge CFStringRef)marker);
    }
    if (dark) {
        // Red 0x01..0x0F carries the same value in the near-black marker.
        NSString *marker = [NSString stringWithFormat:@"#%02X0102%@", 0x01 + adaptationLevel, AlphaSuffix(original, DarkKey)];
        CFDictionarySetValue(edited, DarkKey, (__bridge CFStringRef)marker);
    }
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
 @"    // UIColor may deliver uniforms unchanged, alpha-premultiplied, linear,\n"
 @"    // or premultiplied-linear. Compare all four normalizations so the\n"
 @"    // Island marker survives that transport while ordinary black/white\n"
 @"    // tints remain outside the deliberately offset G/B signature.\n"
 @"    float safeAlpha = max(tint.a, 0.001);\n"
 @"    float3 raw = tint.rgb;\n"
 @"    float3 divided = clamp(tint.rgb / safeAlpha, 0.0, 1.0);\n"
 @"    float3 rawGamma = float3(gammaEncode(raw.r), gammaEncode(raw.g), gammaEncode(raw.b));\n"
 @"    float3 dividedGamma = float3(gammaEncode(divided.r), gammaEncode(divided.g), gammaEncode(divided.b));\n"
 @"    float3 lightTarget = float3(0.0, 254.0 / 255.0, 253.0 / 255.0);\n"
 @"    float3 darkTarget = float3(0.0, 1.0 / 255.0, 2.0 / 255.0);\n"
 @"    float3 lightValue = raw;\n"
 @"    float3 darkValue = raw;\n"
 @"    float lightDistance = distance(raw.gb, lightTarget.gb);\n"
 @"    float darkDistance = distance(raw.gb, darkTarget.gb);\n"
 @"    float d = distance(divided.gb, lightTarget.gb);\n"
 @"    if (d < lightDistance) { lightDistance = d; lightValue = divided; }\n"
 @"    d = distance(divided.gb, darkTarget.gb);\n"
 @"    if (d < darkDistance) { darkDistance = d; darkValue = divided; }\n"
 @"    d = distance(rawGamma.gb, lightTarget.gb);\n"
 @"    if (d < lightDistance) { lightDistance = d; lightValue = rawGamma; }\n"
 @"    d = distance(rawGamma.gb, darkTarget.gb);\n"
 @"    if (d < darkDistance) { darkDistance = d; darkValue = rawGamma; }\n"
 @"    d = distance(dividedGamma.gb, lightTarget.gb);\n"
 @"    if (d < lightDistance) { lightDistance = d; lightValue = dividedGamma; }\n"
 @"    d = distance(dividedGamma.gb, darkTarget.gb);\n"
 @"    if (d < darkDistance) { darkDistance = d; darkValue = dividedGamma; }\n"
 @"    float lightRedByte = lightValue.r * 255.0;\n"
 @"    float darkRedByte = darkValue.r * 255.0;\n"
 @"    bool markerLight = lightDistance < 0.006 && lightRedByte >= 239.5 && lightRedByte <= 254.5;\n"
 @"    bool markerDark = darkDistance < 0.006 && darkRedByte >= 0.5 && darkRedByte <= 15.5;\n"
 @"    if (markerLight || markerDark) {\n"
 @"        float adaptation = markerLight ? clamp((lightRedByte - 240.0) / 14.0, 0.0, 1.0)\n"
 @"                                       : clamp((darkRedByte - 1.0) / 14.0, 0.0, 1.0);\n"
 @"        float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));\n"
 @"        // A broad response avoids a visible threshold around middle gray.\n"
 @"        float bright = smoothstep(0.10, 0.85, luminance);\n"
 @"        // Lift dark backdrops slightly and tint bright backdrops near-black.\n"
 @"        float adaptiveTarget = mix(0.18, 0.025, bright);\n"
 @"        float target = mix(0.10, adaptiveTarget, adaptation);\n"
 @"        // Map the full user slider to a glass-safe 0..42 percent mix.\n"
 @"        float userStrength = smoothstep(0.0, 1.0, clamp(tint.a, 0.0, 1.0));\n"
 @"        float strength = 0.42 * userStrength;\n"
 @"        return mix(background, float3(target), strength);\n"
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
    if (![source isKindOfClass:NSString.class] ||
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
        LogLine(@"[SHADER] Island adaptive mix compiled marker-decoder=raw+unpremultiplied+linear");
        return result;
    }
    LogLine([NSString stringWithFormat:@"[SHADER] modified source failed (%@); retrying original", attemptError.localizedDescription ?: @"unknown"]);
    return OriginalNewLibrary(self, cmd, source, options, error);
}

__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        // The live Island glass, Mango preference reader and runtime-compiled
        // Metal shader all live in SpringBoard on the target build.
        NSString *process = NSProcessInfo.processInfo.processName;
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![process isEqualToString:@"SpringBoard"] && ![bundle isEqualToString:@"com.apple.springboard"]) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.7 robust-marker process=%@ bundle=%@", process ?: @"(nil)", bundle ?: @"(nil)"]);

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
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.7 MetalClass=%@ shaderSeen=%d patched=%d",
                 NSStringFromClass(cls), ShaderSeen, ShaderPatched]);
    }
}
