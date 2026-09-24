#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>
#import <string.h>
#import <CoreFoundation/CoreFoundation.h>

// Names and Mango's initializer signature were confirmed in the supplied
// Beta7-1 Mach-O; all hooks/method calls are checked against runtime metadata.
@interface UIView (MangoIdleGlassInitializer)
- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)name filterType:(NSString *)filter;
- (void)setLgSpecularEnabledOverride:(id)value;
@end

static Class HostClass, WindowClass, ContentClass, ElementClass, GlassClass;
static void (*OriginalLayout)(id, SEL);
static void (*OriginalContentHidden)(id, SEL, BOOL);
static void (*OriginalElementMove)(id, SEL);
static void (*OriginalElementAlpha)(id, SEL, CGFloat);
static void (*OriginalGlassHidden)(id, SEL, BOOL);
static BOOL InUpdate, Disabled;
static NSHashTable<UIView *> *Hosts;
static dispatch_source_t Timer;
static CADisplayLink *DisplayLink;
static CFTimeInterval LastTransition;
static char BackgroundKey, StateKey, LastElementHostKey, GlassModeKey, OpaqueSinceKey;
static NSString * const LogDir = @"/var/mobile/Library/Logs/MangoIdleIsland";
static void Update(UIView *host);

@interface MangoIdleWeakHost : NSObject
@property (nonatomic, weak) UIView *view;
@end
@implementation MangoIdleWeakHost
@end

@interface MangoIdleFrameObserver : NSObject
- (void)tick:(CADisplayLink *)link;
@end

static void Pulse(void) {
    LastTransition = CACurrentMediaTime();
    DisplayLink.paused = NO;
}

@implementation MangoIdleFrameObserver
- (void)tick:(CADisplayLink *)link {
    if (CACurrentMediaTime() - LastTransition > 1.0) { link.paused = YES; return; }
    for (UIView *host in Hosts.allObjects) Update(host);
}
@end

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

static BOOL ClassMethodSignature(Class cls, SEL selector, const char *returnType, unsigned int argc, const char *firstExplicitArgument) {
    Method m = class_getInstanceMethod(cls, selector);
    if (!m || method_getNumberOfArguments(m) != argc) return NO;
    char ret[64] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (strcmp(ret, returnType)) return NO;
    if (firstExplicitArgument) {
        char arg[128] = {0};
        method_getArgumentType(m, 2, arg, sizeof(arg));
        if (arg[0] != firstExplicitArgument[0]) return NO;
    }
    return YES;
}

static BOOL MangoGlassSetting(void) {
    // Beta7-1 uses this exact preference key in its island configuration.
    // Absence/disabled => use UIKit fallback; never force an off feature on.
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.go.mangoosprefs.plist"];
    id value = prefs[@"PillGlass.Enabled"];
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

static BOOL GlassConstructorAvailable(void) {
    if (!GlassClass || ![GlassClass isSubclassOfClass:UIView.class]) return NO;
    const char *image = class_getImageName(GlassClass);
    if (!image || ![[NSString stringWithUTF8String:image] hasSuffix:@"/mangoos.dylib"]) return NO;
    SEL init = @selector(initWithFrame:groupName:filterType:);
    // Returns object, args: self, _cmd, CGRect, NSString *, NSString *.
    if (!ClassMethodSignature(GlassClass, init, "@", 5, "{")) return NO;
    return YES;
}

static UIView *CreateBackground(BOOL useMango, CGRect rect) {
    UIView *view = nil;
    if (useMango) {
        view = [[GlassClass alloc] initWithFrame:rect groupName:@"Island" filterType:@"go.mangoos.island"];
        if ([view isKindOfClass:GlassClass] && ClassMethodSignature(GlassClass, @selector(setLgSpecularEnabledOverride:), "v", 3, "@")) {
            [view setLgSpecularEnabledOverride:(__bridge id)kCFBooleanFalse];
        }
    }
    if (!view) {
        UIVisualEffectView *fallback = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        fallback.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
        fallback.layer.borderWidth = 0.5;
        fallback.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
        view = fallback;
    }
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
    view.isAccessibilityElement = NO;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    // The real activity MGLiveBackdropView had clips=0 in Probe.log;
    // its CABackdropLayer uses cornerRadius to shape its filters itself.
    view.clipsToBounds = !useMango;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    objc_setAssociatedObject(view, &GlassModeKey, @(useMango && [view isKindOfClass:GlassClass]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return view;
}

static CGFloat EffectiveOpacity(UIView *v, UIView *host) {
    CGFloat opacity = 1;
    for (UIView *p = v; p && p != host; p = p.superview) {
        if (p.hidden || p.layer.hidden) return 0;
        CALayer *layer = p.layer.presentationLayer ?: p.layer;
        opacity *= MIN(p.alpha, layer.opacity);
    }
    return MAX(0, MIN(1, opacity));
}

static NSString *Eligibility(UIView *host, CGFloat *activity) {
    *activity = 0;
    if (Disabled) return @"disabled";
    UIWindow *w = host.window;
    if (![w isKindOfClass:WindowClass] || !w.userInteractionEnabled) return @"window-excluded";
    if (!Visible(host)) return @"host-not-visible";
    CGSize size = host.bounds.size;
    // Allow an intermediate animated host to retain its backing while its
    // content fades away; never reposition or resize the system host itself.
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 100 || size.width > 350 || size.height < 28 || size.height > 145) return @"geometry-excluded";
    NSMutableArray<UIView *> *todo = [host.subviews mutableCopy];
    UIView *own = objc_getAssociatedObject(host, &BackgroundKey);
    NSUInteger count = 0;
    CGFloat elementOpacity = 0, glassOpacity = 0;
    BOOL foundGlass = NO;
    while (todo.count && count++ < 256) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        if (v == own) continue;
        if (ElementClass && [v isKindOfClass:ElementClass]) {
            elementOpacity = MAX(elementOpacity, EffectiveOpacity(v, host));
        }
        if (GlassClass && [v isKindOfClass:GlassClass]) {
            foundGlass = YES;
            if (!CGRectIsEmpty(v.bounds)) glassOpacity = MAX(glassOpacity, EffectiveOpacity(v, host));
        }
        [todo addObjectsFromArray:v.subviews];
    }
    if (todo.count) return @"scan-limit";
    // If the original glass exists but becomes hidden before the element is
    // detached, use the glass visibility for handoff, not the element alone.
    *activity = foundGlass ? glassOpacity : elementOpacity;
    return *activity > 0.01 ? @"activity" : @"background";
}

static void Update(UIView *host) {
    if (InUpdate || !NSThread.isMainThread) return;
    InUpdate = YES;
    @try {
        CGFloat activity = 0;
        NSString *state = Eligibility(host, &activity);
        BOOL eligible = [state isEqualToString:@"background"] || [state isEqualToString:@"activity"];
        UIView *bg = objc_getAssociatedObject(host, &BackgroundKey);
        if (eligible && !bg) {
            BOOL mango = MangoGlassSetting() && GlassConstructorAvailable();
            bg = CreateBackground(mango, host.bounds);
            if (bg) {
                objc_setAssociatedObject(host, &BackgroundKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                Log([NSString stringWithFormat:@"[BACKGROUND] kind=%@", mango ? @"Mango-glass" : @"UIKit-fallback"]);
            }
        }
        if (bg) {
            if (eligible) {
                if (bg.superview != host) [host insertSubview:bg atIndex:0];
                if (!CGRectEqualToRect(bg.frame, host.bounds)) bg.frame = host.bounds;
                CGFloat radius = host.bounds.size.height / 2.0;
                if (bg.layer.cornerRadius != radius) bg.layer.cornerRadius = radius;
                // A full-opacity element gets two frames of overlap so its
                // first committed frame can replace an already rendered pill.
                CFTimeInterval now = CACurrentMediaTime();
                NSNumber *since = objc_getAssociatedObject(host, &OpaqueSinceKey);
                if (activity < 0.98) { since = nil; objc_setAssociatedObject(host, &OpaqueSinceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
                else if (!since) { since = @(now); objc_setAssociatedObject(host, &OpaqueSinceKey, since, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
                CGFloat coverage = activity >= 0.98 && now - since.doubleValue < 0.06 ? 0 : activity;
                CGFloat backingOpacity = MAX(0, MIN(1, 1 - coverage));
                if (fabs(bg.alpha - backingOpacity) > 0.001) bg.alpha = backingOpacity;
                if (bg.hidden) bg.hidden = NO;
            } else {
                if (!bg.hidden) bg.hidden = YES;
                objc_setAssociatedObject(host, &OpaqueSinceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        NSString *old = objc_getAssociatedObject(host, &StateKey);
        if (![old isEqualToString:state]) {
            Pulse();
            Log([NSString stringWithFormat:@"[STATE] host=%p state=%@ size=%.2fx%.2f background=%.2f", (void *)host, state, host.bounds.size.width, host.bounds.size.height, bg.alpha]);
            objc_setAssociatedObject(host, &StateKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @finally { InUpdate = NO; }
}

static void Layout(id self, SEL cmd) {
    OriginalLayout(self, cmd);
    if (!NSThread.isMainThread) return;
    [Hosts addObject:self];
    Pulse();
    Update(self);
}

static UIView *HostFor(UIView *v) {
    for (UIView *p = v; p; p = p.superview) if ([p isKindOfClass:HostClass]) return p;
    return nil;
}

static void ContentHidden(id self, SEL cmd, BOOL hidden) {
    OriginalContentHidden(self, cmd, hidden);
    if (NSThread.isMainThread) {
        UIView *host = HostFor(self);
        if (host) { Pulse(); Update(host); }
    }
}

static void ElementMoved(id self, SEL cmd) {
    MangoIdleWeakHost *box = objc_getAssociatedObject(self, &LastElementHostKey);
    UIView *previous = box.view;
    OriginalElementMove(self, cmd);
    if (NSThread.isMainThread) {
        UIView *current = HostFor(self);
        if (!box) { box = [MangoIdleWeakHost new]; objc_setAssociatedObject(self, &LastElementHostKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        box.view = current;
        Pulse();
        if (previous) Update(previous);
        if (current && current != previous) Update(current);
    }
}

static void ElementAlpha(id self, SEL cmd, CGFloat alpha) {
    OriginalElementAlpha(self, cmd, alpha);
    if (NSThread.isMainThread) {
        UIView *host = HostFor(self);
        if (host) { Pulse(); Update(host); }
    }
}

static void GlassHidden(id self, SEL cmd, BOOL hidden) {
    OriginalGlassHidden(self, cmd, hidden);
    if (NSThread.isMainThread) {
        UIView *host = HostFor(self);
        if (host && objc_getAssociatedObject(host, &BackgroundKey) != self) { Pulse(); Update(host); }
    }
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
            Log(@"[SESSION] version=0.2.0 background=Mango-glass-if-enabled transition=backing-overlap touch=unchanged");
            HostClass = NSClassFromString(@"SBSystemApertureContainerView");
            WindowClass = NSClassFromString(@"SBSystemApertureWindow");
            ContentClass = NSClassFromString(@"_SBSystemApertureContainerViewContentView");
            ElementClass = NSClassFromString(@"SAUIElementView");
            GlassClass = NSClassFromString(@"MGLiveBackdropView");
            if (!HostClass || !WindowClass || !ContentClass || !ElementClass || !GlassClass || ![HostClass isSubclassOfClass:UIView.class] || ![WindowClass isSubclassOfClass:UIWindow.class] || ![ContentClass isSubclassOfClass:UIView.class] || ![ElementClass isSubclassOfClass:UIView.class]) {
                Log(@"[SKIP] expected-runtime-classes-unavailable"); return;
            }
            if (!ClassMethodSignature(HostClass, @selector(layoutSubviews), "v", 2, NULL) ||
                !ClassMethodSignature(ContentClass, @selector(setHidden:), "v", 3, "B") ||
                !ClassMethodSignature(ElementClass, @selector(didMoveToSuperview), "v", 2, NULL) ||
                !ClassMethodSignature(ElementClass, @selector(setAlpha:), "v", 3, "d") ||
                !ClassMethodSignature(GlassClass, @selector(setHidden:), "v", 3, "B")) {
                Log(@"[SKIP] transition-method-signature-mismatch"); return;
            }
            Hosts = [NSHashTable weakObjectsHashTable];
            Disabled = access([[LogDir stringByAppendingPathComponent:@"DISABLED"] fileSystemRepresentation], F_OK) == 0;
            MSHookMessageEx(HostClass, @selector(layoutSubviews), (IMP)Layout, (IMP *)&OriginalLayout);
            MSHookMessageEx(ContentClass, @selector(setHidden:), (IMP)ContentHidden, (IMP *)&OriginalContentHidden);
            MSHookMessageEx(ElementClass, @selector(didMoveToSuperview), (IMP)ElementMoved, (IMP *)&OriginalElementMove);
            MSHookMessageEx(ElementClass, @selector(setAlpha:), (IMP)ElementAlpha, (IMP *)&OriginalElementAlpha);
            MSHookMessageEx(GlassClass, @selector(setHidden:), (IMP)GlassHidden, (IMP *)&OriginalGlassHidden);
            Scan();
            Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(Timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC/2, NSEC_PER_MSEC*100);
            dispatch_source_set_event_handler(Timer, ^{ Scan(); });
            dispatch_resume(Timer);
            static MangoIdleFrameObserver *observer;
            observer = [MangoIdleFrameObserver new];
            DisplayLink = [CADisplayLink displayLinkWithTarget:observer selector:@selector(tick:)];
            DisplayLink.preferredFramesPerSecond = 30;
            [DisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            DisplayLink.paused = YES;
            Log(@"[READY] hooks=layout+content-hidden+element-move+element-alpha+glass-hidden transition-refresh=30fps/1s fallback-scan=500ms");
        });
    }
}
