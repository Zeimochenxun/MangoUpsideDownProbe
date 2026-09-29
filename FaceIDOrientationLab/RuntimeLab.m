#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CydiaSubstrate/CydiaSubstrate.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#import <dlfcn.h>
#import <ptrauth.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <errno.h>
#import <fcntl.h>
#import <pwd.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <time.h>
#import <unistd.h>
#if LAB_SPRINGBOARD
#import <UIKit/UIKit.h>
#define LAB_PROCESS "SpringBoard"
#define LAB_LOGDIR "/var/mobile/Library/Logs/FaceIDOrientationLab-SB"
#else
#define LAB_PROCESS "biometrickitd"
#define LAB_LOGDIR "/var/mobile/Library/Logs/FaceIDOrientationLab-Bio"
#endif
#define EVENT_KINDS 9

// Only verified scalar methods. Never message private objects from the probe.
static const char *kClasses[] = {"BiometricKitXPCServerPearl", "BKFaceDetectStateInfo", "BKFaceDetectStateInfo", "PearlCoreAnalytics", "UIDevice", "SBTraitsSceneParticipantDelegate", "UIDevice"};
static const char *kSelectors[] = {"deviceOrientation", "setOrientation:", "orientation", "sendMatchEventAnalytics:orientation:identities:", "userInterfaceIdiom", "_orientationMode", "orientation"};
static const char *kTypes[] = {"Q16@0:8", "v24@0:8Q16", "Q16@0:8", "v40@0:8@16Q24@32", "q16@0:8", "q16@0:8"};
static const char *kBKDM = "/usr/lib/libBKDM2.dylib";
static const char *kBK = "/System/Library/PrivateFrameworks/BiometricKit.framework/BiometricKit";
static IMP gOriginal[6];
static BOOL gInstalled[6], gRejected[6];
static dispatch_queue_t gQueue;
static dispatch_source_t gTimer;
static int gDir = -1, gFD = -1;
static size_t gBytes;
static NSString *gSession;
static BOOL gStopped;
static _Atomic(bool) gEnabled;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned gPhase, gTicks;
static uint64_t gStarted;
#if LAB_SPRINGBOARD
static BOOL gSensorStarted;
static _Atomic(bool) gSensorPending;
#endif
static const char *kPhases[] = {"unknown", "portrait", "upsideDown", "landscapeLeft", "landscapeRight"};
typedef struct { unsigned method, phase; uint64_t value, ns; uintptr_t caller; } Event;
static Event gEvents[64];
static unsigned gUsed;
static uint64_t gCounts[EVENT_KINDS], gLimited[EVENT_KINDS], gSeconds[EVENT_KINDS];
static unsigned gPerSecond[EVENT_KINDS];
static _Atomic(uint64_t) gBusyDrops;
#if !LAB_SPRINGBOARD
static CFTypeRef (*gCopyAnswer)(CFStringRef, CFDictionaryRef);
static bool (*gBoolAnswer)(CFStringRef);
static BOOL gMGInstalled[2];
static BOOL gCodeCaptured;
static const CFStringRef kMGKeys[] = {CFSTR("DeviceClass"), CFSTR("DeviceClassNumber"), CFSTR("PearlIDCapability"), CFSTR("DeviceSupportsLandscapeFaceID"), CFSTR("+3Uf0Pm5F8Xy7Onyvko0vA"), CFSTR("mtrAoWJ3gsq+I90ZnQ0vQw"), CFSTR("8olRm6C1xqr7AJGpLRnpSw"), CFSTR("eP/CPXY0Q1CoIqAWn/J97g")};
static const char *kMGNames[] = {"DeviceClass", "DeviceClassNumber", "PearlIDCapability", "DeviceSupportsLandscapeFaceID", "+3Uf0Pm5F8Xy7Onyvko0vA", "mtrAoWJ3gsq+I90ZnQ0vQw", "8olRm6C1xqr7AJGpLRnpSw", "eP/CPXY0Q1CoIqAWn/J97g"};
#endif

static uint64_t Now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &t)) return 0;
    return (uint64_t)t.tv_sec * 1000000000ULL + (uint64_t)t.tv_nsec;
}

// No allocation, object access, file I/O or queued blocks on authentication threads.
static void Observe(unsigned method, uint64_t value, uintptr_t caller) {
    if (method >= EVENT_KINDS || !atomic_load_explicit(&gEnabled, memory_order_acquire)) return;
    if (pthread_mutex_trylock(&gLock)) { atomic_fetch_add(&gBusyDrops, 1); return; }
    uint64_t ns = Now(), sec = ns / 1000000000ULL;
    if (!ns || ns < gStarted || ns - gStarted >= 600000000000ULL) { atomic_store(&gEnabled, false); pthread_mutex_unlock(&gLock); return; }
    gCounts[method]++;
    if (sec != gSeconds[method]) { gSeconds[method] = sec; gPerSecond[method] = 0; }
    if (gUsed < 64 && gPerSecond[method] < 4) {
        gEvents[gUsed++] = (Event){method, gPhase, value, ns, caller};
        gPerSecond[method]++;
    } else gLimited[method]++;
    pthread_mutex_unlock(&gLock);
}
static uint64_t DeviceOrientation(id self, SEL cmd) {
    uint64_t result = ((uint64_t (*)(id, SEL))gOriginal[0])(self, cmd);
    Observe(0, result, (uintptr_t)__builtin_return_address(0)); return result;
}
static void SetOrientation(id self, SEL cmd, uint64_t value) {
    Observe(1, value, (uintptr_t)__builtin_return_address(0));
    ((void (*)(id, SEL, uint64_t))gOriginal[1])(self, cmd, value);
}
static uint64_t Orientation(id self, SEL cmd) {
    uint64_t result = ((uint64_t (*)(id, SEL))gOriginal[2])(self, cmd);
    Observe(2, result, (uintptr_t)__builtin_return_address(0)); return result;
}
static void Analytics(id self, SEL cmd, id event, uint64_t value, id identities) {
    Observe(3, value, (uintptr_t)__builtin_return_address(0));
    ((void (*)(id, SEL, id, uint64_t, id))gOriginal[3])(self, cmd, event, value, identities);
}

static int64_t Idiom(id self, SEL cmd) {
    int64_t result = ((int64_t (*)(id, SEL))gOriginal[4])(self, cmd);
    Observe(4, (uint64_t)result, (uintptr_t)__builtin_return_address(0)); return result;
}
static int64_t OrientationMode(id self, SEL cmd) {
    int64_t result = ((int64_t (*)(id, SEL))gOriginal[5])(self, cmd);
    Observe(5, (uint64_t)result, (uintptr_t)__builtin_return_address(0)); return result;
}
#if !LAB_SPRINGBOARD
// Only an allow-listed key is recorded. Answers and authentication objects are untouched.
static void ObserveMG(unsigned method, CFStringRef key, uintptr_t caller) {
    if (!atomic_load_explicit(&gEnabled, memory_order_acquire) || !key || CFGetTypeID(key) != CFStringGetTypeID()) return;
    for (unsigned i = 0; i < sizeof(kMGKeys) / sizeof(kMGKeys[0]); i++)
        if (CFEqual(key, kMGKeys[i])) { Observe(method, i, caller); break; }
}
static CFTypeRef CopyAnswer(CFStringRef key, CFDictionaryRef options) {
    CFTypeRef result = gCopyAnswer(key, options);
    ObserveMG(7, key, (uintptr_t)__builtin_return_address(0)); return result;
}
static bool BoolAnswer(CFStringRef key) {
    bool result = gBoolAnswer(key);
    ObserveMG(8, key, (uintptr_t)__builtin_return_address(0)); return result;
}
#endif

static void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Log(NSString *format, ...) {
    if (gFD < 0) return;
    va_list args; va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSData *data = [[NSString stringWithFormat:@"%.3f session=%@ %@\n", NSDate.date.timeIntervalSince1970, gSession, body] dataUsingEncoding:NSUTF8StringEncoding];
    if (gBytes + data.length > 2 * 1024 * 1024) {
        atomic_store(&gEnabled, false); gStopped = YES; close(gFD); gFD = -1; return;
    }
    const uint8_t *p = data.bytes; size_t left = data.length;
    while (left) {
        ssize_t n = write(gFD, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { atomic_store(&gEnabled, false); gStopped = YES; close(gFD); gFD = -1; return; }
        gBytes += (size_t)n; p += n; left -= (size_t)n;
    }
}
static NSString *UUID(const struct mach_header_64 *h) {
    if (!h || h->magic != MH_MAGIC_64) return nil;
    const uint8_t *p = (const uint8_t *)(h + 1), *end = p + h->sizeofcmds;
    for (uint32_t i = 0; i < h->ncmds && (size_t)(end - p) >= sizeof(struct load_command); i++) {
        const struct load_command *c = (const void *)p;
        if (c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end - p)) return nil;
        if (c->cmd == LC_UUID && c->cmdsize >= sizeof(struct uuid_command))
            return [[[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)c)->uuid].UUIDString lowercaseString];
        p += c->cmdsize;
    }
    return nil;
}
static void InstallHooks(void) {
    IMP replacements[] = {(IMP)DeviceOrientation, (IMP)SetOrientation, (IMP)Orientation, (IMP)Analytics, (IMP)Idiom, (IMP)OrientationMode};
    for (unsigned i = (LAB_SPRINGBOARD ? 4 : 0); i < (LAB_SPRINGBOARD ? 6 : 4) && !gStopped; i++) {
        if (gInstalled[i] || gRejected[i]) continue;
        Class cls = objc_lookUpClass(kClasses[i]);
        if (!cls) continue; // Retry without loading frameworks or instantiating classes.
        SEL sel = sel_registerName(kSelectors[i]);
        Method method = NULL;
        unsigned count = 0;
        Method *list = class_copyMethodList(cls, &count);
        for (unsigned j = 0; j < count; j++) if (method_getName(list[j]) == sel) method = list[j];
        free(list);
        const char *types = method ? method_getTypeEncoding(method) : NULL;
        Dl_info info = {0};
        IMP imp = method ? method_getImplementation(method) : NULL;
        const void *address = imp ? ptrauth_strip((void *)imp, ptrauth_key_function_pointer) : NULL;
        BOOL located = address && dladdr(address, &info);
        const char *path = (i == 0 || i == 3) ? kBKDM : kBK;
        NSString *expectedUUID = (i == 0 || i == 3) ? @"503938ad-b29d-3894-b44c-c2be6ffcef56" : @"e9844b6f-4721-3d52-8988-68e1381b86f6";
        NSString *actualUUID = located ? UUID(info.dli_fbase) : nil;
        if (!types || strcmp(types, kTypes[i]) || !located || !info.dli_fname || (i < 4 && (strcmp(info.dli_fname, path) || ![actualUUID isEqualToString:expectedUUID]))) {
            gRejected[i] = YES;
            Log(@"[SKIP] class=%s selector=%s types=%s image=%s uuid=%@ reason=signature-or-image-mismatch", kClasses[i], kSelectors[i], types ?: "missing", info.dli_fname ?: "unknown", actualUUID ?: @"unknown");
            continue;
        }
        MSHookMessageEx(cls, sel, replacements[i], &gOriginal[i]);
        gInstalled[i] = YES;
        Log(@"[HOOK] class=%s selector=%s types=%s image=%s uuid=%@ preserve-existing-chain=YES", kClasses[i], kSelectors[i], types, info.dli_fname, actualUUID);
    }
}
#if !LAB_SPRINGBOARD
static void InstallMG(void) {
    const char *symbols[] = {"MGCopyAnswer", "MGGetBoolAnswer"};
    void *replacements[] = {(void *)CopyAnswer, (void *)BoolAnswer};
    void **originals[] = {(void **)&gCopyAnswer, (void **)&gBoolAnswer};
    for (unsigned i = 0; i < 2; i++) {
        if (gMGInstalled[i]) continue;
        void *address = dlsym(RTLD_DEFAULT, symbols[i]);
        Dl_info info = {0};
        if (!address || !dladdr(ptrauth_strip(address, ptrauth_key_function_pointer), &info) || !info.dli_fname || !strstr(info.dli_fname, "libMobileGestalt.dylib")) continue;
        MSHookFunction(address, replacements[i], originals[i]);
        if (!*originals[i]) { Log(@"[MG-SKIP] symbol=%s reason=no-original-trampoline", symbols[i]); continue; }
        gMGInstalled[i] = YES;
        Log(@"[MG-HOOK] symbol=%s image=%s uuid=%@ observe-keys-only=YES", symbols[i], info.dli_fname, UUID(info.dli_fbase) ?: @"unknown");
    }
}
#endif
static BOOL RegularFile(int fd) {
    struct stat st;
    return fd >= 0 && !fstat(fd, &st) && S_ISREG(st.st_mode) && st.st_nlink == 1 && st.st_uid == geteuid();
}
static void CreateControl(const char *name, const char *value, gid_t gid) {
    int fd = openat(gDir, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0660);
    if (fd < 0) return;
    if (fchown(fd, geteuid(), gid) == 0 && fchmod(fd, 0660) == 0) (void)write(fd, value, strlen(value));
    close(fd);
}
static BOOL OpenLogs(void) {
    // Separate per-process directories preserve ownership and avoid cross-process writers.
    const char *path = LAB_LOGDIR;
    if (mkdir(path, 0700) && errno != EEXIST) return NO;
    gDir = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat st;
    if (gDir < 0 || fstat(gDir, &st) || st.st_uid != geteuid() || (st.st_mode & 0022)) return NO;
    struct passwd *mobile = getpwnam("mobile");
    gid_t gid = mobile ? mobile->pw_gid : getegid();
    if (fchown(gDir, geteuid(), gid) || fchmod(gDir, 0750)) return NO;
    if (!fstatat(gDir, "Probe.log", &st, AT_SYMLINK_NOFOLLOW)) {
        if (!S_ISREG(st.st_mode) || st.st_uid != geteuid() || st.st_nlink != 1 || st.st_size > 2 * 1024 * 1024) return NO;
        if (renameat(gDir, "Probe.log", gDir, "Previous.log")) return NO;
    } else if (errno != ENOENT) return NO;
    gFD = openat(gDir, "Probe.log", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0640);
    if (!RegularFile(gFD) || fchown(gFD, geteuid(), gid) || fchmod(gFD, 0640)) return NO;
    CreateControl("Phase.txt", "unknown\n", gid);
    CreateControl("Disable.txt", "0\n", gid);
    return YES;
}
#if !LAB_SPRINGBOARD
static void CaptureBKDMCode(void) {
    if (gCodeCaptured || gDir < 0) return;
    Class cls = objc_lookUpClass("BiometricKitXPCServerPearl");
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName("deviceOrientation")) : NULL;
    Dl_info info = {0};
    const void *imp = method ? ptrauth_strip((void *)method_getImplementation(method), ptrauth_key_function_pointer) : NULL;
    if (!imp || !dladdr(imp, &info) || !info.dli_fname || strcmp(info.dli_fname, kBKDM)) return;
    const struct mach_header_64 *h = info.dli_fbase;
    NSString *uuid = UUID(h);
    if (![uuid isEqualToString:@"503938ad-b29d-3894-b44c-c2be6ffcef56"]) return;
    // The on-disk dylib may be inside the shared cache. Copy only mapped __TEXT
    // containing the observed return offsets, after validating segment bounds.
    const uint32_t start = 0x4000;
    const uint8_t *p = (const uint8_t *)(h + 1), *end = p + h->sizeofcmds;
    uint32_t length = 0;
    for (uint32_t i = 0; i < h->ncmds && (size_t)(end - p) >= sizeof(struct load_command); i++) {
        const struct load_command *c = (const void *)p;
        if (c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end - p)) return;
        if (c->cmd == LC_SEGMENT_64 && c->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const void *)c;
            if (!strncmp(seg->segname, "__TEXT", sizeof(seg->segname)) && seg->fileoff == 0 && seg->vmsize >= 0x6000 && (seg->initprot & VM_PROT_READ)) length = (uint32_t)(seg->vmsize < 0x10000 ? seg->vmsize : 0x10000) - start;
        }
        p += c->cmdsize;
    }
    if (!length) { Log(@"[CODE-SKIP] reason=text-bounds-or-read-permission"); gCodeCaptured = YES; return; }
    int fd = openat(gDir, "BKDM-code-from-4000.bin", O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0640);
    if (!RegularFile(fd) || ftruncate(fd, 0)) { if (fd >= 0) close(fd); Log(@"[CODE-SKIP] reason=unsafe-output"); gCodeCaptured = YES; return; }
    struct passwd *mobile = getpwnam("mobile");
    gid_t gid = mobile ? mobile->pw_gid : getegid();
    if (fchown(fd, geteuid(), gid) || fchmod(fd, 0640)) { close(fd); Log(@"[CODE-SKIP] reason=output-permissions"); gCodeCaptured = YES; return; }
    const uint8_t *source = (const uint8_t *)h + start;
    size_t remain = length;
    while (remain) {
        ssize_t n = write(fd, source, remain);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { close(fd); Log(@"[CODE-SKIP] reason=short-write"); gCodeCaptured = YES; return; }
        source += n; remain -= (size_t)n;
    }
    close(fd); gCodeCaptured = YES;
    Log(@"[CODE-DUMP] file=BKDM-code-from-4000.bin image=%s uuid=%@ baseRelativeStart=0x4000 length=0x%x source=mapped-__TEXT read-only=YES", info.dli_fname, uuid, length);
}
#endif
static NSString *ReadControl(const char *name) {
    int fd = openat(gDir, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (!RegularFile(fd)) { if (fd >= 0) close(fd); return nil; }
    char buf[65]; ssize_t n = read(fd, buf, sizeof(buf)); close(fd);
    if (n <= 0 || n >= (ssize_t)sizeof(buf)) return nil;
    return [[[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static void Tick(void) {
    if (gStopped) {
        if (gTimer) { dispatch_source_cancel(gTimer); gTimer = nil; }
#if LAB_SPRINGBOARD
        dispatch_async(dispatch_get_main_queue(), ^{ if (gSensorStarted) { [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications]; gSensorStarted = NO; } });
#endif
        if (gFD >= 0) { close(gFD); gFD = -1; }
        if (gDir >= 0) { close(gDir); gDir = -1; }
        return;
    }
    if (Now() - gStarted >= 600000000000ULL) {
        atomic_store(&gEnabled, false); gStopped = YES;
        Log(@"[STOP] reason=ten-minute-limit hooks-forward-unchanged=YES"); return;
    }
    NSString *disable = ReadControl("Disable.txt");
    if (![disable isEqualToString:@"0"]) {
        atomic_store(&gEnabled, false); gStopped = YES;
        Log(@"[DISABLED] reason=control-file forwarding=unchanged restart-required-to-resume"); return;
    }
    NSString *phase = ReadControl("Phase.txt");
    unsigned next = 0;
    for (unsigned i = 1; i < 5; i++) if ([phase isEqualToString:@(kPhases[i])]) next = i;
    Event events[64]; unsigned used, old;
    uint64_t counts[EVENT_KINDS], limited[EVENT_KINDS];
    pthread_mutex_lock(&gLock);
    old = gPhase; gPhase = next;
    used = gUsed; memcpy(events, gEvents, used * sizeof(Event)); gUsed = 0;
    memcpy(counts, gCounts, sizeof(counts)); memcpy(limited, gLimited, sizeof(limited));
    pthread_mutex_unlock(&gLock);
    if (next != old) Log(@"[PHASE] label=%s source=manual not-system-orientation", kPhases[next]);
    for (unsigned i = 0; i < used; i++) {
        Event e = events[i];
        Dl_info callerInfo = {0};
        const void *caller = (const void *)ptrauth_strip((void *)e.caller, ptrauth_key_function_pointer);
        BOOL haveCaller = caller && dladdr(caller, &callerInfo);
        const char *name = e.method < 7 ? kSelectors[e.method] : (e.method == 7 ? "MGCopyAnswer" : "MGGetBoolAnswer");
        const char *cls = e.method < 7 ? kClasses[e.method] : "MobileGestalt";
        if (haveCaller) Log(@"[CALLER] mono_ns=%llu class=%s selector=%s image=%s uuid=%@ returnOffset=0x%llx",
            (unsigned long long)e.ns, cls, name, callerInfo.dli_fname ?: "unknown",
            UUID(callerInfo.dli_fbase) ?: @"unknown", (unsigned long long)((uintptr_t)caller - (uintptr_t)callerInfo.dli_fbase));
#if !LAB_SPRINGBOARD
        if (e.method >= 7) {
            if (e.value < sizeof(kMGNames) / sizeof(kMGNames[0])) Log(@"[MG-QUERY] mono_ns=%llu phase=%s symbol=%s key=%s answer=not-read", (unsigned long long)e.ns, kPhases[e.phase], name, kMGNames[e.value]);
            continue;
        }
#endif
        Log(@"[ORIENTATION] mono_ns=%llu phase=%s source=manual class=%s selector=%s raw=%llu observation=%s",
            (unsigned long long)e.ns, kPhases[e.phase], kClasses[e.method], kSelectors[e.method], (unsigned long long)e.value,
            (e.method == 1 || e.method == 3) ? "argument" : (e.method == 6 ? "public-UIDevice-sample-not-auth-input" : "return"));
    }
    if (gStopped) return;
    if (gTicks < 120) {
#if !LAB_SPRINGBOARD
        CaptureBKDMCode();
#endif
        InstallHooks();
#if !LAB_SPRINGBOARD
        InstallMG();
#endif
    }
    if (gTicks % 15 == 0) {
        Log(@"[COUNTS] phase=%s device=%llu setter=%llu getter=%llu analytics=%llu idiom=%llu mode=%llu publicOrientation=%llu mgCopy=%llu mgBool=%llu limited=%llu busyDropped=%llu hooks=%d%d%d%d%d%d",
            kPhases[next], (unsigned long long)counts[0], (unsigned long long)counts[1], (unsigned long long)counts[2], (unsigned long long)counts[3],
            (unsigned long long)counts[4], (unsigned long long)counts[5], (unsigned long long)counts[6],
            (unsigned long long)counts[7], (unsigned long long)counts[8],
            (unsigned long long)(limited[0]+limited[1]+limited[2]+limited[3]+limited[4]+limited[5]+limited[6]+limited[7]+limited[8]), (unsigned long long)atomic_load(&gBusyDrops), gInstalled[0], gInstalled[1], gInstalled[2], gInstalled[3], gInstalled[4], gInstalled[5]);
    }
    if (gTicks == 120) Log(@"[DISCOVERY-END] absent-or-rejected-methods-remain-unhooked");
    if (!gStopped) atomic_store(&gEnabled, true);
#if LAB_SPRINGBOARD
    if (!gStopped && !atomic_exchange(&gSensorPending, true)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (atomic_load(&gEnabled)) {
                if (!gSensorStarted) { [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications]; gSensorStarted = YES; }
                Observe(6, (uint64_t)[UIDevice currentDevice].orientation, 0);
            }
            atomic_store(&gSensorPending, false);
        });
    }
#endif
    gTicks++;
}
__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        if (strcmp(getprogname(), LAB_PROCESS)) return;
        char build[64] = {0}, model[64] = {0}; size_t bs = sizeof(build), ms = sizeof(model);
        if (sysctlbyname("kern.osversion", build, &bs, NULL, 0) || sysctlbyname("hw.machine", model, &ms, NULL, 0)) return;
        if (strcmp(build, "20F66") || strcmp(model, "iPhone14,4")) return;
        gQueue = dispatch_queue_create("com.chenxun.faceidorientationlab", DISPATCH_QUEUE_SERIAL);
        dispatch_async(gQueue, ^{
            @autoreleasepool {
                if (!OpenLogs()) { if (gFD >= 0) close(gFD); if (gDir >= 0) close(gDir); gFD = gDir = -1; return; }
                gSession = NSUUID.UUID.UUIDString; gStarted = Now();
                Log(@"[SESSION] version=0.1.2-alpha3 process=%s pid=%d build=20F66 model=iPhone14,4 mode=observe-only maxBytes=2097152 maxSamplesPerMethodPerSecond=4", LAB_PROCESS, getpid());
                Log(@"[NOTICE] raw-enum=unknown analytics-is-not-proof-of-control-path phase=manual no-identities-or-auth-results-recorded");
                gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
                dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
                dispatch_source_set_event_handler(gTimer, ^{ @autoreleasepool { Tick(); } });
                dispatch_resume(gTimer);
            }
        });
    }
}
