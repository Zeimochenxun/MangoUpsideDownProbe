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
#import <float.h>
#import <stdint.h>

// 0.1.2 renderer baseline, now parameterized. The default configuration is
// mathematically identical to 0.1.2: smoothstep(0.08, 0.42), target 0.80->0.025,
// opacity 0.16->0.42 and master strength 1.0.
//
// Runtime parameters are transported through the Island tint marker so changing
// Settings only needs Mango's normal parameter reload; the Metal library itself
// is not recompiled for every slider move. Seven 3-bit values are packed into
// the RGB marker. The default packed value is XOR-mapped back to the exact
// original 0.1.2 markers #FEFEFD1A and #0101021A.

static NSString * const LogDir = @"/var/mobile/Library/Logs/MangoIslandAdaptiveColor";
static CFStringRef const MangoDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const LightKey = CFSTR("Island.LightTintColor");
static CFStringRef const DarkKey = CFSTR("Island.DarkTintColor");
static CFStringRef const AdaptationKey = CFSTR("MangoIslandAdaptiveColor.Adaptation");
static CFStringRef const LumaStartKey = CFSTR("MangoIslandAdaptiveColor.LumaStart");
static CFStringRef const LumaEndKey = CFSTR("MangoIslandAdaptiveColor.LumaEnd");
static CFStringRef const DarkTargetKey = CFSTR("MangoIslandAdaptiveColor.DarkTarget");
static CFStringRef const BrightTargetKey = CFSTR("MangoIslandAdaptiveColor.BrightTarget");
static CFStringRef const DarkOpacityKey = CFSTR("MangoIslandAdaptiveColor.DarkOpacity");
static CFStringRef const BrightOpacityKey = CFSTR("MangoIslandAdaptiveColor.BrightOpacity");

static const double MasterValues[8]        = {0.00, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 1.00};
static const double LumaStartValues[8]     = {0.00, 0.04, 0.08, 0.12, 0.18, 0.24, 0.32, 0.42};
static const double LumaEndValues[8]       = {0.18, 0.26, 0.34, 0.42, 0.52, 0.64, 0.78, 0.92};
static const double DarkTargetValues[8]    = {0.20, 0.35, 0.50, 0.65, 0.80, 0.88, 0.94, 1.00};
static const double BrightTargetValues[8]  = {0.00, 0.025, 0.05, 0.08, 0.12, 0.18, 0.26, 0.36};
static const double DarkOpacityValues[8]   = {0.00, 0.08, 0.16, 0.24, 0.34, 0.46, 0.62, 0.80};
static const double BrightOpacityValues[8] = {0.00, 0.10, 0.20, 0.30, 0.42, 0.56, 0.70, 0.85};

static CFDictionaryRef (*OriginalCopyMultiple)(CFArrayRef, CFStringRef, CFStringRef, CFStringRef);
static id<MTLLibrary> (*OriginalNewLibrary)(id, SEL, NSString *, MTLCompileOptions *, NSError **);
static BOOL ShaderSeen, ShaderPatched;

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

static double NumberFromDictionary(CFDictionaryRef values, CFStringRef key, double fallback) {
    if (!values) return fallback;
    CFTypeRef raw = CFDictionaryGetValue(values, key);
    if (!raw || CFGetTypeID(raw) != CFNumberGetTypeID()) return fallback;
    double candidate = fallback;
    if (!CFNumberGetValue((CFNumberRef)raw, kCFNumberDoubleType, &candidate) || !isfinite(candidate)) return fallback;
    return candidate;
}

static unsigned NearestIndex(double value, const double *table) {
    unsigned best = 0;
    double distance = DBL_MAX;
    for (unsigned i = 0; i < 8; i++) {
        double d = fabs(value - table[i]);
        if (d < distance) { distance = d; best = i; }
    }
    return best;
}

static uint32_t PackedConfiguration(CFStringRef app, CFStringRef user, CFStringRef host) {
    const void *rawKeys[] = {
        AdaptationKey, LumaStartKey, LumaEndKey, DarkTargetKey,
        BrightTargetKey, DarkOpacityKey, BrightOpacityKey
    };
    CFArrayRef query = CFArrayCreate(kCFAllocatorDefault, rawKeys, 7, &kCFTypeArrayCallBacks);
    if (!query) return 0x1118D7u; // exact 0.1.2 defaults
    CFDictionaryRef values = OriginalCopyMultiple(query, app, user, host);
    CFRelease(query);

    unsigned master = NearestIndex(NumberFromDictionary(values, AdaptationKey, 1.0), MasterValues);
    unsigned lumaStart = NearestIndex(NumberFromDictionary(values, LumaStartKey, 0.08), LumaStartValues);
    unsigned lumaEnd = NearestIndex(NumberFromDictionary(values, LumaEndKey, 0.42), LumaEndValues);
    unsigned darkTarget = NearestIndex(NumberFromDictionary(values, DarkTargetKey, 0.80), DarkTargetValues);
    unsigned brightTarget = NearestIndex(NumberFromDictionary(values, BrightTargetKey, 0.025), BrightTargetValues);
    unsigned darkOpacity = NearestIndex(NumberFromDictionary(values, DarkOpacityKey, 0.16), DarkOpacityValues);
    unsigned brightOpacity = NearestIndex(NumberFromDictionary(values, BrightOpacityKey, 0.42), BrightOpacityValues);
    if (values) CFRelease(values);

    return (uint32_t)(master |
           (lumaStart << 3) |
           (lumaEnd << 6) |
           (darkTarget << 9) |
           (brightTarget << 12) |
           (darkOpacity << 15) |
           (brightOpacity << 18));
}

static NSString *LightMarkerForPacked(uint32_t packed) {
    uint32_t encoded = packed ^ 0x0E67A9u;
    unsigned r = 0x80u | (encoded & 0x7Fu);
    unsigned g = 0x80u | ((encoded >> 7) & 0x7Fu);
    unsigned b = 0x80u | ((encoded >> 14) & 0x7Fu);
    return [NSString stringWithFormat:@"#%02X%02X%02X1A", r, g, b];
}

static NSString *DarkMarkerForPacked(uint32_t packed) {
    uint32_t encoded = packed ^ 0x119856u;
    unsigned r = encoded & 0x7Fu;
    unsigned g = (encoded >> 7) & 0x7Fu;
    unsigned b = (encoded >> 14) & 0x7Fu;
    return [NSString stringWithFormat:@"#%02X%02X%02X1A", r, g, b];
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

    uint32_t packed = PackedConfiguration(app, user, host);
    NSString *lightMarker = LightMarkerForPacked(packed);
    NSString *darkMarker = DarkMarkerForPacked(packed);
    if (light) CFDictionarySetValue(edited, LightKey, (CFStringRef)lightMarker);
    if (dark) CFDictionarySetValue(edited, DarkKey, (CFStringRef)darkMarker);
    if (original) CFRelease(original);

    LogLine([NSString stringWithFormat:@"[ISLAND] configurable marker packed=0x%06X light=%@ dark=%@",
             packed, lightMarker, darkMarker]);
    return edited;
}

static NSString *const FlatOld = @"flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const CurvedOld = @"float3 outRGB = mix(bg.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const PixelEntry = @"float4 mangoGlassPixel(";
static NSString *const AdaptiveFunction =
@"float miaMaster(uint c) {\n"
 @"    if (c == 0u) return 0.00; if (c == 1u) return 0.15; if (c == 2u) return 0.30; if (c == 3u) return 0.45;\n"
 @"    if (c == 4u) return 0.60; if (c == 5u) return 0.75; if (c == 6u) return 0.90; return 1.00;\n"
 @"}\n"
 @"float miaLumaStart(uint c) {\n"
 @"    if (c == 0u) return 0.00; if (c == 1u) return 0.04; if (c == 2u) return 0.08; if (c == 3u) return 0.12;\n"
 @"    if (c == 4u) return 0.18; if (c == 5u) return 0.24; if (c == 6u) return 0.32; return 0.42;\n"
 @"}\n"
 @"float miaLumaEnd(uint c) {\n"
 @"    if (c == 0u) return 0.18; if (c == 1u) return 0.26; if (c == 2u) return 0.34; if (c == 3u) return 0.42;\n"
 @"    if (c == 4u) return 0.52; if (c == 5u) return 0.64; if (c == 6u) return 0.78; return 0.92;\n"
 @"}\n"
 @"float miaDarkTarget(uint c) {\n"
 @"    if (c == 0u) return 0.20; if (c == 1u) return 0.35; if (c == 2u) return 0.50; if (c == 3u) return 0.65;\n"
 @"    if (c == 4u) return 0.80; if (c == 5u) return 0.88; if (c == 6u) return 0.94; return 1.00;\n"
 @"}\n"
 @"float miaBrightTarget(uint c) {\n"
 @"    if (c == 0u) return 0.00; if (c == 1u) return 0.025; if (c == 2u) return 0.05; if (c == 3u) return 0.08;\n"
 @"    if (c == 4u) return 0.12; if (c == 5u) return 0.18; if (c == 6u) return 0.26; return 0.36;\n"
 @"}\n"
 @"float miaDarkOpacity(uint c) {\n"
 @"    if (c == 0u) return 0.00; if (c == 1u) return 0.08; if (c == 2u) return 0.16; if (c == 3u) return 0.24;\n"
 @"    if (c == 4u) return 0.34; if (c == 5u) return 0.46; if (c == 6u) return 0.62; return 0.80;\n"
 @"}\n"
 @"float miaBrightOpacity(uint c) {\n"
 @"    if (c == 0u) return 0.00; if (c == 1u) return 0.10; if (c == 2u) return 0.20; if (c == 3u) return 0.30;\n"
 @"    if (c == 4u) return 0.42; if (c == 5u) return 0.56; if (c == 6u) return 0.70; return 0.85;\n"
 @"}\n"
 @"float3 mangoIslandAdaptiveColor(float3 background, float4 tint)\n"
 @"{\n"
 @"    uint rByte = uint(round(clamp(tint.r, 0.0, 1.0) * 255.0));\n"
 @"    uint gByte = uint(round(clamp(tint.g, 0.0, 1.0) * 255.0));\n"
 @"    uint bByte = uint(round(clamp(tint.b, 0.0, 1.0) * 255.0));\n"
 @"    uint aByte = uint(round(clamp(tint.a, 0.0, 1.0) * 255.0));\n"
 @"    bool markerLight = aByte == 26u && rByte >= 128u && gByte >= 128u && bByte >= 128u;\n"
 @"    bool markerDark = aByte == 26u && rByte < 128u && gByte < 128u && bByte < 128u;\n"
 @"    if (markerLight || markerDark) {\n"
 @"        uint encoded = (rByte & 0x7Fu) | ((gByte & 0x7Fu) << 7) | ((bByte & 0x7Fu) << 14);\n"
 @"        uint packed = encoded ^ (markerLight ? 0x0E67A9u : 0x119856u);\n"
 @"        uint masterCode = packed & 7u;\n"
 @"        uint startCode = (packed >> 3) & 7u;\n"
 @"        uint endCode = (packed >> 6) & 7u;\n"
 @"        uint darkTargetCode = (packed >> 9) & 7u;\n"
 @"        uint brightTargetCode = (packed >> 12) & 7u;\n"
 @"        uint darkOpacityCode = (packed >> 15) & 7u;\n"
 @"        uint brightOpacityCode = (packed >> 18) & 7u;\n"
 @"        float start = miaLumaStart(startCode);\n"
 @"        float end = max(miaLumaEnd(endCode), start + 0.01);\n"
 @"        float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));\n"
 @"        float bright = smoothstep(start, end, luminance);\n"
 @"        float target = mix(miaDarkTarget(darkTargetCode), miaBrightTarget(brightTargetCode), bright);\n"
 @"        float opacity = mix(miaDarkOpacity(darkOpacityCode), miaBrightOpacity(brightOpacityCode), bright);\n"
 @"        opacity = clamp(opacity * miaMaster(masterCode), 0.0, 1.0);\n"
 @"        return mix(background, float3(target), opacity);\n"
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
        LogLine(@"[SHADER] configurable 0.1.2 adaptive renderer compiled; other groups retain original mix");
        return result;
    }
    LogLine([NSString stringWithFormat:@"[SHADER] modified source failed (%@); retrying original", attemptError.localizedDescription ?: @"unknown"]);
    return OriginalNewLibrary(self, cmd, source, options, error);
}

__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![process isEqualToString:@"backboardd"] && ![bundle isEqualToString:@"com.apple.backboardd"]) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.2.2 configurable baseline=0.1.2 process=%@ bundle=%@",
                 process ?: @"(nil)", bundle ?: @"(nil)"]);

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

        MSHookMessageEx(cls, selector, (IMP)NewLibrary, (IMP *)&OriginalNewLibrary);
        MSHookFunction((void *)CFPreferencesCopyMultiple, (void *)CopyMultiple, (void **)&OriginalCopyMultiple);
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.2.2 MetalClass=%@ shaderSeen=%d patched=%d",
                 NSStringFromClass(cls), ShaderSeen, ShaderPatched]);
    }
}
