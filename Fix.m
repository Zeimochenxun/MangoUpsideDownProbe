#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>

static NSString * const kVersion = @"0.1.0-alpha1";
static NSString * const kLogDirectory = @"/var/mobile/Library/Logs/MangoSplitUpsideDownFix";
static NSString * const kLogPath = @"/var/mobile/Library/Logs/MangoSplitUpsideDownFix/Fix.log";
static NSString * const kDisablePath = @"/var/mobile/Library/Preferences/MangoSplitUpsideDownFix.disabled";
static NSString * const kPackagedMangoUUID = @"699ea8ae-c032-386e-b62d-f92fbff2a889";
static NSString * const kInstalledMangoUUID = @"67c0d7c2-4487-3fd2-9535-067745ae4b8f";

static dispatch_queue_t gLogQueue;
static NSString *gSessionID;
static NSHashTable<UIWindow *> *gMangoWindows;
static NSHashTable<UIWindow *> *gRefusedWindows;
static BOOL gReady;
static NSInteger gLastOrientation = NSIntegerMin;

static BOOL TransformNear(CGAffineTransform a, CGAffineTransform b) {
    const CGFloat e = 0.002;
    return fabs(a.a-b.a)<e && fabs(a.b-b.b)<e && fabs(a.c-b.c)<e &&
           fabs(a.d-b.d)<e && fabs(a.tx-b.tx)<e && fabs(a.ty-b.ty)<e;
}

static void AppendLine(NSString *line) {
    if (!line) return;
    NSString *owned = [line copy];
    dispatch_async(gLogQueue, ^{
        NSData *data = [[owned stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        int fd = open(kLogPath.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW, 0600);
        if (fd < 0) return;
        const uint8_t *p = data.bytes;
        NSUInteger left = data.length;
        while (left) {
            ssize_t n = write(fd, p, left);
            if (n <= 0) break;
            p += n;
            left -= (NSUInteger)n;
        }
        close(fd);
    });
}

static void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    AppendLine([NSString stringWithFormat:@"%.3f session=%@ %@", NSDate.date.timeIntervalSince1970,
                gSessionID ?: @"uninitialized", body]);
}

static NSString *UUIDForImageBase(const void *base) {
    if (!base) return nil;
    const struct mach_header_64 *header = base;
    if (header->magic != MH_MAGIC_64) return nil;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    for (uint32_t i=0; i<header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command)) return nil;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const uint8_t *b = ((const struct uuid_command *)command)->uuid;
            return [NSString stringWithFormat:
                @"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]];
        }
        cursor += command->cmdsize;
    }
    return nil;
}

static BOOL VerifyMango(NSString **pathOut, NSString **uuidOut) {
    Class cls = objc_getClass("MangoPillElement");
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName("handlePanGesture:")) : Nil;
    if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@16") != 0) return NO;
    Dl_info info = {0};
    if (!dladdr((const void *)method_getImplementation(method), &info) || !info.dli_fname) return NO;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    NSString *uuid = UUIDForImageBase(info.dli_fbase).lowercaseString;
    if (pathOut) *pathOut = path;
    if (uuidOut) *uuidOut = uuid;
    BOOL correctImage = [path.lastPathComponent caseInsensitiveCompare:@"mango.dylib"] == NSOrderedSame;
    BOOL correctUUID = [uuid isEqualToString:kInstalledMangoUUID] || [uuid isEqualToString:kPackagedMangoUUID];
    return correctImage && correctUUID;
}

static NSInteger MangoOrientation(void) {
    Class cls = objc_getClass("DecoratedAppSceneView");
    SEL sel = sel_registerName("mango_currentInterfaceOrientation");
    Method method = cls ? class_getClassMethod(cls, sel) : Nil;
    if (!method || strcmp(method_getTypeEncoding(method), "q16@0:8") != 0) return UIInterfaceOrientationUnknown;
    return ((NSInteger(*)(id,SEL))objc_msgSend)(cls, sel);
}

static BOOL ContainsMangoTarget(UIView *view) {
    Class floating = objc_getClass("DecoratedFloatingView");
    Class scene = objc_getClass("DecoratedAppSceneView");
    if ((floating && [view isKindOfClass:floating]) || (scene && [view isKindOfClass:scene])) return YES;
    for (UIView *child in view.subviews) if (ContainsMangoTarget(child)) return YES;
    return NO;
}

static NSArray<UIWindow *> *AllWindows(void) {
    NSMutableOrderedSet<UIWindow *> *result = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window) [result addObject:window];
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows) if (window) [result addObject:window];
    return result.array;
}

static BOOL WindowIsSafeTarget(UIWindow *window, NSString **reasonOut) {
    if (object_getClass(window) != UIWindow.class) {
        if (reasonOut) *reasonOut = [NSString stringWithFormat:@"window-class-%@", NSStringFromClass(window.class)];
        return NO;
    }
    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGSize actual = window.bounds.size;
    CGSize expected = screen.fixedCoordinateSpace.bounds.size;
    BOOL fullScreen = fabs(actual.width-expected.width)<2 && fabs(actual.height-expected.height)<2;
    if (!fullScreen) {
        if (reasonOut) *reasonOut = [NSString stringWithFormat:@"not-fullscreen-bounds-%@-expected-%@",
                                    NSStringFromCGSize(actual), NSStringFromCGSize(expected)];
        return NO;
    }
    if (!CGPointEqualToPoint(window.layer.anchorPoint, CGPointMake(0.5,0.5))) {
        if (reasonOut) *reasonOut = [NSString stringWithFormat:@"anchor-%@", NSStringFromCGPoint(window.layer.anchorPoint)];
        return NO;
    }
    CGAffineTransform t = window.transform;
    CGAffineTransform identity = CGAffineTransformIdentity;
    CGAffineTransform flipped = CGAffineTransformMakeRotation((CGFloat)M_PI);
    if (!TransformNear(t, identity) && !TransformNear(t, flipped)) {
        if (reasonOut) *reasonOut = [NSString stringWithFormat:@"foreign-transform-%@", NSStringFromCGAffineTransform(t)];
        return NO;
    }
    return YES;
}

static void DiscoverMangoWindows(void) {
    for (UIWindow *window in AllWindows()) {
        if ([gMangoWindows containsObject:window] || [gRefusedWindows containsObject:window]) continue;
        if (!ContainsMangoTarget(window)) continue;
        NSString *reason = nil;
        if (!WindowIsSafeTarget(window, &reason)) {
            [gRefusedWindows addObject:window];
            Log(@"[WINDOW-REFUSED] ptr=%p reason=%@ frame=%@ bounds=%@ transform=%@", window,
                reason, NSStringFromCGRect(window.frame), NSStringFromCGRect(window.bounds),
                NSStringFromCGAffineTransform(window.transform));
            continue;
        }
        [gMangoWindows addObject:window];
        Log(@"[WINDOW-TRACKED] ptr=%p class=%@ level=%.3f frame=%@ bounds=%@ rootVC=%@",
            window, NSStringFromClass(window.class), window.windowLevel, NSStringFromCGRect(window.frame),
            NSStringFromCGRect(window.bounds), NSStringFromClass(window.rootViewController.class));
    }
}

static void SetWindowTransform(UIWindow *window, CGAffineTransform transform, NSString *action) {
    [UIView performWithoutAnimation:^{ window.transform = transform; }];
    Log(@"[WINDOW-%@] ptr=%p orientation=%ld transform=%@ frame=%@ bounds=%@",
        action, window, (long)MangoOrientation(), NSStringFromCGAffineTransform(window.transform),
        NSStringFromCGRect(window.frame), NSStringFromCGRect(window.bounds));
}

static void Reconcile(NSString *source) {
    NSAssert(NSThread.isMainThread, @"main thread required");
    if (!gReady) return;
    DiscoverMangoWindows();
    NSInteger orientation = MangoOrientation();
    BOOL disabled = [[NSFileManager defaultManager] fileExistsAtPath:kDisablePath];
    if (orientation != gLastOrientation) {
        Log(@"[ORIENTATION] source=%@ old=%ld new=%ld tracked=%lu disabled=%d", source,
            (long)gLastOrientation, (long)orientation, (unsigned long)gMangoWindows.count, disabled);
        gLastOrientation = orientation;
    }
    CGAffineTransform identity = CGAffineTransformIdentity;
    CGAffineTransform flipped = CGAffineTransformMakeRotation((CGFloat)M_PI);
    for (UIWindow *window in gMangoWindows.allObjects) {
        if (!window) continue;
        CGAffineTransform current = window.transform;
        if (!disabled && orientation == UIInterfaceOrientationPortraitUpsideDown) {
            if (TransformNear(current, identity)) SetWindowTransform(window, flipped, @"FLIPPED");
            else if (!TransformNear(current, flipped)) Log(@"[WINDOW-SUSPENDED] ptr=%p reason=foreign-transform value=%@", window, NSStringFromCGAffineTransform(current));
        } else {
            if (TransformNear(current, flipped)) SetWindowTransform(window, identity, @"RESTORED");
            else if (!TransformNear(current, identity)) Log(@"[WINDOW-SUSPENDED] ptr=%p reason=foreign-transform value=%@", window, NSStringFromCGAffineTransform(current));
        }
    }
}

static void ScheduleTick(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        Reconcile(@"timer");
        ScheduleTick();
    });
}

static void InstallWhenReady(void) {
    if (gReady) return;
    static NSUInteger attempts = 0;
    NSString *path = nil, *uuid = nil;
    if (!VerifyMango(&path, &uuid)) {
        attempts++;
        if (attempts <= 120) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ InstallWhenReady(); });
        } else {
            Log(@"[FIX-ABORT] reason=Mango-identity-mismatch-or-not-loaded path=%@ uuid=%@", path ?: @"unknown", uuid ?: @"unknown");
        }
        return;
    }
    gReady = YES;
    Log(@"[MANGO-IDENTITY] path=%@ uuid=%@ acceptedUUIDs=%@,%@", path, uuid,
        kInstalledMangoUUID, kPackagedMangoUUID);
    NSArray<NSNotificationName> *names = @[@"MangoInterfaceOrientationDidChange",
                                           UIApplicationDidChangeStatusBarOrientationNotification,
                                           UIDeviceOrientationDidChangeNotification];
    for (NSNotificationName name in names) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                Reconcile(note.name);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ Reconcile(@"notification+150ms"); });
            }];
    }
    Reconcile(@"installed");
    ScheduleTick();
}

__attribute__((constructor)) static void MangoSplitUpsideDownFixInit(void) {
    @autoreleasepool {
        gLogQueue = dispatch_queue_create("com.chenxun.mangosplitupsidedownfix.log", DISPATCH_QUEUE_SERIAL);
        gSessionID = NSUUID.UUID.UUIDString;
        gMangoWindows = [NSHashTable weakObjectsHashTable];
        gRefusedWindows = [NSHashTable weakObjectsHashTable];
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:kLogDirectory withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0755} error:&error];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:kLogPath error:nil];
        if ([attributes fileSize] > 2*1024*1024) {
            NSString *previous = [kLogDirectory stringByAppendingPathComponent:@"Fix.previous.log"];
            [[NSFileManager defaultManager] removeItemAtPath:previous error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:kLogPath toPath:previous error:nil];
        }
        AppendLine(@"");
        Log(@"[SESSION] start pid=%d version=%@ behavior=rotate-confirmed-mango-window-only disableFile=%@ mkdirError=%@",
            getpid(), kVersion, kDisablePath, error ?: @"none");
        dispatch_async(dispatch_get_main_queue(), ^{ InstallWhenReady(); });
    }
}
