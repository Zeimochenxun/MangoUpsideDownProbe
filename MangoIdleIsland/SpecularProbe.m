#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

@interface UIView (MangoIdleGlassProbe113)
- (instancetype)initWithFrame:(CGRect)frame groupName:(NSString *)name filterType:(NSString *)filter;
- (NSString *)lgFilterType;
- (void)updateSpecular;
@end

static id (*MIOriginalGlassInit)(id, SEL, CGRect, NSString *, NSString *);
static void (*MIOriginalUpdateSpecular)(id, SEL);
static NSString * const MIDomain = @"com.go.mangoosprefs";
static NSString * const MIIslandFilter = @"go.mangoos.island";
static NSString * const MILogDir = @"/var/mobile/Library/Logs/MangoIdleIsland";
static NSString * const MIProbeLogName = @"GlassProbe.log";
static char MIGroupKey, MIFilterKey, MIInitialFrameKey;
static BOOL MIHooksInstalled;

static void MIProbeLog(NSString *event) {
    struct stat st;
    const char *dir = MILogDir.fileSystemRepresentation;
    if (mkdir(dir, 0700) && lstat(dir, &st)) return;
    if (lstat(dir, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid()) return;
    NSString *path = [MILogDir stringByAppendingPathComponent:MIProbeLogName];
    int fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_NONBLOCK, 0600);
    if (fd < 0) return;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_nlink != 1) { close(fd); return; }
    if (st.st_size > 262144) { if (ftruncate(fd, 0)) { close(fd); return; } }
    NSData *line = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, event] dataUsingEncoding:NSUTF8StringEncoding];
    (void)write(fd, line.bytes, line.length);
    close(fd);
}

static BOOL MIExactVoidNoArgMethod(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char ret[16] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    return !strcmp(ret, "v");
}

static BOOL MIExactObjectNoArgMethod(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char ret[16] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    return ret[0] == '@';
}

static BOOL MIExactGlassInitializer(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(initWithFrame:groupName:filterType:));
    if (!m || method_getNumberOfArguments(m) != 5) return NO;
    char ret[32] = {0}, frameArg[128] = {0}, groupArg[32] = {0}, filterArg[32] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    method_getArgumentType(m, 2, frameArg, sizeof(frameArg));
    method_getArgumentType(m, 3, groupArg, sizeof(groupArg));
    method_getArgumentType(m, 4, filterArg, sizeof(filterArg));
    return ret[0] == '@' && frameArg[0] == '{' && groupArg[0] == '@' && filterArg[0] == '@';
}

static NSString *MIProbeObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar) return @"<missing>";
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return [NSString stringWithFormat:@"<non-object type=%s>", type ?: "?"];
    id value = object_getIvar(object, ivar);
    if (!value) return @"<nil>";
    if ([value isKindOfClass:CALayer.class]) {
        CALayer *layer = value;
        return [NSString stringWithFormat:@"<%@:%p hidden=%d opacity=%.3f mask=%p super=%p filters=%lu>",
                NSStringFromClass([value class]), (void *)value, layer.hidden, layer.opacity,
                (void *)layer.mask, (void *)layer.superlayer, (unsigned long)layer.filters.count];
    }
    if ([value isKindOfClass:UIView.class]) {
        UIView *view = value;
        return [NSString stringWithFormat:@"<%@:%p hidden=%d alpha=%.3f window=%p super=%p>",
                NSStringFromClass([value class]), (void *)value, view.hidden, view.alpha,
                (void *)view.window, (void *)view.superview];
    }
    return [NSString stringWithFormat:@"<%@:%p>", NSStringFromClass([value class]), (void *)value];
}

static NSString *MICurrentFilter(id object) {
    NSString *associated = objc_getAssociatedObject(object, &MIFilterKey);
    if (MIExactObjectNoArgMethod([object class], @selector(lgFilterType))) {
        @try {
            id current = [object lgFilterType];
            if ([current isKindOfClass:NSString.class]) return current;
        } @catch (__unused NSException *exception) {
        }
    }
    return [associated isKindOfClass:NSString.class] ? associated : nil;
}

static NSString *MIObjectContext(id object) {
    if (![object isKindOfClass:UIView.class]) {
        return [NSString stringWithFormat:@"class=%@ ptr=%p nonUIView=1", NSStringFromClass([object class]), (void *)object];
    }
    UIView *view = object;
    NSString *windowClass = view.window ? NSStringFromClass(view.window.class) : @"<nil>";
    NSString *superClass = view.superview ? NSStringFromClass(view.superview.class) : @"<nil>";
    return [NSString stringWithFormat:@"class=%@ ptr=%p frame=%.1f,%.1f,%.1f,%.1f bounds=%.1f,%.1f,%.1f,%.1f hidden=%d alpha=%.3f window=%@:%p super=%@:%p",
            NSStringFromClass(view.class), (void *)view,
            view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height,
            view.bounds.origin.x, view.bounds.origin.y, view.bounds.size.width, view.bounds.size.height,
            view.hidden, view.alpha,
            windowClass, (void *)view.window, superClass, (void *)view.superview];
}

static void MIRecordGlassState(id object, NSString *event) {
    if (!object) return;
    NSString *group = objc_getAssociatedObject(object, &MIGroupKey);
    NSString *initialFilter = objc_getAssociatedObject(object, &MIFilterKey);
    NSString *currentFilter = MICurrentFilter(object);
    NSValue *initialFrame = objc_getAssociatedObject(object, &MIInitialFrameKey);
    CGRect f = initialFrame ? initialFrame.CGRectValue : CGRectZero;
    BOOL island = [currentFilter isEqualToString:MIIslandFilter] || [initialFilter isEqualToString:MIIslandFilter];
    id enabled = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.SpecularEnabled"), (__bridge CFStringRef)MIDomain));
    id opacity = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.SpecularOpacity"), (__bridge CFStringRef)MIDomain));
    MIProbeLog([NSString stringWithFormat:@"[GLASS113-%@] %@ group=%@ initFilter=%@ filter=%@ island=%d initFrame=%.1f,%.1f,%.1f,%.1f main=%d prefEnabled=%@ prefOpacity=%@ _specular=%@ _boost=%@ _boostMask=%@ _dark=%@ _darkMask=%@ _mask=%@",
                event,
                MIObjectContext(object),
                group ?: @"<unknown>", initialFilter ?: @"<unknown>", currentFilter ?: @"<unknown>", island,
                f.origin.x, f.origin.y, f.size.width, f.size.height,
                NSThread.isMainThread,
                enabled ?: @"<nil>", opacity ?: @"<nil>",
                MIProbeObjectIvar(object, "_specular"), MIProbeObjectIvar(object, "_specularBoost"),
                MIProbeObjectIvar(object, "_specularBoostMask"), MIProbeObjectIvar(object, "_specularDark"),
                MIProbeObjectIvar(object, "_specularDarkMask"), MIProbeObjectIvar(object, "_specularMask")]);
}

static id MIInitGlass(id self, SEL cmd, CGRect frame, NSString *groupName, NSString *filterType) {
    id result = MIOriginalGlassInit(self, cmd, frame, groupName, filterType);
    if (!result) {
        MIProbeLog([NSString stringWithFormat:@"[GLASS113-INIT-NIL] class=%@ group=%@ filter=%@ frame=%.1f,%.1f,%.1f,%.1f",
                    NSStringFromClass([self class]), groupName ?: @"<nil>", filterType ?: @"<nil>",
                    frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]);
        return result;
    }

    if (groupName) objc_setAssociatedObject(result, &MIGroupKey, [groupName copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (filterType) objc_setAssociatedObject(result, &MIFilterKey, [filterType copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(result, &MIInitialFrameKey, [NSValue valueWithCGRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MIRecordGlassState(result, @"INIT");

    __weak id weakObject = result;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        id strongObject = weakObject;
        if (strongObject) MIRecordGlassState(strongObject, @"ATTACH100");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        id strongObject = weakObject;
        if (strongObject) MIRecordGlassState(strongObject, @"ATTACH500");
    });
    return result;
}

static void MIUpdateSpecular(id self, SEL cmd) {
    MIRecordGlassState(self, @"UPDATE-BEFORE");
    MIOriginalUpdateSpecular(self, cmd);
    MIRecordGlassState(self, @"UPDATE-AFTER");
}

static void MIScanExistingGlasses(Class cls) {
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSetWithArray:UIApplication.sharedApplication.windows];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    NSUInteger found = 0, visited = 0;
    for (UIWindow *window in windows) {
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:window];
        NSUInteger perWindow = 0;
        while (todo.count && perWindow++ < 512) {
            UIView *view = todo.lastObject;
            [todo removeLastObject];
            visited++;
            if ([view isKindOfClass:cls]) {
                found++;
                MIRecordGlassState(view, @"EXISTING");
            }
            [todo addObjectsFromArray:view.subviews];
        }
        if (todo.count) {
            MIProbeLog([NSString stringWithFormat:@"[GLASS113-SCAN-LIMIT] window=%@:%p visited=%lu remaining=%lu",
                        NSStringFromClass(window.class), (void *)window,
                        (unsigned long)perWindow, (unsigned long)todo.count]);
        }
    }
    MIProbeLog([NSString stringWithFormat:@"[GLASS113-SCAN] windows=%lu visited=%lu found=%lu",
                (unsigned long)windows.count, (unsigned long)visited, (unsigned long)found]);
}

static void MIInstallProbeAttempt(NSUInteger attempt) {
    if (MIHooksInstalled) return;
    Class cls = NSClassFromString(@"MGLiveBackdropView");
    if (!cls) {
        if (attempt < 6) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                MIInstallProbeAttempt(attempt + 1);
            });
        } else {
            MIProbeLog(@"[GLASS113] version=1.1.3-probe result=class-unavailable readonly=1");
        }
        return;
    }

    BOOL initOK = MIExactGlassInitializer(cls);
    BOOL updateOK = MIExactVoidNoArgMethod(cls, @selector(updateSpecular));
    if (!initOK || !updateOK) {
        MIProbeLog([NSString stringWithFormat:@"[GLASS113] version=1.1.3-probe result=signature-mismatch initializer=%d updateSpecular=%d readonly=1",
                    initOK, updateOK]);
        return;
    }

    MSHookMessageEx(cls, @selector(initWithFrame:groupName:filterType:), (IMP)MIInitGlass, (IMP *)&MIOriginalGlassInit);
    MSHookMessageEx(cls, @selector(updateSpecular), (IMP)MIUpdateSpecular, (IMP *)&MIOriginalUpdateSpecular);
    MIHooksInstalled = YES;
    MIProbeLog([NSString stringWithFormat:@"[GLASS113] version=1.1.3-probe hooks=initializer+updateSpecular scope=all-MGLiveBackdropView readonly=1 class=%@ module=%s",
                NSStringFromClass(cls), class_getImageName(cls) ?: "<unknown>"]);
    MIScanExistingGlasses(cls);
}

__attribute__((constructor)) static void MIInstallGlassProbe113(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            MIInstallProbeAttempt(0);
        });
    }
}
