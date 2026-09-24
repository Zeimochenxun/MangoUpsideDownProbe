#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>
#import <string.h>

// Private names below were observed in the supplied Beta7-1 Probe.log.
// Only layoutSubviews (void, no arguments) is hooked after signature validation.
static Class HostClass, WindowClass, ContentClass;
static void (*OriginalLayout)(id, SEL);
static BOOL InUpdate, Disabled;
static NSHashTable<UIView *> *Hosts;
static dispatch_source_t Timer;
static char BackgroundKey, StateKey;
static NSString * const LogDir = @"/var/mobile/Library/Logs/MangoIdleIsland";

static void Log(NSString *event) {
    struct stat st;
    const char *dir = LogDir.fileSystemRepresentation;
    if (mkdir(dir, 0700) && lstat(dir, &st)) return;
    if (lstat(dir, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid()) return;
    NSString *path = [LogDir stringByAppendingPathComponent:@"Status.log"];
    int fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_NONBLOCK, 0600);
    if (fd < 0) return;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_nlink != 1) { close(fd); return; }
    if (st.st_size > 65536) { if (ftruncate(fd, 0)) { close(fd); return; } }
    NSData *line = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, event] dataUsingEncoding:NSUTF8StringEncoding];
    (void)write(fd, line.bytes, line.length);
    close(fd);
}

static BOOL Visible(UIView *v) {
    if (!v.window || v.window.hidden || v.window.alpha < 0.99) return NO;
    for (UIView *p = v; p; p = p.superview) {
        if (p.hidden || p.alpha < 0.99 || p.layer.hidden || p.layer.opacity < 0.99) return NO;
    }
    return YES;
}

static NSString *Eligibility(UIView *host) {
    if (Disabled) return @"disabled";
    UIWindow *w = host.window;
    if (![w isKindOfClass:WindowClass] || !w.userInteractionEnabled) return @"window-excluded";
    if (!Visible(host)) return @"host-not-visible";
    CGSize size = host.bounds.size;
    // Conservative initial gate based on the observed 125 x 36.67 idle host.
    // Expanded/active geometries are never forced into an idle shape.
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 110 || size.width > 140 || size.height < 28 || size.height > 45) return @"geometry-excluded";
    NSMutableArray<UIView *> *todo = [host.subviews mutableCopy];
    UIView *content = nil;
    UIView *own = objc_getAssociatedObject(host, &BackgroundKey);
    NSUInteger count = 0;
    while (todo.count && count++ < 256) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        if (v == own) continue;
        if ([v isKindOfClass:ContentClass]) {
            if (content) return @"ambiguous-content";
            content = v;
        }
        NSString *name = NSStringFromClass(v.class);
        if ([name hasPrefix:@"SAUI"] || [name isEqualToString:@"MGLiveBackdropView"]) return @"activity-present";
        [todo addObjectsFromArray:v.subviews];
    }
    if (todo.count) return @"scan-limit";
    // Empty AND explicitly hidden, matching the captured initial state.
    if (!content || !content.hidden || content.subviews.count) return @"content-not-empty-hidden";
    return @"idle";
}

static void Update(UIView *host) {
    if (InUpdate || !NSThread.isMainThread) return;
    InUpdate = YES;
    @try {
        NSString *state = Eligibility(host);
        BOOL show = [state isEqualToString:@"idle"];
        UIVisualEffectView *bg = objc_getAssociatedObject(host, &BackgroundKey);
        if (show && !bg) {
            bg = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
            bg.userInteractionEnabled = NO;
            bg.accessibilityElementsHidden = YES;
            bg.isAccessibilityElement = NO;
            bg.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
            bg.layer.borderWidth = 0.5;
            bg.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
            bg.layer.cornerCurve = kCACornerCurveContinuous;
            bg.clipsToBounds = YES;
            objc_setAssociatedObject(host, &BackgroundKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (show) {
            bg.frame = host.bounds;
            bg.layer.cornerRadius = host.bounds.size.height / 2.0;
            if (bg.superview != host) [host insertSubview:bg atIndex:0];
            bg.hidden = NO;
        } else {
            bg.hidden = YES;
            [bg removeFromSuperview];
        }
        NSString *old = objc_getAssociatedObject(host, &StateKey);
        if (![old isEqualToString:state]) {
            Log([NSString stringWithFormat:@"[STATE] host=%p state=%@ size=%.2fx%.2f background=%d", host, state, host.bounds.size.width, host.bounds.size.height, show]);
            objc_setAssociatedObject(host, &StateKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @finally { InUpdate = NO; }
}

static void Layout(id self, SEL cmd) {
    OriginalLayout(self, cmd);
    if (!NSThread.isMainThread) return;
    [Hosts addObject:self];
    Update(self);
}

static void Scan(void) {
    Disabled = access([[LogDir stringByAppendingPathComponent:@"DISABLED"] fileSystemRepresentation], F_OK) == 0;
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSetWithArray:UIApplication.sharedApplication.windows];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    for (UIWindow *w in windows) {
        if (![w isKindOfClass:WindowClass] || !w.userInteractionEnabled) continue;
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        NSUInteger count = 0;
        while (todo.count && count++ < 256) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if ([v isKindOfClass:HostClass]) { [Hosts addObject:v]; continue; }
            [todo addObjectsFromArray:v.subviews];
        }
    }
    for (UIView *host in Hosts.allObjects) Update(host);
}

__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            Log(@"[SESSION] version=0.1.0 background=UIKit-material touch=unchanged");
            HostClass = NSClassFromString(@"SBSystemApertureContainerView");
            WindowClass = NSClassFromString(@"SBSystemApertureWindow");
            ContentClass = NSClassFromString(@"_SBSystemApertureContainerViewContentView");
            if (!HostClass || !WindowClass || !ContentClass || !NSClassFromString(@"MGLiveBackdropView") || ![HostClass isSubclassOfClass:UIView.class] || ![WindowClass isSubclassOfClass:UIWindow.class] || ![ContentClass isSubclassOfClass:UIView.class]) {
                Log(@"[SKIP] expected-runtime-classes-unavailable"); return;
            }
            Method m = class_getInstanceMethod(HostClass, @selector(layoutSubviews));
            char ret[16] = {0};
            if (m) method_getReturnType(m, ret, sizeof(ret));
            if (!m || strcmp(ret, "v") || method_getNumberOfArguments(m) != 2) { Log(@"[SKIP] layout-signature-mismatch"); return; }
            Hosts = [NSHashTable weakObjectsHashTable];
            Disabled = access([[LogDir stringByAppendingPathComponent:@"DISABLED"] fileSystemRepresentation], F_OK) == 0;
            MSHookMessageEx(HostClass, @selector(layoutSubviews), (IMP)Layout, (IMP *)&OriginalLayout);
            Scan();
            Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(Timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC/2, NSEC_PER_MSEC*100);
            dispatch_source_set_event_handler(Timer, ^{ Scan(); });
            dispatch_resume(Timer);
            Log(@"[READY] hook=container-layout fallback-scan=500ms");
        });
    }
}
