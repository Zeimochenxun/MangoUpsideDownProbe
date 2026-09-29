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

// Exact 0.1.2 renderer baseline, with one deliberately isolated extension:
// a 0..1 adaptation scalar. At 1.0, the marker bytes and shader math are the
// original 0.1.2 values. The scalar only blends between the untouched sampled
// backdrop and 0.1.2's adaptive result; it does not alter the response curve.

static NSString * const LogDir = @"/var/mobile/Library/Logs/MangoIslandAdaptiveColor";
static CFStringRef const MangoDomain = CFSTR("com.go.mangoosprefs");
static CFStringRef const LightKey = CFSTR("Island.LightTintColor");
static CFStringRef const DarkKey = CFSTR("Island.DarkTintColor");
static CFStringRef const AdaptationKey = CFSTR("MangoIslandAdaptiveColor.Adaptation");

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

static double AdaptationAmount(CFStringRef app, CFStringRef user, CFStringRef host) {
    const void *rawKeys[] = { AdaptationKey };
    CFArrayRef query = CFArrayCreate(kCFAllocatorDefault, rawKeys, 1, &kCFTypeArrayCallBacks);
    if (!query) return 1.0;
    CFDictionaryRef values = OriginalCopyMultiple(query, app, user, host);
    CFRelease(query);

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

    // Encode 225 levels in the two near-white / near-black channels. Even at
    // the weakest setting, fallback colors remain safely near the original
    // sentinels if shader patching fails. At 100%, the bytes are EXACT 0.1.2:
    // Light #FEFEFD1A, Dark #0101021A.
    double amount = AdaptationAmount(app, user, host);
    unsigned level = (unsigned)lround(amount * 224.0);
    unsigned lightR = 0xF0 + level / 15;
    unsigned lightG = 0xF0 + level % 15;
    unsigned inverse = 224 - level;
    unsigned darkR = 0x01 + inverse / 15;
    unsigned darkG = 0x01 + inverse % 15;
    NSString *lightMarker = [NSString stringWithFormat:@"#%02X%02XFD1A", lightR, lightG];
    NSString *darkMarker = [NSString stringWithFormat:@"#%02X%02X021A", darkR, darkG];
    if (light) CFDictionarySetValue(edited, LightKey, (CFStringRef)lightMarker);
    if (dark) CFDictionarySetValue(edited, DarkKey, (CFStringRef)darkMarker);
    if (original) CFRelease(original);

    LogLine([NSString stringWithFormat:@"[ISLAND] 0.1.2 marker supplied adaptation=%.3f level=%u/224", amount, level]);
    return edited;
}

static NSString *const FlatOld = @"flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const CurvedOld = @"float3 outRGB = mix(bg.rgb, u.tintColor.rgb, u.tintColor.a);";
static NSString *const PixelEntry = @"float4 mangoGlassPixel(";
static NSString *const AdaptiveFunction =
@"float3 mangoIslandAdaptiveColor(float3 background, float4 tint)\n"
 @"{\n"
 @"    // 0x1A alpha plus encoded near-white/near-black RGB identifies Island.\n"
 @"    float redByte = tint.r * 255.0;\n"
 @"    float greenByte = tint.g * 255.0;\n"
 @"    bool markerAlpha = abs(tint.a - (26.0 / 255.0)) < 0.0008;\n"
 @"    bool markerLight = redByte >= 239.5 && redByte <= 254.5 &&\n"
 @"                       greenByte >= 239.5 && greenByte <= 254.5 &&\n"
 @"                       abs(tint.b - (253.0 / 255.0)) < 0.0008;\n"
 @"    bool markerDark = redByte >= 0.5 && redByte <= 15.5 &&\n"
 @"                      greenByte >= 0.5 && greenByte <= 15.5 &&\n"
 @"                      abs(tint.b - (2.0 / 255.0)) < 0.0008;\n"
 @"    if (markerAlpha && (markerLight || markerDark)) {\n"
 @"        float encoded = 0.0;\n"
 @"        if (markerLight) {\n"
 @"            encoded = (redByte - 240.0) * 15.0 + (greenByte - 240.0);\n"
 @"        } else {\n"
 @"            float inverse = (redByte - 1.0) * 15.0 + (greenByte - 1.0);\n"
 @"            encoded = 224.0 - inverse;\n"
 @"        }\n"
 @"        float adaptation = clamp(encoded / 224.0, 0.0, 1.0);\n"
 @"        // Everything below through 'adaptive' is the exact 0.1.2 formula.\n"
 @"        float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));\n"
 @"        float bright = smoothstep(0.08, 0.42, luminance);\n"
 @"        float3 target = mix(float3(0.80), float3(0.025), bright);\n"
 @"        float opacity = mix(0.16, 0.42, bright);\n"
 @"        float3 adaptive = mix(background, target, opacity);\n"
 @"        if (adaptation > 0.9999) return adaptive;\n"
 @"        return mix(background, adaptive, adaptation);\n"
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
        LogLine(@"[SHADER] 0.1.2 adaptive mix + 225-level scalar compiled; other groups retain original mix");
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
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.2.1 baseline=0.1.2 slider=225-level process=%@ bundle=%@", process ?: @"(nil)", bundle ?: @"(nil)"]);

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
        LogLine([NSString stringWithFormat:@"[SESSION] 0.1.2.1 MetalClass=%@ shaderSeen=%d patched=%d",
                 NSStringFromClass(cls), ShaderSeen, ShaderPatched]);
    }
}
