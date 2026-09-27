#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>

// Observation only: no hooks, preference writes, screenshots, or layer edits.
static NSString * const LogDirectory = @"/var/mobile/Library/Logs/MangoAdaptiveContrastProbe";
static int LogFD = -1;
static dispatch_source_t SampleTimer;
static NSString *PreviousState;
static unsigned TickCount;
static size_t BytesWritten;
static const size_t MaxBytes = 256 * 1024;

static void LogLine(NSString *line) {
    if (LogFD < 0 || !line || BytesWritten >= MaxBytes) return;
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (BytesWritten + data.length > MaxBytes) return;
    const uint8_t *p = data.bytes;
    size_t left = data.length;
    while (left) {
        ssize_t n = write(LogFD, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return;
        p += n; left -= (size_t)n; BytesWritten += (size_t)n;
    }
}

static BOOL OpenLog(void) {
    struct stat st;
    const char *dir = LogDirectory.fileSystemRepresentation;
    if (mkdir(dir, 0700) && errno != EEXIST) return NO;
    int d = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (d < 0 || fstat(d, &st) || !S_ISDIR(st.st_mode) || st.st_uid != geteuid() || (st.st_mode & 0022)) {
        if (d >= 0) close(d);
        return NO;
    }
    if (!fstatat(d, "Probe.log", &st, AT_SYMLINK_NOFOLLOW)) {
        if (!S_ISREG(st.st_mode) || st.st_uid != geteuid() || st.st_nlink != 1 ||
            renameat(d, "Probe.log", d, "Previous.log")) { close(d); return NO; }
    } else if (errno != ENOENT) { close(d); return NO; }
    LogFD = openat(d, "Probe.log", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    close(d);
    return LogFD >= 0;
}

static BOOL Visible(UIView *view) {
    if (!view.window || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *p = view; p; p = p.superview) {
        if (p.hidden || p.alpha < 0.02 || p.layer.hidden || p.layer.opacity < 0.02) return NO;
    }
    return YES;
}

static BOOL MangoIslandGlass(UIView *view) {
    Class cls = object_getClass(view);
    if (![NSStringFromClass(cls) isEqualToString:@"MGLiveBackdropView"]) return NO;
    const char *image = class_getImageName(cls);
    NSString *module = image ? [[NSString stringWithUTF8String:image] lastPathComponent] : nil;
    if (![module isEqualToString:@"mango.dylib"] && ![module isEqualToString:@"mangoos.dylib"]) return NO;
    SEL sel = @selector(lgFilterType);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char result[32] = {0}; method_getReturnType(method, result, sizeof(result));
    if (strcmp(result, "@")) return NO;
    id type = ((id (*)(id,SEL))objc_msgSend)(view, sel);
    return [type isKindOfClass:NSString.class] && [type isEqualToString:@"go.mangoos.island"];
}

static NSString *Filters(UIView *view) {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (id filter in view.layer.filters ?: @[]) {
        NSString *name = NSStringFromClass(object_getClass(filter));
        NSString *type = @"?";
        @try {
            id v = [filter valueForKey:@"type"];
            if ([v isKindOfClass:NSString.class]) type = v;
        } @catch (__unused NSException *e) { }
        [items addObject:[NSString stringWithFormat:@"%@/%@",name,type]];
        if (items.count >= 3) break;
    }
    return items.count ? [items componentsJoinedByString:@","] : @"none";
}

static void Sample(void) {
    if (++TickCount > 600 || access([LogDirectory stringByAppendingPathComponent:@"DISABLED"].fileSystemRepresentation,F_OK) == 0) {
        LogLine(@"[END] time-limit-or-disabled");
        dispatch_source_cancel(SampleTimer);
        close(LogFD); LogFD = -1;
        return;
    }
    @autoreleasepool {
        Class apertureWindow = NSClassFromString(@"SBSystemApertureWindow");
        if (!apertureWindow) return;
        NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSetWithArray:UIApplication.sharedApplication.windows];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];

        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        unsigned windowCount=0, visibleGlasses=0, totalGlasses=0, visibleElements=0, scanned=0;
        for (UIWindow *window in windows) {
            if (![window isKindOfClass:apertureWindow] || ++windowCount > 8) continue;
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count && scanned++ < 1200) {
                UIView *v = stack.lastObject; [stack removeLastObject];
                if (MangoIslandGlass(v)) {
                    totalGlasses++;
                    BOOL visible = Visible(v);
                    if (visible) visibleGlasses++;
                    [lines addObject:[NSString stringWithFormat:@"[ISLAND] view=%p module=%s visible=%d size=%.1fx%.1f alpha=%.2f filters=%@",
                        (void *)v,class_getImageName(object_getClass(v)) ?: "?",visible,v.bounds.size.width,v.bounds.size.height,v.alpha,Filters(v)]];
                } else if ([NSStringFromClass(object_getClass(v)) isEqualToString:@"SAUIElementView"] && Visible(v)) {
                    visibleElements++;
                    [lines addObject:[NSString stringWithFormat:@"[CONTENT] view=%p size=%.1fx%.1f",(void *)v,v.bounds.size.width,v.bounds.size.height]];
                }
                if (stack.count + scanned < 1200) [stack addObjectsFromArray:v.subviews];
            }
            [lines addObject:[NSString stringWithFormat:@"[WINDOW] class=%@ orientation=%ld trait=%ld visible=%d",
                NSStringFromClass(object_getClass(window)),(long)window.windowScene.interfaceOrientation,
                (long)window.traitCollection.userInterfaceStyle,!window.hidden && window.alpha > 0.02]];
        }
        [lines sortUsingSelector:@selector(compare:)];
        NSString *state = [NSString stringWithFormat:@"windows=%u glass=%u visibleGlass=%u visibleContent=%u scanned=%u\n%@",
            windowCount,totalGlasses,visibleGlasses,visibleElements,scanned,[lines componentsJoinedByString:@"\n"]];
        if (![state isEqualToString:PreviousState] || TickCount % 15 == 0) {
            LogLine([NSString stringWithFormat:@"[SAMPLE] t=%.0f tick=%u %@",NSDate.date.timeIntervalSince1970,TickCount,state]);
            PreviousState = state;
        }
    }
}

__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if (strcmp(getprogname(),"SpringBoard")) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!OpenLog()) return;
            LogLine([NSString stringWithFormat:@"[SESSION] version=0.1.0 pid=%d uuid=%@ mode=read-only duration=600s",getpid(),NSUUID.UUID.UUIDString]);
            SampleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            dispatch_source_set_timer(SampleTimer,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_SEC/10);
            dispatch_source_set_event_handler(SampleTimer, ^{ Sample(); });
            dispatch_resume(SampleTimer);
        });
    }
}
