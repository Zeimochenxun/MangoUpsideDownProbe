#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

@interface UIView (MangoIdleSpecularProbe)
- (NSString *)lgFilterType;
@end

static void (*MIOriginalUpdateSpecular)(id, SEL);
static NSString * const MIDomain = @"com.go.mangoosprefs";
static NSString * const MIIslandFilter = @"go.mangoos.island";
static NSString * const MILogDir = @"/var/mobile/Library/Logs/MangoIdleIsland";

static void MIProbeLog(NSString *event) {
    struct stat st;
    const char *dir = MILogDir.fileSystemRepresentation;
    if (mkdir(dir, 0700) && lstat(dir, &st)) return;
    if (lstat(dir, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid()) return;
    NSString *path = [MILogDir stringByAppendingPathComponent:@"Status.log"];
    int fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_NONBLOCK, 0600);
    if (fd < 0) return;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_nlink != 1) { close(fd); return; }
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

static BOOL MIIsIslandGlass(id object) {
    if (!object) return NO;
    Method m = class_getInstanceMethod([object class], @selector(lgFilterType));
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char ret[16] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (strcmp(ret, "@")) return NO;
    NSString *filter = [object lgFilterType];
    return [filter isKindOfClass:NSString.class] && [filter isEqualToString:MIIslandFilter];
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

static void MIRecordSpecularState(id self, NSString *phase) {
    if (!MIIsIslandGlass(self)) return;
    id enabled = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.SpecularEnabled"), (__bridge CFStringRef)MIDomain));
    id opacity = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Island.SpecularOpacity"), (__bridge CFStringRef)MIDomain));
    MIProbeLog([NSString stringWithFormat:@"[SPECULAR-PROBE] phase=%@ ptr=%p enabled=%@ opacity=%@ _specular=%@ _boost=%@ _boostMask=%@ _dark=%@ _darkMask=%@ _mask=%@",
                phase, (void *)self, enabled ?: @"<nil>", opacity ?: @"<nil>",
                MIProbeObjectIvar(self, "_specular"), MIProbeObjectIvar(self, "_specularBoost"),
                MIProbeObjectIvar(self, "_specularBoostMask"), MIProbeObjectIvar(self, "_specularDark"),
                MIProbeObjectIvar(self, "_specularDarkMask"), MIProbeObjectIvar(self, "_specularMask")]);
}

static void MIUpdateSpecular(id self, SEL cmd) {
    BOOL island = MIIsIslandGlass(self);
    if (island) MIRecordSpecularState(self, @"before-updateSpecular");
    MIOriginalUpdateSpecular(self, cmd);
    if (island) MIRecordSpecularState(self, @"after-updateSpecular");
}

__attribute__((constructor)) static void MIInstallSpecularProbe(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        if (os.majorVersion != 16 || os.minorVersion != 5 || os.patchVersion != 0) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 11 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            Class cls = NSClassFromString(@"MGLiveBackdropView");
            if (!cls || !MIExactVoidNoArgMethod(cls, @selector(updateSpecular))) {
                MIProbeLog(@"[GLASS] updateSpecular-probe=unavailable");
                return;
            }
            MSHookMessageEx(cls, @selector(updateSpecular), (IMP)MIUpdateSpecular, (IMP *)&MIOriginalUpdateSpecular);
            MIProbeLog(@"[GLASS] updateSpecular-probe=installed readonly");
        });
    }
}
