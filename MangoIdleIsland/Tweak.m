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
#import <roothide.h>

// Beta7-1 runtime surface verified against the supplied Mango binaries.
// Every optional Mango method is signature-gated before it is hooked/called.
@interface UIView (MangoIdleGlassInitializer)
- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)name filterType:(NSString *)filter;
- (void)setLgSpecularEnabledOverride:(id)value;
- (NSString *)lgFilterType;
- (id)lgSpecularEnabledOverride;
- (void)reapplyFilterForParameterReload;
- (void)updateSpecular;
@end

static Class HostClass, WindowClass, ContentClass, ElementClass, GlassClass;
static void (*OriginalLayout)(id, SEL);
static void (*OriginalContentHidden)(id, SEL, BOOL);
static void (*OriginalElementMove)(id, SEL);
static void (*OriginalElementAlpha)(id, SEL, CGFloat);
static void (*OriginalGlassHidden)(id, SEL, BOOL);
static void (*OriginalSpecularOverride)(id, SEL, id);
static void (*OriginalParameterReapply)(id, SEL);
static void (*OriginalUpdateSpecular)(id, SEL);

static BOOL InUpdate, Disabled, OriginalIslandGlassSeen, GlassConstructorVerified, GlassConstructionFailed, CachedGlassSetting;
static BOOL ParameterReapplyHookInstalled;
static CFTimeInterval LastPreferenceRead;
static NSHashTable<UIView *> *Hosts;
static dispatch_source_t Timer;
static CADisplayLink *DisplayLink;
static CFTimeInterval LastTransition;
static uint64_t ParameterReloadGeneration;
static char BackgroundKey, StateKey, LastElementHostKey, GlassModeKey, OpaqueSinceKey, LastParameterReapplyKey, EdgeAttemptKey, EdgeSeenKey;

static NSString * const MangoDomain = @"com.go.mangoosprefs";
static NSString * const IslandFilterType = @"go.mangoos.island";
static NSString * const LogDir = @"/var/mobile/Library/Logs/MangoIdleIsland";

static void Update(UIView *host);
static void Pulse(void);
static void Log(NSString *event);
static UIView *HostFor(UIView *v);
static BOOL ClassMethodSignature(Class cls, SEL selector, const char *returnType, unsigned int argc, const char *firstExplicitArgument);

static BOOL IslandEdgeOptIn(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)MangoDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.SpecularEnabled"), (__bridge CFStringRef)MangoDomain));
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

static BOOL IsIslandGlass(id object) {
    // Mango Beta7 contains this class in both mango.dylib and mangoos.dylib.
    // Check the actual object's class and image, rather than assuming the
    // NSClassFromString winner is also the class of the active glass.
    Class cls = object ? object_getClass(object) : Nil;
    if (!cls || ![NSStringFromClass(cls) isEqualToString:@"MGLiveBackdropView"]) return NO;
    const char *image = class_getImageName(cls);
    NSString *module = image ? [[NSString stringWithUTF8String:image] lastPathComponent] : nil;
    if (![module isEqualToString:@"mango.dylib"] && ![module isEqualToString:@"mangoos.dylib"]) return NO;
    if (!ClassMethodSignature(cls, @selector(lgFilterType), "@", 2, NULL)) return NO;
    return [[object lgFilterType] isEqualToString:IslandFilterType];
}

static void EnsureActiveEdge(UIView *glass) {
    if (Disabled || !glass.window || CGRectIsEmpty(glass.bounds) || !IslandEdgeOptIn()) return;
    Class cls = object_getClass(glass);
    if (!ClassMethodSignature(cls, @selector(lgSpecularEnabledOverride), "@", 2, NULL) ||
        !ClassMethodSignature(cls, @selector(setLgSpecularEnabledOverride:), "v", 3, "@")) return;
    id value = [glass lgSpecularEnabledOverride];
    if (!objc_getAssociatedObject(glass, &EdgeSeenKey)) {
        objc_setAssociatedObject(glass, &EdgeSeenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Log([NSString stringWithFormat:@"[EDGE-ACTIVE] observed class=%p module=%s override=%@ size=%.1fx%.1f",
             (void *)cls, class_getImageName(cls) ?: "?", value ?: @"nil", glass.bounds.size.width, glass.bounds.size.height]);
    }
    if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) return;
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *last = objc_getAssociatedObject(glass, &EdgeAttemptKey);
    if (last && now - last.doubleValue < 1.0) return;
    objc_setAssociatedObject(glass, &EdgeAttemptKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [glass setLgSpecularEnabledOverride:(__bridge id)kCFBooleanTrue];
    Log([NSString stringWithFormat:@"[EDGE-ACTIVE] corrected class=%p before=%@ after=%@",
         (void *)cls, value ?: @"nil", [glass lgSpecularEnabledOverride] ?: @"nil"]);
}

static void SpecularOverride(id self, SEL cmd, id value) {
    // Beta7 Active Island can install its own @NO override after the shared
    // Island preference has already enabled specular. 1.1.0 changed @NO to
    // nil, but device testing proved nil still follows the Active default-off
    // path. For Island glass only, make the user's explicit preference the
    // authoritative override: @YES when enabled, @NO when disabled.
    if (!Disabled && IsIslandGlass(self)) {
        BOOL enabled = IslandEdgeOptIn();
        value = enabled ? (__bridge id)kCFBooleanTrue : (__bridge id)kCFBooleanFalse;
        Log([NSString stringWithFormat:@"[SPECULAR] ptr=%p intercepted=1 forced=%@",
             (void *)self, enabled ? @"YES" : @"NO"]);
    }
    OriginalSpecularOverride(self, cmd, value);
}

static NSString *ProbeIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar) return @"<missing>";
    id value = object_getIvar(object, ivar);
    if (!value) return @"<nil>";
    if ([value isKindOfClass:[CALayer class]]) {
        CALayer *layer = value;
        return [NSString stringWithFormat:@"<%@:%p hidden=%d opacity=%.3f mask=%p super=%p filters=%lu>", NSStringFromClass([value class]), (void *)value, layer.hidden, layer.opacity, (void *)layer.mask, (void *)layer.superlayer, (unsigned long)layer.filters.count];
    }
    if ([value isKindOfClass:[UIView class]]) {
        UIView *view = value;
        return [NSString stringWithFormat:@"<%@:%p hidden=%d alpha=%.3f window=%p super=%p>", NSStringFromClass([value class]), (void *)value, view.hidden, view.alpha, (void *)view.window, (void *)view.superview];
    }
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([value class]), (void *)value, value];
}

static void LogSpecularProbe(id self, NSString *phase) {
    if (!IsIslandGlass(self)) return;
    id enabled = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.SpecularEnabled"), (__bridge CFStringRef)MangoDomain));
    id opacity = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.SpecularOpacity"), (__bridge CFStringRef)MangoDomain));
    Log([NSString stringWithFormat:@"[SPECULAR-PROBE] phase=%@ ptr=%p enabled=%@ opacity=%@ _specular=%@ _boost=%@ _boostMask=%@ _dark=%@ _darkMask=%@ _mask=%@",
         phase, (void *)self, enabled ?: @"<nil>", opacity ?: @"<nil>",
         ProbeIvar(self, "_specular"), ProbeIvar(self, "_specularBoost"), ProbeIvar(self, "_specularBoostMask"),
         ProbeIvar(self, "_specularDark"), ProbeIvar(self, "_specularDarkMask"), ProbeIvar(self, "_specularMask")]);
}

static void UpdateSpecularProbe(id self, SEL cmd) {
    BOOL island = IsIslandGlass(self);
    if (island) LogSpecularProbe(self, @"before-updateSpecular");
    OriginalUpdateSpecular(self, cmd);
    if (island) LogSpecularProbe(self, @"after-updateSpecular");
}

static void ParameterReapply(id self, SEL cmd) {
    OriginalParameterReapply(self, cmd);
    if (IsIslandGlass(self)) {
        objc_setAssociatedObject(self, &LastParameterReapplyKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static NSMutableOrderedSet<UIView *> *CollectIslandGlasses(void) {
    NSMutableOrderedSet<UIView *> *result = [NSMutableOrderedSet orderedSet];
    for (UIView *host in Hosts.allObjects) {
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:host];
        NSUInteger count = 0;
        while (todo.count && count++ < 256) {
            UIView *v = todo.lastObject;
            [todo removeLastObject];
            if (IsIslandGlass(v)) [result addObject:v];
            [todo addObjectsFromArray:v.subviews];
        }
    }
    return result;
}

static BOOL IsIdleOwnedGlass(UIView *glass, UIView **hostOut) {
    UIView *host = HostFor(glass);
    if (hostOut) *hostOut = host;
    return host && objc_getAssociatedObject(host, &BackgroundKey) == glass;
}

static void LogIslandGlass(UIView *glass, NSString *owner, UIView *host) {
    NSString *filter = IsIslandGlass(glass) ? [glass lgFilterType] : @"(non-island)";
    Log([NSString stringWithFormat:@"[ISLAND-GLASS] owner=%@ class=%@ ptr=%p filterType=%@ window=%p host=%p alpha=%.3f hidden=%d idle-owned=%d",
         owner,
         NSStringFromClass(glass.class),
         (void *)glass,
         filter ?: @"(nil)",
         (void *)glass.window,
         (void *)host,
         glass.alpha,
         glass.hidden,
         [owner isEqualToString:@"idle"]]);
}

static void RefreshActiveIslandGlass(UIView *glass, CFTimeInterval eventTime) {
    // Keep Mango's active MGLiveBackdropView instance and lifecycle intact.
    // Only update the Island-only specular override and use Mango's own
    // reapply selector when its normal ParametersReloaded observer did not.
    BOOL edgeEnabled = IslandEdgeOptIn();
    if (ClassMethodSignature(GlassClass, @selector(setLgSpecularEnabledOverride:), "v", 3, "@")) {
        [glass setLgSpecularEnabledOverride:edgeEnabled ? (__bridge id)kCFBooleanTrue : (__bridge id)kCFBooleanFalse];
    }

    NSNumber *last = objc_getAssociatedObject(glass, &LastParameterReapplyKey);
    BOOL observed = last && last.doubleValue >= eventTime - 0.15;
    if (observed) {
        Log([NSString stringWithFormat:@"[GLASS-REFRESH] owner=active ptr=%p method=reapplyFilterForParameterReload result=observed-mango-refresh", (void *)glass]);
        return;
    }

    if (ParameterReapplyHookInstalled && ClassMethodSignature(GlassClass, @selector(reapplyFilterForParameterReload), "v", 2, NULL)) {
        [glass reapplyFilterForParameterReload];
        Log([NSString stringWithFormat:@"[GLASS-REFRESH] owner=active ptr=%p method=reapplyFilterForParameterReload result=invoked-fallback", (void *)glass]);
    } else {
        Log([NSString stringWithFormat:@"[GLASS-REFRESH] owner=active ptr=%p result=no-safe-runtime-refresh", (void *)glass]);
    }
}

static void ParametersChanged(CFTimeInterval eventTime, uint64_t generation) {
    if (!NSThread.isMainThread || !Hosts || Disabled || generation != ParameterReloadGeneration) return;

    LastPreferenceRead = 0;
    NSMutableOrderedSet<UIView *> *islandGlasses = CollectIslandGlasses();
    NSUInteger idleCount = 0, activeCount = 0;
    NSMutableArray<UIView *> *active = [NSMutableArray array];

    for (UIView *glass in islandGlasses) {
        UIView *host = nil;
        BOOL idleOwned = IsIdleOwnedGlass(glass, &host);
        NSString *owner = idleOwned ? @"idle" : @"active";
        if (idleOwned) idleCount++; else { activeCount++; [active addObject:glass]; }
        LogIslandGlass(glass, owner, host);
    }

    Log([NSString stringWithFormat:@"[PARAMETERS] generation=%llu island-glass-count=%lu idle=%lu active=%lu",
         (unsigned long long)generation,
         (unsigned long)islandGlasses.count,
         (unsigned long)idleCount,
         (unsigned long)activeCount]);

    // Active instances belong to Mango. Never remove or recreate them.
    for (UIView *glass in active) RefreshActiveIslandGlass(glass, eventTime);

    // Beta7's in-place reapply is not reliable for our idle copy (notably
    // Blur may disappear until reconstruction). Rebuild only the view owned
    // by MangoIdleIsland using the same verified Island initializer.
    NSUInteger rebuilt = 0;
    for (UIView *host in Hosts.allObjects) {
        UIView *bg = objc_getAssociatedObject(host, &BackgroundKey);
        if (bg) {
            objc_setAssociatedObject(host, &BackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(host, &OpaqueSinceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [bg removeFromSuperview];
            rebuilt++;
            Log([NSString stringWithFormat:@"[GLASS-REFRESH] owner=idle ptr=%p method=fresh-init result=rebuilt", (void *)bg]);
        }
        Update(host);
    }
    Pulse();
    Log([NSString stringWithFormat:@"[PARAMETERS] rebuilt-idle=%lu mode=global-island-native-reapply+idle-fresh-init", (unsigned long)rebuilt]);
}

static void MangoReload(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    CFTimeInterval eventTime = CACurrentMediaTime();
    uint64_t generation = ++ParameterReloadGeneration;
    Log([NSString stringWithFormat:@"[PARAMETERS] notification=go.mangoos/ParametersReloaded generation=%llu", (unsigned long long)generation]);

    // MangoOSRendering's verified chain reloads its preference cache before
    // publishing ParametersReloaded. Give all Mango observers one main-loop
    // turn; coalescing also prevents rapid UI changes from rebuilding Idle
    // glass repeatedly.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        ParametersChanged(eventTime, generation);
    });
}

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
    CFTimeInterval now = CACurrentMediaTime();
    if (LastPreferenceRead && now - LastPreferenceRead < 5.0) return CachedGlassSetting;
    LastPreferenceRead = now;
    NSString *path = @"/var/mobile/Library/Preferences/com.go.mangoosprefs.plist";
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:jbroot(path)];
    if (!prefs) prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    id value = prefs[@"PillGlass.Enabled"];
    if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) { CachedGlassSetting = YES; return YES; }
    id mainValue = [NSUserDefaults.standardUserDefaults objectForKey:@"MangoPillGlassEnabled"];
    CachedGlassSetting = [mainValue respondsToSelector:@selector(boolValue)] && [mainValue boolValue];
    return CachedGlassSetting;
}

static NSString *GlassConstructorIssue(void) {
    if (!GlassClass || ![GlassClass isSubclassOfClass:UIView.class]) return @"class-not-UIView";
    const char *image = class_getImageName(GlassClass);
    if (!image) return @"missing-image";
    NSString *name = [[NSString stringWithUTF8String:image] lastPathComponent];
    if (![name isEqualToString:@"mango.dylib"] && ![name isEqualToString:@"mangoos.dylib"]) return @"image-not-mango";
    SEL init = @selector(initWithFrame:groupName:filterType:);
    if (!ClassMethodSignature(GlassClass, init, "@", 5, "{")) return @"initializer-signature-mismatch";
    return nil;
}

static UIView *CreateBackground(BOOL useMango, CGRect rect) {
    UIView *view = nil;
    if (useMango) {
        view = [[GlassClass alloc] initWithFrame:rect groupName:@"Island" filterType:IslandFilterType];
        if (!view || ![view isKindOfClass:GlassClass]) {
            GlassConstructionFailed = YES;
            Log(@"[GLASS] construction-failed-using-UIKit-until-respring");
            view = nil;
        }
        if ([view isKindOfClass:GlassClass] && ClassMethodSignature(GlassClass, @selector(setLgSpecularEnabledOverride:), "v", 3, "@")) {
            [view setLgSpecularEnabledOverride:IslandEdgeOptIn() ? (__bridge id)kCFBooleanTrue : (__bridge id)kCFBooleanFalse];
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
    BOOL actualMangoGlass = useMango && [view isKindOfClass:GlassClass];
    view.clipsToBounds = !actualMangoGlass;
    view.autoresizingMask = UIViewAutoresizingNone;
    objc_setAssociatedObject(view, &GlassModeKey, @(actualMangoGlass), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return view;
}

static CGFloat EffectiveOpacity(UIView *v, UIView *host) {
    CGFloat opacity = 1;
    for (UIView *p = v; p && p != host; p = p.superview) {
        if (p.hidden || p.layer.hidden) return 0;
        CALayer *layer = p.layer.presentationLayer ?: p.layer;
        // During a fade, the presentation layer is the currently visible
        // value. The model alpha is already the destination of the animation.
        opacity *= layer.opacity;
    }
    return MAX(0, MIN(1, opacity));
}

static BOOL StableIdleGeometry(CGSize size) {
    // Device logs show stable compact Island geometries around 125x36.67,
    // 129x38, 133x39.33 and 137.67x40.67. Long-press preview is 150x44.
    // Keep the supplemental glass strictly on the compact side of that split.
    return isfinite(size.width) && isfinite(size.height) &&
           size.width >= 110.0 && size.width <= 145.0 &&
           size.height >= 28.0 && size.height <= 45.0;
}

static BOOL StableIdleHostGeometry(UIView *host) {
    CGSize model = host.bounds.size;
    if (!StableIdleGeometry(model)) return NO;
    CALayer *presentation = host.layer.presentationLayer;
    if (!presentation) return YES;
    CGSize visible = presentation.bounds.size;
    // Content can dismiss before compact bounds reach their final size.
    // Restore backing once both sizes are compact; expanded model or
    // presentation bounds remain excluded by the compact geometry gates.
    return StableIdleGeometry(visible);
}

static NSString *Eligibility(UIView *host, CGFloat *activity, CGFloat *elementOpacityOut, CGFloat *glassOpacityOut) {
    *activity = 0;
    *elementOpacityOut = 0;
    *glassOpacityOut = 0;
    if (Disabled) return @"disabled";
    UIWindow *w = host.window;
    if (![w isKindOfClass:WindowClass] || !w.userInteractionEnabled) return @"window-excluded";
    if (!Visible(host)) return @"host-not-visible";
    CGSize size = host.bounds.size;
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 100 || size.width > 350 || size.height < 28 || size.height > 145) return @"geometry-excluded";
    BOOL stableIdleGeometry = StableIdleHostGeometry(host);
    NSMutableArray<UIView *> *todo = [host.subviews mutableCopy];
    UIView *own = objc_getAssociatedObject(host, &BackgroundKey);
    NSUInteger count = 0;
    CGFloat elementOpacity = 0, glassOpacity = 0;
    while (todo.count && count++ < 256) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        if (v == own) continue;
        if (ElementClass && [v isKindOfClass:ElementClass]) elementOpacity = MAX(elementOpacity, EffectiveOpacity(v, host));
        // Keep active-Island edge/specular maintenance independent of the idle
        // geometry gate. We still observe native glass throughout transitions.
        if (IsIslandGlass(v)) {
            EnsureActiveEdge(v);
            if (!CGRectIsEmpty(v.bounds)) {
                CGFloat realOpacity = EffectiveOpacity(v, host);
                glassOpacity = MAX(glassOpacity, realOpacity);
                if (realOpacity > 0.01 && !OriginalIslandGlassSeen) {
                    OriginalIslandGlassSeen = YES;
                    Log(@"[GLASS] original-island-glass-observed");
                }
            }
        }
        [todo addObjectsFromArray:v.subviews];
    }
    *elementOpacityOut = elementOpacity;
    *glassOpacityOut = glassOpacity;
    if (todo.count) return @"scan-limit";

    *activity = MAX(glassOpacity, elementOpacity);
    if (*activity > 0.01) return @"activity";
    // A no-content geometry such as 150x44 is a press/preview transition, not
    // idle. Never keep an independent supplemental glass in that animation.
    return stableIdleGeometry ? @"background" : @"transition";
}

static void Update(UIView *host) {
    if (InUpdate || !NSThread.isMainThread) return;
    InUpdate = YES;
    @try {
        CGFloat activity = 0, elementOpacity = 0, glassOpacity = 0;
        NSString *state = Eligibility(host, &activity, &elementOpacity, &glassOpacity);
        BOOL stableGeometry = StableIdleHostGeometry(host);
        BOOL backgroundState = [state isEqualToString:@"background"];
        BOOL activityState = [state isEqualToString:@"activity"];
        BOOL blendableActivity = activityState && stableGeometry;

        UIView *bg = objc_getAssociatedObject(host, &BackgroundKey);
        // During a compact activity fade, allow the Idle glass to exist only as
        // the inverse-opacity backing layer. Outside compact geometry it exits
        // immediately and never participates in press/preview motion.
        BOOL needBackground = backgroundState || (blendableActivity && activity < 0.995);
        BOOL constructor = needBackground && GlassConstructorVerified && !GlassConstructionFailed;
        BOOL mango = constructor && (OriginalIslandGlassSeen || MangoGlassSetting());
        BOOL upgrading = needBackground && bg && mango && ![objc_getAssociatedObject(bg, &GlassModeKey) boolValue];

        if (needBackground && (!bg || upgrading)) {
            UIView *old = bg;
            bg = CreateBackground(mango, host.bounds);
            if (bg) {
                objc_setAssociatedObject(host, &BackgroundKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [old removeFromSuperview];
                BOOL realGlass = [objc_getAssociatedObject(bg, &GlassModeKey) boolValue];
                Log([NSString stringWithFormat:@"[BACKGROUND] kind=%@ source=%@ constructor=%d upgraded=%d",
                     realGlass ? @"Mango-glass" : @"UIKit-fallback",
                     OriginalIslandGlassSeen ? @"observed" : (mango ? @"setting" : @"fallback"), constructor, upgrading]);
            }
        }

        if (bg) {
            if (backgroundState || (blendableActivity && activity < 0.995)) {
                CGFloat backingOpacity = backgroundState ? 1.0 : MAX(0, MIN(1, 1 - activity));
                [UIView performWithoutAnimation:^{
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    if (bg.superview != host) [host insertSubview:bg atIndex:0];
                    bg.frame = host.bounds;
                    bg.layer.cornerRadius = host.bounds.size.height / 2.0;
                    bg.alpha = backingOpacity;
                    bg.hidden = NO;
                    [CATransaction commit];
                }];
            } else {
                // Preview/expanded geometry and fully established activity are
                // exclusively native/Mango-owned. Do not animate our independent
                // Idle glass alongside them.
                [UIView performWithoutAnimation:^{
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    bg.hidden = YES;
                    [bg removeFromSuperview];
                    [CATransaction commit];
                }];
            }
        }

        NSString *old = objc_getAssociatedObject(host, &StateKey);
        if (![old isEqualToString:state]) {
            Pulse();
            CALayer *presentation = host.layer.presentationLayer;
            CGSize presentationSize = presentation ? presentation.bounds.size : host.bounds.size;
            Log([NSString stringWithFormat:@"[STATE] host=%p state=%@ stable=%d activity=%.3f size=%.2fx%.2f presentation=%.2fx%.2f hasPresentation=%d elementOpacity=%.3f glassOpacity=%.3f background=%.3f bgAttached=%d bgHidden=%d",
                 (void *)host, state, stableGeometry, activity,
                 host.bounds.size.width, host.bounds.size.height,
                 presentationSize.width, presentationSize.height, presentation != nil,
                 elementOpacity, glassOpacity, bg ? bg.alpha : 0.0,
                 bg.superview == host, bg ? bg.hidden : YES]);
            objc_setAssociatedObject(host, &StateKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @finally {
        InUpdate = NO;
    }
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
        if (!box) {
            box = [MangoIdleWeakHost new];
            objc_setAssociatedObject(self, &LastElementHostKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
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
    if (NSThread.isMainThread && IsIslandGlass(self)) {
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
            Log(@"[SESSION] version=1.1.9.2~alpha2-stable-idle-handoff background=Mango-glass stable-idle-only=1 inverse-native-opacity=1 presentation-opacity=1 presentation-bounds-guard=1 compact-return-handoff=1 activity-detaches-idle touch=unchanged");
            HostClass = NSClassFromString(@"SBSystemApertureContainerView");
            WindowClass = NSClassFromString(@"SBSystemApertureWindow");
            ContentClass = NSClassFromString(@"_SBSystemApertureContainerViewContentView");
            ElementClass = NSClassFromString(@"SAUIElementView");
            GlassClass = NSClassFromString(@"MGLiveBackdropView");

            if (!HostClass || !WindowClass || !ContentClass || !ElementClass || !GlassClass ||
                ![HostClass isSubclassOfClass:UIView.class] || ![WindowClass isSubclassOfClass:UIWindow.class] ||
                ![ContentClass isSubclassOfClass:UIView.class] || ![ElementClass isSubclassOfClass:UIView.class]) {
                Log(@"[SKIP] expected-runtime-classes-unavailable");
                return;
            }
            if (!ClassMethodSignature(HostClass, @selector(layoutSubviews), "v", 2, NULL) ||
                !ClassMethodSignature(ContentClass, @selector(setHidden:), "v", 3, "B") ||
                !ClassMethodSignature(ElementClass, @selector(didMoveToSuperview), "v", 2, NULL) ||
                !ClassMethodSignature(ElementClass, @selector(setAlpha:), "v", 3, "d") ||
                !ClassMethodSignature(GlassClass, @selector(setHidden:), "v", 3, "B")) {
                Log(@"[SKIP] transition-method-signature-mismatch");
                return;
            }

            NSString *glassIssue = GlassConstructorIssue();
            GlassConstructorVerified = !glassIssue;
            Log([NSString stringWithFormat:@"[GLASS] constructor-verified=%d reason=%@ module=%s",
                 GlassConstructorVerified, glassIssue ?: @"none", class_getImageName(GlassClass) ?: "(unknown)"]);

            Hosts = [NSHashTable weakObjectsHashTable];
            Disabled = access([[LogDir stringByAppendingPathComponent:@"DISABLED"] fileSystemRepresentation], F_OK) == 0;

            MSHookMessageEx(HostClass, @selector(layoutSubviews), (IMP)Layout, (IMP *)&OriginalLayout);
            MSHookMessageEx(ContentClass, @selector(setHidden:), (IMP)ContentHidden, (IMP *)&OriginalContentHidden);
            MSHookMessageEx(ElementClass, @selector(didMoveToSuperview), (IMP)ElementMoved, (IMP *)&OriginalElementMove);
            MSHookMessageEx(ElementClass, @selector(setAlpha:), (IMP)ElementAlpha, (IMP *)&OriginalElementAlpha);
            MSHookMessageEx(GlassClass, @selector(setHidden:), (IMP)GlassHidden, (IMP *)&OriginalGlassHidden);

            if (GlassConstructorVerified &&
                ClassMethodSignature(GlassClass, @selector(lgFilterType), "@", 2, NULL) &&
                ClassMethodSignature(GlassClass, @selector(setLgSpecularEnabledOverride:), "v", 3, "@")) {
                MSHookMessageEx(GlassClass, @selector(setLgSpecularEnabledOverride:), (IMP)SpecularOverride, (IMP *)&OriginalSpecularOverride);
                Log(@"[GLASS] edge-override-hook=installed island-only explicit-boolean");
            }

            if (GlassConstructorVerified &&
                ClassMethodSignature(GlassClass, @selector(reapplyFilterForParameterReload), "v", 2, NULL)) {
                MSHookMessageEx(GlassClass, @selector(reapplyFilterForParameterReload), (IMP)ParameterReapply, (IMP *)&OriginalParameterReapply);
                ParameterReapplyHookInstalled = YES;
                Log(@"[GLASS] parameter-reapply-hook=installed island-observer");
            } else {
                Log(@"[GLASS] parameter-reapply-hook=unavailable");
            }

            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MangoReload,
                                            CFSTR("go.mangoos/ParametersReloaded"), NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);

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

            Log(@"[READY] hooks=layout+content-hidden+element-move+element-alpha+glass-hidden+island-reapply transition-refresh=30fps/1s fallback-scan=500ms global-Island-glass-logic=enabled");
        });
    }
}
