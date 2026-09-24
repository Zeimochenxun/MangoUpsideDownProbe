#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

// No private message sends, method replacement, layout changes or extra windows.
static dispatch_queue_t gWriter;
static dispatch_source_t gTimer;
static NSString *gSession, *gLast;
static int gDir = -1, gFile = -1;
static unsigned gTick;
static size_t gBytes;
static atomic_bool gPending, gFailed;
static const size_t kMaxLog = 4 * 1024 * 1024;

static BOOL OpenLog(void) {
    NSString *path = @"/var/mobile/Library/Logs/MangoIdleIslandProbe";
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    gDir = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat st;
    if (gDir < 0 || fstat(gDir, &st) || st.st_uid != geteuid() || (st.st_mode & 0022)) return NO;
    if (fchmod(gDir, 0700)) return NO;
    if (!fstatat(gDir, "Probe.log", &st, AT_SYMLINK_NOFOLLOW)) {
        if (!S_ISREG(st.st_mode) || st.st_uid != geteuid() || st.st_nlink != 1 || st.st_size > (off_t)kMaxLog) return NO;
        if (renameat(gDir, "Probe.log", gDir, "Previous.log")) return NO;
    } else if (errno != ENOENT) return NO;
    gFile = openat(gDir, "Probe.log", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    return gFile >= 0;
}
static void Write(NSString *line) {
    if (gFile < 0 || atomic_load(&gFailed)) return;
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (gBytes + data.length > kMaxLog) { atomic_store(&gFailed, true); return; }
    const uint8_t *p = data.bytes; size_t left = data.length;
    while (left) {
        ssize_t n = write(gFile, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { atomic_store(&gFailed, true); return; }
        p += n; left -= (size_t)n; gBytes += (size_t)n;
    }
}
static void Close(void) {
    if (gFile >= 0) { close(gFile); gFile = -1; }
    if (gDir >= 0) { close(gDir); gDir = -1; }
}
static NSString *ImageUUID(const struct mach_header *header) {
    if (!header || header->magic != MH_MAGIC_64) return @"unknown";
    const struct mach_header_64 *h = (const void *)header;
    const uint8_t *p = (const uint8_t *)(h + 1), *end = p + h->sizeofcmds;
    for (unsigned i = 0; i < h->ncmds && end-p >= (ptrdiff_t)sizeof(struct load_command); i++) {
        const struct load_command *c = (const void *)p;
        if (c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end-p)) break;
        if (c->cmd == LC_UUID && c->cmdsize >= sizeof(struct uuid_command))
            return [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)c)->uuid].UUIDString;
        p += c->cmdsize;
    }
    return @"unknown";
}
static BOOL Relevant(UIView *view) {
    NSString *name = NSStringFromClass(object_getClass(view));
    return [name containsString:@"Aperture"] || [name hasPrefix:@"SAUI"] ||
        [name isEqualToString:@"MGLiveBackdropView"] || [name isEqualToString:@"_SBGainMapView"];
}
static NSString *ViewLine(UIView *view, NSString *kind) {
    UIView *parent = view.superview;
    CALayer *layer = view.layer;
    CALayer *presentation = layer.presentationLayer;
    CGAffineTransform t = view.transform;
    return [NSString stringWithFormat:
        @"[%@] id=%p class=%@ parent=%p window=%p frame=%@ bounds=%@ hidden=%d alpha=%.3f layerHidden=%d opacity=%.3f presentation=%d pBounds=%@ pOpacity=%.3f transform={%.3f,%.3f,%.3f,%.3f,%.1f,%.1f} clips=%d interaction=%d childCount=%lu",
        kind, (__bridge void *)view, NSStringFromClass(object_getClass(view)), (__bridge void *)parent,
        (__bridge void *)view.window, NSStringFromCGRect(view.frame), NSStringFromCGRect(view.bounds),
        view.hidden, view.alpha, layer.hidden, layer.opacity, presentation != nil,
        presentation ? NSStringFromCGRect(presentation.bounds) : @"none", presentation ? presentation.opacity : -1.0,
        t.a,t.b,t.c,t.d,t.tx,t.ty,view.clipsToBounds,view.userInteractionEnabled,(unsigned long)view.subviews.count];
}

// Main thread only. All UIKit access is bounded to 32 windows / 1200 nodes / depth 20.
static NSString *Snapshot(void) {
    UIApplication *app = UIApplication.sharedApplication;
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSetWithArray:app.windows];
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableSet<NSValue *> *emitted = [NSMutableSet set];
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray array];
    unsigned scanned = 0, matched = 0, windowCount = 0;
    BOOL truncated = NO;
    NSArray<UIWindow *> *ordered = [windows.array sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        BOOL first = Relevant(a), second = Relevant(b);
        // Stack is LIFO: named aperture windows are visited first.
        return first == second ? NSOrderedSame : (first ? NSOrderedDescending : NSOrderedAscending);
    }];
    for (UIWindow *window in ordered) {
        if (windowCount++ >= 32) { truncated = YES; break; }
        UIWindowScene *scene = window.windowScene;
        [lines addObject:[NSString stringWithFormat:@"[WINDOW] id=%p class=%@ level=%.1f frame=%@ bounds=%@ hidden=%d alpha=%.3f sceneOrientation=%ld sceneState=%ld root=%@",
            (__bridge void *)window, NSStringFromClass(object_getClass(window)), window.windowLevel,
            NSStringFromCGRect(window.frame), NSStringFromCGRect(window.bounds),window.hidden,window.alpha,
            scene ? (long)scene.interfaceOrientation : -1L, scene ? (long)scene.activationState : -1L,
            window.rootViewController ? NSStringFromClass(object_getClass(window.rootViewController)) : @"none"]];
        [stack addObject:window]; [depths addObject:@0];
    }
    while (stack.count && scanned < 1200 && emitted.count < 160) {
        UIView *view = stack.lastObject; [stack removeLastObject];
        unsigned depth = depths.lastObject.unsignedIntValue; [depths removeLastObject];
        scanned++;
        if (Relevant(view)) {
            matched++;
            UIView *ancestor = view;
            for (unsigned a = 0; ancestor && a < 24 && emitted.count < 160; a++, ancestor = ancestor.superview) {
                NSValue *key = [NSValue valueWithNonretainedObject:ancestor];
                if (![emitted containsObject:key]) {
                    [lines addObject:ViewLine(ancestor, a == 0 ? @"TARGET" : @"ANCESTOR")];
                    [emitted addObject:key];
                }
            }
        }
        NSArray<UIView *> *children = view.subviews;
        if (depth >= 20) { if (children.count) truncated = YES; continue; }
        for (UIView *child in children.reverseObjectEnumerator) {
            if (stack.count + scanned >= 1200) { truncated = YES; break; }
            [stack addObject:child]; [depths addObject:@(depth+1)];
        }
    }
    truncated |= stack.count != 0;
    [lines insertObject:[NSString stringWithFormat:@"[SUMMARY] enumeratedWindows=%lu scannedNodes=%u targets=%u truncated=%d missingTargetIsNotProofOfGlobalAbsence=1",
        (unsigned long)windows.count,scanned,matched,truncated] atIndex:0];
    return [lines componentsJoinedByString:@"\n"];
}
static void Stop(NSString *reason) {
    dispatch_source_cancel(gTimer);
    dispatch_async(gWriter, ^{
        Write([NSString stringWithFormat:@"[END] reason=%@ samplesAttempted=%u",reason,gTick]);
        Close();
    });
}
static void Tick(void) {
    // Writer cannot close gDir until the timer has stopped.
    struct stat st;
    if (gTick >= 60 || atomic_load(&gFailed) || !fstatat(gDir,"DISABLED",&st,AT_SYMLINK_NOFOLLOW)) {
        Stop(gTick >= 60 ? @"120-second-limit" : @"disabled-or-write-limit"); return;
    }
    gTick++;
    if (atomic_exchange(&gPending, true)) return;
    @autoreleasepool {
        NSString *body;
        @try { body = Snapshot(); }
        @catch (__unused NSException *exception) { body = @"[SNAPSHOT-ERROR] UIKit observation failed; exception contents omitted"; }
        NSTimeInterval timestamp = NSDate.date.timeIntervalSince1970;
        unsigned tick = gTick;
        dispatch_async(gWriter, ^{
            @autoreleasepool {
                NSString *textBody = body;
                if (textBody.length > 64000) textBody = [[textBody substringToIndex:63000] stringByAppendingString:@"\n[TRUNCATED] text-limit"];
                if (![textBody isEqualToString:gLast] || tick % 10 == 0) {
                    Write([NSString stringWithFormat:@"[SNAPSHOT] time=%.3f session=%@ tick=%u\n%@",timestamp,gSession,tick,textBody]);
                    gLast = textBody;
                }
                atomic_store(&gPending, false);
            }
        });
    }
}
__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        if (strcmp(getprogname(),"SpringBoard")) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5) return;
        gWriter = dispatch_queue_create("com.chenxun.mangoidleislandprobe.writer",DISPATCH_QUEUE_SERIAL);
        dispatch_async(gWriter, ^{
            @autoreleasepool {
                if (!OpenLog()) { Close(); return; }
                gSession = NSUUID.UUID.UUIDString;
                Write([NSString stringWithFormat:@"[SESSION] version=0.1.0 pid=%d session=%@ startupDelay=10s duration=120s interval=2s maxBytes=4194304 mode=read-only-view-sampling",getpid(),gSession]);
                unsigned count = _dyld_image_count();
                for (unsigned i=0;i<count;i++) {
                    const char *path = _dyld_get_image_name(i);
                    if (!path) continue;
                    NSString *name = [NSString stringWithUTF8String:path].lastPathComponent;
                    if ([name isEqualToString:@"mango.dylib"] || [name isEqualToString:@"mangoos.dylib"])
                        Write([NSString stringWithFormat:@"[IMAGE] name=%@ uuid=%@",name,ImageUUID(_dyld_get_image_header(i))]);
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
                    dispatch_source_set_timer(gTimer,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),2*NSEC_PER_SEC,NSEC_PER_SEC/10);
                    dispatch_source_set_event_handler(gTimer, ^{ Tick(); });
                    dispatch_resume(gTimer);
                });
            }
        });
    }
}
