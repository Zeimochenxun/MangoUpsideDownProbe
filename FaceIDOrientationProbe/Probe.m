#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <stdint.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <unistd.h>

static NSString *const kPrimaryLogDirectory = @"/var/mobile/Library/Logs/FaceIDOrientationProbe";
static NSString *const kPrimaryLogPath = @"/var/mobile/Library/Logs/FaceIDOrientationProbe/Probe.log";
static NSString *const kFallbackLogPath = @"/var/tmp/FaceIDOrientationProbe.log";

static dispatch_queue_t gQueue;
static dispatch_source_t gTimer;
static NSString *gSession;
static NSString *gLogPath;
static NSMutableSet<NSString *> *gLoggedImages;
static NSMutableSet<NSString *> *gLoggedClasses;
static NSMutableSet<NSString *> *gLoggedMethods;
static uint32_t gLastImageCount = UINT32_MAX;

static NSArray<NSString *> *Keywords(void) {
    static NSArray<NSString *> *keywords;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keywords = @[
            @"orientation", @"portrait", @"landscape", @"upside", @"rotation", @"rotate",
            @"pose", @"attitude", @"gravity", @"acceler", @"transform",
            @"camera", @"capture", @"sensor", @"depth", @"infrared", @"rgb",
            @"pearl", @"faceid", @"face id", @"biometr", @"attention", @"gaze", @"match"
        ];
    });
    return keywords;
}

static BOOL ContainsKeyword(NSString *value) {
    if (!value.length) return NO;
    for (NSString *keyword in Keywords()) {
        if ([value rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL RelevantImagePath(NSString *path) {
    if (!path.length) return NO;
    NSArray<NSString *> *parts = @[
        @"biometrickit", @"bkdm", @"localauthentication", @"coreauthentication",
        @"moduleacm", @"mechanismbase", @"daemonutils", @"pearl"
    ];
    for (NSString *part in parts) {
        if ([path rangeOfString:part options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL EnsurePrimaryLog(void) {
    NSError *error = nil;
    BOOL made = [[NSFileManager defaultManager] createDirectoryAtPath:kPrimaryLogDirectory
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error];
    if (!made) return NO;
    chmod(kPrimaryLogDirectory.fileSystemRepresentation, 0777);
    int fd = open(kPrimaryLogPath.fileSystemRepresentation,
                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0666);
    if (fd < 0) return NO;
    fchmod(fd, 0666);
    close(fd);
    return YES;
}

static void WriteLine(NSString *line) {
    if (!line.length || !gLogPath.length) return;
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    int fd = open(gLogPath.fileSystemRepresentation,
                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0666);
    if (fd < 0) return;
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t count = write(fd, bytes, remaining);
        if (count <= 0) break;
        bytes += count;
        remaining -= (NSUInteger)count;
    }
    close(fd);
}

static void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Log(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    WriteLine([NSString stringWithFormat:@"%.3f session=%@ process=%@ pid=%d %@",
               [NSDate date].timeIntervalSince1970, gSession,
               NSProcessInfo.processInfo.processName, getpid(), body]);
}

static NSString *UUIDForHeader(const struct mach_header *header) {
    if (!header || header->magic != MH_MAGIC_64) return @"unknown";
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    const uint8_t *cursor = (const uint8_t *)(header64 + 1);
    for (uint32_t index = 0; index < header64->ncmds; index++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(struct load_command)) break;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const uint8_t *b = ((const struct uuid_command *)command)->uuid;
            return [NSString stringWithFormat:
                    @"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                    b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9],
                    b[10], b[11], b[12], b[13], b[14], b[15]];
        }
        cursor += command->cmdsize;
    }
    return @"unknown";
}

static NSString *ImageForIMP(IMP implementation) {
    Dl_info info = {0};
    if (!implementation || dladdr((const void *)implementation, &info) == 0 || !info.dli_fname) {
        return @"unknown";
    }
    return [NSString stringWithUTF8String:info.dli_fname];
}

static void LogMethods(Class cls, NSString *className, BOOL classMethods, BOOL imageRelevant) {
    Class target = classMethods ? object_getClass(cls) : cls;
    if (!target) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    for (unsigned int index = 0; index < count; index++) {
        SEL selector = method_getName(methods[index]);
        NSString *selectorName = NSStringFromSelector(selector);
        if (!ContainsKeyword(selectorName)) continue;
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@", className,
                         classMethods ? @"+" : @"-", selectorName];
        if ([gLoggedMethods containsObject:key]) continue;
        [gLoggedMethods addObject:key];
        const char *types = method_getTypeEncoding(methods[index]);
        IMP implementation = method_getImplementation(methods[index]);
        Log(@"[METHOD] kind=%@ class=%@ selector=%@ types=%s image=%@ relevantImage=%d",
            classMethods ? @"class" : @"instance", className, selectorName,
            types ?: "unknown", ImageForIMP(implementation), imageRelevant);
    }
    free(methods);
}

static void ScanClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = calloc((size_t)count, sizeof(Class));
    if (!classes) return;
    count = objc_getClassList(classes, count);
    NSUInteger relevantCount = 0;
    for (int index = 0; index < count; index++) {
        Class cls = classes[index];
        const char *rawName = class_getName(cls);
        if (!rawName) continue;
        NSString *className = [NSString stringWithUTF8String:rawName];
        const char *rawImage = class_getImageName(cls);
        NSString *image = rawImage ? [NSString stringWithUTF8String:rawImage] : @"unknown";
        BOOL imageRelevant = RelevantImagePath(image);
        BOOL nameRelevant = ContainsKeyword(className);
        if (!imageRelevant && !nameRelevant) continue;
        relevantCount++;
        if (![gLoggedClasses containsObject:className]) {
            [gLoggedClasses addObject:className];
            Log(@"[CLASS] name=%@ image=%@ imageRelevant=%d nameRelevant=%d superclass=%@",
                className, image, imageRelevant, nameRelevant,
                class_getSuperclass(cls) ? NSStringFromClass(class_getSuperclass(cls)) : @"none");
        }
        LogMethods(cls, className, NO, imageRelevant);
        LogMethods(cls, className, YES, imageRelevant);
    }
    free(classes);
    Log(@"[CLASS-SCAN-END] runtimeClasses=%d relevantClasses=%lu loggedClasses=%lu loggedMethods=%lu",
        count, (unsigned long)relevantCount, (unsigned long)gLoggedClasses.count,
        (unsigned long)gLoggedMethods.count);
}

static void ScanImagesAndClasses(void) {
    uint32_t count = _dyld_image_count();
    if (count == gLastImageCount) return;
    Log(@"[SCAN-BEGIN] previousImageCount=%u imageCount=%u", gLastImageCount, count);
    gLastImageCount = count;
    for (uint32_t index = 0; index < count; index++) {
        const char *rawPath = _dyld_get_image_name(index);
        if (!rawPath) continue;
        NSString *path = [NSString stringWithUTF8String:rawPath];
        if (!RelevantImagePath(path) || [gLoggedImages containsObject:path]) continue;
        [gLoggedImages addObject:path];
        const struct mach_header *header = _dyld_get_image_header(index);
        Log(@"[IMAGE] index=%u path=%@ uuid=%@ slide=%lld", index, path,
            UUIDForHeader(header), (long long)_dyld_get_image_vmaddr_slide(index));
    }
    ScanClasses();
    Log(@"[SCAN-END] imageCount=%u relevantImages=%lu", count, (unsigned long)gLoggedImages.count);
}

static void StartTimer(void) {
    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              5 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(gTimer, ^{
        @autoreleasepool {
            ScanImagesAndClasses();
        }
    });
    dispatch_resume(gTimer);
}

__attribute__((constructor)) static void FaceIDOrientationProbeInit(void) {
    @autoreleasepool {
        gQueue = dispatch_queue_create("com.chenxun.faceidorientationprobe", DISPATCH_QUEUE_SERIAL);
        gSession = NSUUID.UUID.UUIDString;
        gLoggedImages = [NSMutableSet set];
        gLoggedClasses = [NSMutableSet set];
        gLoggedMethods = [NSMutableSet set];
        gLogPath = EnsurePrimaryLog() ? kPrimaryLogPath : kFallbackLogPath;
        Log(@"[SESSION] version=0.1.0 uid=%u euid=%u os=%@ log=%@ mode=read-only-no-hooks",
            getuid(), geteuid(), NSProcessInfo.processInfo.operatingSystemVersionString, gLogPath);
        StartTimer();
    }
}
