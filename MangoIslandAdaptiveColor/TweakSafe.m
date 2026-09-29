#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>
#import <float.h>
#import <stdint.h>

// MangoIslandAdaptiveColor 0.1.3
//
// Safety goal: only Island tint markers may enter the adaptive renderer.
// The previous 0.1.2.2 marker accepted a very broad RGB/alpha range, so an
// unrelated Mango glass with a coincidentally similar tint could be mistaken
// for Island. 0.1.3 adds a packed-config checksum plus semantic validation.
//
// Visual goal: on very bright backgrounds, preserve backdrop chroma/detail
// instead of mixing toward a flat gray film. The Island marker also enables
// bright-background-only dispersion gain and a subtle dark Fresnel rim. Other
// Mango glass keeps the original shader path byte-for-byte.

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

// Stable quantization tables. Defaults are deliberately more transparent on
// bright backgrounds than 0.1.2/0.1.2.2.
static const double MasterValues[8]        = {0.00, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 1.00};
static const double LumaStartValues[8]     = {0.00, 0.04, 0.08, 0.12, 0.18, 0.24, 0.32, 0.42};
static const double LumaEndValues[8]       = {0.18, 0.26, 0.34, 0.42, 0.52, 0.64, 0.78, 0.92};
static const double DarkTargetValues[8]    = {0.20, 0.35, 0.50, 0.65, 0.80, 0.88, 0.94, 1.00};
static const double BrightTargetValues[8]  = {0.00, 0.025, 0.05, 0.08, 0.12, 0.18, 0.26, 0.36};
static const double DarkOpacityValues[8]   = {0.00, 0.08, 0.16, 0.24, 0.34, 0.46, 0.62, 0.80};
static const double BrightOpacityValues[8] = {0.00, 0.10, 0.20, 0.30, 0.42, 0.56, 0.70, 0.85};

static const double DefaultMaster = 0.90;
static const double DefaultLumaStart = 0.08;
static const double DefaultLumaEnd = 0.52;
static const double DefaultDarkTarget = 0.80;
static const double DefaultBrightTarget = 0.08;
static const double DefaultDarkOpacity = 0.16;
static const double DefaultBrightOpacity = 0.20;

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

static uint32_t DefaultPackedConfiguration(void) {
    // 0.90, 0.08, 0.52, 0.80, 0.08, 0.16, 0.20
    return (uint32_t)(6u | (2u << 3) | (4u << 6) | (4u << 9) |
                      (3u << 12) | (2u << 15) | (2u << 18));
}

static uint32_t PackedConfiguration(CFStringRef app, CFStringRef user, CFStringRef host) {
    const void *rawKeys[] = {
        AdaptationKey, LumaStartKey, LumaEndKey, DarkTargetKey,
        BrightTargetKey, DarkOpacityKey, BrightOpacityKey
    };
    CFArrayRef query = CFArrayCreate(kCFAllocatorDefault, rawKeys, 7, &kCFTypeArrayCallBacks);
    if (!query) return DefaultPackedConfiguration();
    CFDictionaryRef values = OriginalCopyMultiple(query, app, user, host);
    CFRelease(query);

    unsigned master = NearestIndex(NumberFromDictionary(values, AdaptationKey, DefaultMaster), MasterValues);
    unsigned lumaStart = NearestIndex(NumberFromDictionary(values, LumaStartKey, DefaultLumaStart), LumaStartValues);
    unsigned lumaEnd = NearestIndex(NumberFromDictionary(values, LumaEndKey, DefaultLumaEnd), LumaEndValues);
    unsigned darkTarget = NearestIndex(NumberFromDictionary(values, DarkTargetKey, DefaultDarkTarget), DarkTargetValues);
    unsigned brightTarget = NearestIndex(NumberFromDictionary(values, BrightTargetKey, DefaultBrightTarget), BrightTargetValues);
    unsigned darkOpacity = NearestIndex(NumberFromDictionary(values, DarkOpacityKey, DefaultDarkOpacity), DarkOpacityValues);
    unsigned brightOpacity = NearestIndex(NumberFromDictionary(values, BrightOpacityKey, DefaultBrightOpacity), BrightOpacityValues);
    if (values) CFRelease(values);

    // Encode only semantically valid configurations. This is also part of the
    // marker collision defense used by the shader.
    while (lumaEnd < 7 && LumaEndValues[lumaEnd] <= LumaStartValues[lumaStart] + 0.01) lumaEnd++;
    while (brightTarget > 0 && BrightTargetValues[brightTarget] > DarkTargetValues[darkTarget]) brightTarget--;

    return (uint32_t)(master |
           (lumaStart << 3) |
           (lumaEnd << 6) |
           (darkTarget << 9) |
           (brightTarget << 12) |
           (darkOpacity << 15) |
           (brightOpacity << 18));
}

static unsigned MarkerAlphaForPacked(uint32_t packed) {
    // 24-way checksum in a low-alpha range (8..31). The old exact 0.1.2
    // packed default still hashes to 0x1A, but arbitrary Mango tints almost
    // never satisfy this relationship accidentally.
    uint32_t folded = packed ^ (packed >> 5) ^ (packed >> 10) ^ (packed >> 15);
    return 8u + ((folded + 21u) % 24u);
}

static NSString *LightMarkerForPacked(uint32_t packed) {
    uint32_t encoded = packed ^ 0x0E67A9u;
    unsigned r = 0x80u | (encoded & 0x7Fu);
    unsigned g = 0x80u | ((encoded >> 7) & 0x7Fu);
    unsigned b = 0x80u | ((encoded >> 14) & 0x7Fu);
    unsigned a = MarkerAlphaForPacked(packed);
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", r, g, b, a];
}

static NSString *DarkMarkerForPacked(uint32_t packed) {
    uint32_t encoded = packed ^ 0x119856u;
    unsigned r = encoded & 0x7Fu;
    unsigned g = (encoded >> 7) & 0x7Fu;
    unsigned b = (encoded >> 14) & 0x7Fu;
    unsigned a = MarkerAlphaForPacked(packed);
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", r, g, b, a];
}

static CFDictionaryRef CopyMultiple(CFArrayRef keys, CFStringRef app, CFStringRef user, CFStringRef host) {
    CFDictionaryRef original = OriginalCopyMultiple(keys, app, user, host);
    if (!app || !CFEqual(app, MangoDomain)) return original;

    // CPU-side scope remains exact: only Island Light/Dark tint keys are ever
    // replaced. Other group keys are returned untouched.
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
    if (light) CFDictionarySetValue(edited, LightKey, (__bridge CFStringRef)lightMarker);
    if (dark) CFDictionarySetValue(edited, DarkKey, (__bridge CFStringRef)darkMarker);
    if (original) CFRelease(original);

    LogLine([NSString stringWithFormat:@"[ISLAND-ONLY] packed=0x%06X checksumAlpha=%u light=%@ dark=%@",
             packed, MarkerAlphaForPacked(packed), lightMarker, darkMarker]);
    return edited;
}

static NSString *const FlatOld = @"flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const CurvedOld = @"float3 outRGB = mix(bg.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const DispersionOld = @"float dispersion = clamp(u.dispersionStrength, 0.0, 20.0);";
static NSString *const GlareApplyOld = @"outRGB = 1.0 - (1.0 - outRGB) * (1.0 - glare);";
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
 @"uint miaMarkerAlpha(uint packed) {\n"
 @"    uint folded = packed ^ (packed >> 5) ^ (packed >> 10) ^ (packed >> 15);\n"
 @"    return 8u + ((folded + 21u) % 24u);\n"
 @"}\n"
 @"uint miaPackedMarker(float4 tint) {\n"
 @"    uint rByte = uint(round(clamp(tint.r, 0.0, 1.0) * 255.0));\n"
 @"    uint gByte = uint(round(clamp(tint.g, 0.0, 1.0) * 255.0));\n"
 @"    uint bByte = uint(round(clamp(tint.b, 0.0, 1.0) * 255.0));\n"
 @"    uint aByte = uint(round(clamp(tint.a, 0.0, 1.0) * 255.0));\n"
 @"    bool markerLight = rByte >= 128u && gByte >= 128u && bByte >= 128u;\n"
 @"    bool markerDark = rByte < 128u && gByte < 128u && bByte < 128u;\n"
 @"    if (!markerLight && !markerDark) return 0xFFFFFFFFu;\n"
 @"    uint encoded = (rByte & 0x7Fu) | ((gByte & 0x7Fu) << 7) | ((bByte & 0x7Fu) << 14);\n"
 @"    uint packed = encoded ^ (markerLight ? 0x0E67A9u : 0x119856u);\n"
 @"    if (aByte != miaMarkerAlpha(packed)) return 0xFFFFFFFFu;\n"
 @"    uint startCode = (packed >> 3) & 7u;\n"
 @"    uint endCode = (packed >> 6) & 7u;\n"
 @"    uint darkTargetCode = (packed >> 9) & 7u;\n"
 @"    uint brightTargetCode = (packed >> 12) & 7u;\n"
 @"    if (miaLumaEnd(endCode) <= miaLumaStart(startCode) + 0.009) return 0xFFFFFFFFu;\n"
 @"    if (miaBrightTarget(brightTargetCode) > miaDarkTarget(darkTargetCode)) return 0xFFFFFFFFu;\n"
 @"    return packed;\n"
 @"}\n"
 @"bool miaIsIslandMarker(float4 tint) { return miaPackedMarker(tint) != 0xFFFFFFFFu; }\n"
 @"float miaHighlightAmount(float3 background, float4 tint) {\n"
 @"    if (!miaIsIslandMarker(tint)) return 0.0;\n"
 @"    float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));\n"
 @"    return smoothstep(0.68, 0.92, luminance);\n"
 @"}\n"
 @"float3 mangoIslandAdaptiveColor(float3 background, float4 tint)\n"
 @"{\n"
 @"    uint packed = miaPackedMarker(tint);\n"
 @"    if (packed == 0xFFFFFFFFu) return mix(background, tint.rgb, tint.a);\n"
 @"    uint masterCode = packed & 7u;\n"
 @"    uint startCode = (packed >> 3) & 7u;\n"
 @"    uint endCode = (packed >> 6) & 7u;\n"
 @"    uint darkTargetCode = (packed >> 9) & 7u;\n"
 @"    uint brightTargetCode = (packed >> 12) & 7u;\n"
 @"    uint darkOpacityCode = (packed >> 15) & 7u;\n"
 @"    uint brightOpacityCode = (packed >> 18) & 7u;\n"
 @"    float start = miaLumaStart(startCode);\n"
 @"    float end = miaLumaEnd(endCode);\n"
 @"    float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));\n"
 @"    float bright = smoothstep(start, end, luminance);\n"
 @"    float target = mix(miaDarkTarget(darkTargetCode), miaBrightTarget(brightTargetCode), bright);\n"
 @"    float opacity = mix(miaDarkOpacity(darkOpacityCode), miaBrightOpacity(brightOpacityCode), bright);\n"
 @"    float master = miaMaster(masterCode);\n"
 @"    float3 normalAdaptive = mix(background, float3(target), clamp(opacity * master, 0.0, 1.0));\n"
 @"    // Highlight Glass: preserve RGB relationships and backdrop detail.\n"
 @"    float highlight = smoothstep(0.68, 0.92, luminance);\n"
 @"    float highlightOpacity = opacity * mix(1.0, 0.72, highlight) * master;\n"
 @"    float desiredLuma = mix(luminance, target, clamp(highlightOpacity, 0.0, 1.0));\n"
 @"    float scale = desiredLuma / max(luminance, 0.001);\n"
 @"    float3 chromaPreserved = clamp(background * scale, 0.0, 1.0);\n"
 @"    float3 highlightGlass = mix(background, chromaPreserved, 0.82);\n"
 @"    return mix(normalAdaptive, highlightGlass, highlight);\n"
 @"}\n\n";

static NSUInteger Occurrences(NSString *haystack, NSString *needle) {
    NSUInteger count = 0, pos = 0;
    while (pos < haystack.length) {
        NSRange found = [haystack rangeOfString:needle options:0 range:NSMakeRange(pos, haystack.length - pos)];
        if (found.location == NSNotFound) break;
        count++;
        pos = NSMaxRange(found);
    }
    return count;
}

static id<MTLLibrary> NewLibrary(id self, SEL cmd, NSString *source, MTLCompileOptions *options, NSError **error) {
    if (![source isKindOfClass:NSString.class] ||
        [source rangeOfString:@"mangoGlassFragment"].location == NSNotFound) {
        return OriginalNewLibrary(self, cmd, source, options, error);
    }

    ShaderSeen = YES;
    if (Occurrences(source, PixelEntry) != 1 ||
        Occurrences(source, FlatOld) != 1 ||
        Occurrences(source, CurvedOld) != 1 ||
        Occurrences(source, DispersionOld) != 1 ||
        Occurrences(source, GlareApplyOld) != 1 ||
        [source rangeOfString:@"struct Uniforms"].location == NSNotFound) {
        LogLine(@"[SHADER] Mango source differs; original used");
        return OriginalNewLibrary(self, cmd, source, options, error);
    }

    NSString *edited = [source stringByReplacingOccurrencesOfString:FlatOld
                                                           withString:@"flat.rgb = mangoIslandAdaptiveColor(flat.rgb, u.tintColor);"];
    edited = [edited stringByReplacingOccurrencesOfString:CurvedOld
                                               withString:@"float3 outRGB = mangoIslandAdaptiveColor(bg.rgb, u.tintColor);\n    float miaHighlightEdge = miaHighlightAmount(bg.rgb, u.tintColor);\n    if (miaHighlightEdge > 0.001) {\n        float miaEdgeFresnel = fresnelAtRatio(bezelRatio, u.refractiveIndex) * edgeOpacity;\n        float miaDarkRim = clamp(miaEdgeFresnel * 0.34 * miaHighlightEdge, 0.0, 0.14);\n        outRGB *= (1.0 - miaDarkRim);\n    }"];
    edited = [edited stringByReplacingOccurrencesOfString:DispersionOld
                                               withString:@"float dispersion = clamp(u.dispersionStrength, 0.0, 20.0);\n    if (miaIsIslandMarker(u.tintColor)) {\n        float3 miaCenter = src.sample(s, captureUV).rgb;\n        float miaBrightEdge = miaHighlightAmount(miaCenter, u.tintColor);\n        dispersion = clamp(dispersion * mix(1.0, 1.60, miaBrightEdge), 0.0, 20.0);\n    }"];
    edited = [edited stringByReplacingOccurrencesOfString:GlareApplyOld
                                               withString:@"if (miaHighlightEdge > 0.001) glare *= mix(1.0, 0.55, miaHighlightEdge);\n    outRGB = 1.0 - (1.0 - outRGB) * (1.0 - glare);"];
    edited = [edited stringByReplacingOccurrencesOfString:PixelEntry
                                               withString:[AdaptiveFunction stringByAppendingString:PixelEntry]];

    NSError *attemptError = nil;
    id<MTLLibrary> result = OriginalNewLibrary(self, cmd, edited, options, &attemptError);
    if (result) {
        ShaderPatched = YES;
        LogLine(@"[SHADER] 0.1.3 Island-only adaptive contrast glass compiled; non-marker glass retains original mix");
        return result;
    }

    LogLine([NSString stringWithFormat:@"[SHADER] modified source failed (%@); retrying original",
             attemptError.localizedDescription ?: @"unknown"]);
    return OriginalNewLibrary(self, cmd, source, options, error);
}

__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![process isEqualToString:@"backboardd"] && ![bundle isEqualToString:@"com.apple.backboardd"]) return;

        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;

        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.3 island-only highlight-glass process=%@ bundle=%@",
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
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.3 MetalClass=%@ shaderSeen=%d patched=%d",
                 NSStringFromClass(cls), ShaderSeen, ShaderPatched]);
    }
}
