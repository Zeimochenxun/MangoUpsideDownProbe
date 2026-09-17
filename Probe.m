#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CydiaSubstrate/CydiaSubstrate.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>
#import <limits.h>

static NSString * const kLogDirectory = @"/var/mobile/Library/Logs/MangoUpsideDownWorld";
static NSString * const kLogPath = @"/var/mobile/Library/Logs/MangoUpsideDownWorld/Probe.log";
static NSString * const kExpectedMangoUUID = @"67c0d7c2-4487-3fd2-9535-067745ae4b8f";
static dispatch_queue_t gLogQueue;
static NSString *gSessionID;
static BOOL gInstalled;
static NSInteger gLastMangoOrientation = NSIntegerMin;
static NSInteger gLastLayoutMode = NSIntegerMin;
static volatile unsigned long long gEventCounter;
static __thread unsigned long long gGestureEvent;
static BOOL gRootWindowMetadataLogged;

static NSString *OrientationName(NSInteger value) {
    switch (value) {
        case UIInterfaceOrientationPortrait: return @"portrait";
        case UIInterfaceOrientationPortraitUpsideDown: return @"portraitUpsideDown";
        case UIInterfaceOrientationLandscapeLeft: return @"landscapeLeft";
        case UIInterfaceOrientationLandscapeRight: return @"landscapeRight";
        default: return [NSString stringWithFormat:@"unknown(%ld)", (long)value];
    }
}

static NSString *LayoutModeName(NSInteger value) {
    if (value == NSIntegerMin) return @"unknown";
    return [NSString stringWithFormat:@"%ld", (long)value];
}

static void AppendLine(NSString *line) {
    if (!line) return;
    NSString *owned = [line copy];
    dispatch_async(gLogQueue, ^{
        @autoreleasepool {
            NSString *full = [owned stringByAppendingString:@"\n"];
            NSData *data = [full dataUsingEncoding:NSUTF8StringEncoding];
            int fd = open(kLogPath.fileSystemRepresentation,
                          O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
            if (fd < 0) return;
            const uint8_t *bytes = data.bytes;
            NSUInteger left = data.length;
            while (left > 0) {
                ssize_t n = write(fd, bytes, left);
                if (n <= 0) break;
                bytes += n;
                left -= (NSUInteger)n;
            }
            close(fd);
        }
    });
}

static void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    AppendLine([NSString stringWithFormat:@"%.3f session=%@ %@", now,
                gSessionID ?: @"uninitialized", body]);
}

static NSInteger SceneOrientation(NSString **allScenes) {
    UIApplication *application = UIApplication.sharedApplication;
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    NSInteger chosen = UIInterfaceOrientationUnknown;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        NSInteger value = windowScene.interfaceOrientation;
        [items addObject:[NSString stringWithFormat:@"%@:%ld", OrientationName(value), (long)value]];
        if (chosen == UIInterfaceOrientationUnknown ||
            scene.activationState == UISceneActivationStateForegroundActive) {
            chosen = value;
        }
    }
    if (allScenes) *allScenes = [items componentsJoinedByString:@","];
    return chosen;
}

static NSInteger MangoOrientation(void) {
    Class cls = objc_getClass("DecoratedAppSceneView");
    SEL sel = sel_registerName("mango_currentInterfaceOrientation");
    if (!cls || ![cls respondsToSelector:sel]) return UIInterfaceOrientationUnknown;
    return ((NSInteger (*)(id, SEL))objc_msgSend)(cls, sel);
}

static void LogOrientation(NSString *source, NSInteger mode) {
    NSString *scenes = nil;
    NSInteger system = SceneOrientation(&scenes);
    NSInteger mango = MangoOrientation();
    Log(@"[ORIENTATION] source=%@ system=%ld systemName=%@ mango=%ld mangoName=%@ mode=%@ scenes=%@ visual=manual",
        source, (long)system, OrientationName(system), (long)mango,
        OrientationName(mango), LayoutModeName(mode), scenes.length ? scenes : @"none");
}

static NSString *ImagePathForIMP(IMP imp) {
    Dl_info info = {0};
    if (!imp || dladdr((const void *)imp, &info) == 0 || !info.dli_fname) return @"unknown";
    return [NSString stringWithUTF8String:info.dli_fname];
}

static NSString *UUIDForImageBase(const void *base) {
    if (!base) return nil;
    const struct mach_header_64 *header = (const struct mach_header_64 *)base;
    if (header->magic != MH_MAGIC_64) return nil;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(struct load_command)) return nil;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uuid = (const struct uuid_command *)command;
            const uint8_t *b = uuid->uuid;
            return [NSString stringWithFormat:
                    @"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                    b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],
                    b[10],b[11],b[12],b[13],b[14],b[15]];
        }
        cursor += command->cmdsize;
    }
    return nil;
}

static BOOL IMPBelongsToExpectedMango(IMP imp, NSString **pathOut, NSString **uuidOut) {
    Dl_info info = {0};
    if (!imp || dladdr((const void *)imp, &info) == 0 || !info.dli_fname) return NO;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    NSString *uuid = UUIDForImageBase(info.dli_fbase);
    if (pathOut) *pathOut = path;
    if (uuidOut) *uuidOut = uuid;
    BOOL isMango = [path.lastPathComponent caseInsensitiveCompare:@"mango.dylib"] == NSOrderedSame;
    return isMango && [uuid.lowercaseString isEqualToString:kExpectedMangoUUID];
}

static BOOL VerifyMethod(Class cls, SEL sel, BOOL classMethod, const char *expectedTypes,
                         BOOL requireMangoImage, Method *methodOut) {
    Method method = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) {
        Log(@"[HOOK-REFUSED] class=%@ selector=%@ reason=missing", NSStringFromClass(cls), NSStringFromSelector(sel));
        return NO;
    }
    const char *actual = method_getTypeEncoding(method);
    if (!actual || strcmp(actual, expectedTypes) != 0) {
        Log(@"[HOOK-REFUSED] class=%@ selector=%@ reason=type expected=%s actual=%s",
            NSStringFromClass(cls), NSStringFromSelector(sel), expectedTypes, actual ?: "null");
        return NO;
    }
    IMP imp = method_getImplementation(method);
    NSString *path = nil;
    NSString *uuid = nil;
    if (requireMangoImage && !IMPBelongsToExpectedMango(imp, &path, &uuid)) {
        Log(@"[HOOK-REFUSED] class=%@ selector=%@ reason=image path=%@ uuid=%@",
            NSStringFromClass(cls), NSStringFromSelector(sel), path ?: @"unknown", uuid ?: @"unknown");
        return NO;
    }
    if (methodOut) *methodOut = method;
    Log(@"[HOOK-VERIFIED] class=%@ selector=%@ types=%s image=%@ uuid=%@",
        NSStringFromClass(cls), NSStringFromSelector(sel), actual,
        path ?: ImagePathForIMP(imp), uuid ?: @"not-required");
    return YES;
}

static BOOL NameMatchesRootWindowKeyword(NSString *name) {
    if (!name.length) return NO;
    NSArray<NSString *> *keywords = @[@"orientation", @"rotation", @"scene", @"window",
                                      @"root", @"frame", @"bounds", @"transform",
                                      @"coordinate", @"layout", @"hitTest", @"pointInside"];
    for (NSString *keyword in keywords) {
        if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static NSString *ClassHierarchy(Class cls) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (Class cursor = cls; cursor && parts.count < 16; cursor = class_getSuperclass(cursor)) {
        [parts addObject:NSStringFromClass(cursor) ?: @"unknown"];
    }
    return [parts componentsJoinedByString:@"<-" ];
}

static void LogRootWindowClassMetadata(NSString *className) {
    Class cls = objc_getClass(className.UTF8String);
    if (!cls) {
        Log(@"[ROOT-WINDOW-CLASS] class=%@ exists=0", className);
        return;
    }
    const char *imageName = class_getImageName(cls);
    BOOL windowSubclass = [cls isSubclassOfClass:UIWindow.class];
    Log(@"[ROOT-WINDOW-CLASS] class=%@ exists=1 image=%s instanceSize=%zu isUIWindowSubclass=%d hierarchy=%@",
        className, imageName ?: "unknown", class_getInstanceSize(cls), windowSubclass, ClassHierarchy(cls));

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    NSUInteger loggedMethods = 0;
    for (unsigned int i = 0; i < methodCount && loggedMethods < 80; i++) {
        SEL selector = method_getName(methods[i]);
        NSString *selectorName = NSStringFromSelector(selector);
        if (!NameMatchesRootWindowKeyword(selectorName)) continue;
        const char *types = method_getTypeEncoding(methods[i]);
        IMP imp = method_getImplementation(methods[i]);
        Log(@"[ROOT-WINDOW-METHOD] class=%@ selector=%@ types=%s image=%@",
            className, selectorName, types ?: "unknown", ImagePathForIMP(imp));
        loggedMethods++;
    }
    free(methods);

    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    NSUInteger loggedIvars = 0;
    for (unsigned int i = 0; i < ivarCount && loggedIvars < 80; i++) {
        const char *rawName = ivar_getName(ivars[i]);
        NSString *ivarName = rawName ? [NSString stringWithUTF8String:rawName] : @"unknown";
        if (!NameMatchesRootWindowKeyword(ivarName)) continue;
        Log(@"[ROOT-WINDOW-IVAR] class=%@ ivar=%@ types=%s offset=%td",
            className, ivarName, ivar_getTypeEncoding(ivars[i]) ?: "unknown", ivar_getOffset(ivars[i]));
        loggedIvars++;
    }
    free(ivars);
    Log(@"[ROOT-WINDOW-METADATA-END] class=%@ declaredMethods=%u matchedMethods=%lu declaredIvars=%u matchedIvars=%lu",
        className, methodCount, (unsigned long)loggedMethods, ivarCount, (unsigned long)loggedIvars);
}

static NSArray<UIWindow *> *AllApplicationWindows(void) {
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window) [windows addObject:window];
        }
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window) [windows addObject:window];
    }
    return windows.array;
}

static NSString *ViewChain(UIView *view) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UIView *cursor = view; cursor && parts.count < 14; cursor = cursor.superview) {
        [parts addObject:NSStringFromClass(cursor.class) ?: @"unknown"];
    }
    if (view.window && ![parts.lastObject isEqualToString:NSStringFromClass(view.window.class)]) {
        [parts addObject:[NSString stringWithFormat:@"window:%@", NSStringFromClass(view.window.class)]];
    }
    return [parts componentsJoinedByString:@"->"];
}

static void LogOneRootWindow(UIWindow *window, NSString *source, NSUInteger index) {
    UIWindowScene *scene = window.windowScene;
    NSInteger orientation = scene ? scene.interfaceOrientation : UIInterfaceOrientationUnknown;
    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGPoint coordinateOrigin = [window convertPoint:CGPointZero toCoordinateSpace:screen.coordinateSpace];
    CGPoint fixedOrigin = [window convertPoint:CGPointZero toCoordinateSpace:screen.fixedCoordinateSpace];
    CGPoint localMax = CGPointMake(CGRectGetMaxX(window.bounds), CGRectGetMaxY(window.bounds));
    CGPoint coordinateMax = [window convertPoint:localMax toCoordinateSpace:screen.coordinateSpace];
    CGPoint fixedMax = [window convertPoint:localMax toCoordinateSpace:screen.fixedCoordinateSpace];
    UIViewController *root = window.rootViewController;
    Log(@"[ROOT-WINDOW] source=%@ index=%lu ptr=%p class=%@ sceneOrientation=%ld sceneName=%@ frame=%@ bounds=%@ center=%@ transform=%@ key=%d hidden=%d alpha=%.3f level=%.3f screenBounds=%@ coordinateBounds=%@ fixedBounds=%@ coordinateOrigin=%@ coordinateMax=%@ fixedOrigin=%@ fixedMax=%@ rootVC=%@ rootViewFrame=%@ rootViewBounds=%@ rootViewTransform=%@",
        source, (unsigned long)index, window, NSStringFromClass(window.class), (long)orientation,
        OrientationName(orientation), NSStringFromCGRect(window.frame), NSStringFromCGRect(window.bounds),
        NSStringFromCGPoint(window.center), NSStringFromCGAffineTransform(window.transform),
        window.isKeyWindow, window.hidden, window.alpha, window.windowLevel,
        NSStringFromCGRect(screen.bounds), NSStringFromCGRect(screen.coordinateSpace.bounds),
        NSStringFromCGRect(screen.fixedCoordinateSpace.bounds), NSStringFromCGPoint(coordinateOrigin),
        NSStringFromCGPoint(coordinateMax), NSStringFromCGPoint(fixedOrigin), NSStringFromCGPoint(fixedMax),
        root ? NSStringFromClass(root.class) : @"none",
        root.viewIfLoaded ? NSStringFromCGRect(root.view.frame) : @"not-loaded",
        root.viewIfLoaded ? NSStringFromCGRect(root.view.bounds) : @"not-loaded",
        root.viewIfLoaded ? NSStringFromCGAffineTransform(root.view.transform) : @"not-loaded");
}

static void LogTargetWindowsOnMain(NSString *source, UIView *gestureView) {
    if (!gRootWindowMetadataLogged) {
        gRootWindowMetadataLogged = YES;
        LogRootWindowClassMetadata(@"UIRootSceneWindow");
        LogRootWindowClassMetadata(@"FBRootWindow");
    }
    Class uiRootClass = objc_getClass("UIRootSceneWindow");
    Class fbRootClass = objc_getClass("FBRootWindow");
    NSArray<UIWindow *> *windows = AllApplicationWindows();
    NSUInteger matched = 0;
    for (UIWindow *window in windows) {
        BOOL isUIRoot = uiRootClass && [window isKindOfClass:uiRootClass];
        BOOL isFBRoot = fbRootClass && [window isKindOfClass:fbRootClass];
        if (!isUIRoot && !isFBRoot) continue;
        if (matched < 32) LogOneRootWindow(window, source, matched);
        matched++;
    }
    Log(@"[ROOT-WINDOW-SUMMARY] source=%@ totalWindows=%lu matched=%lu uiRootClass=%d fbRootClass=%d",
        source, (unsigned long)windows.count, (unsigned long)matched, uiRootClass != Nil, fbRootClass != Nil);
    if (gestureView) {
        UIWindow *window = gestureView.window;
        CGPoint originInWindow = window ? [gestureView convertPoint:CGPointZero toView:window] : CGPointZero;
        CGPoint maxInWindow = window ? [gestureView convertPoint:CGPointMake(CGRectGetMaxX(gestureView.bounds), CGRectGetMaxY(gestureView.bounds)) toView:window] : CGPointZero;
        Log(@"[ROOT-WINDOW-GESTURE] source=%@ viewClass=%@ viewFrame=%@ viewBounds=%@ viewTransform=%@ windowClass=%@ originInWindow=%@ maxInWindow=%@ chain=%@",
            source, NSStringFromClass(gestureView.class), NSStringFromCGRect(gestureView.frame),
            NSStringFromCGRect(gestureView.bounds), NSStringFromCGAffineTransform(gestureView.transform),
            window ? NSStringFromClass(window.class) : @"none", NSStringFromCGPoint(originInWindow),
            NSStringFromCGPoint(maxInWindow), ViewChain(gestureView));
    }
}

static void LogTargetWindows(NSString *source, UIView *gestureView) {
    NSString *ownedSource = [source copy];
    __weak UIView *weakView = gestureView;
    if (NSThread.isMainThread) {
        LogTargetWindowsOnMain(ownedSource, gestureView);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ LogTargetWindowsOnMain(ownedSource, weakView); });
    }
}

static NSInteger (*OrigMangoOrientation)(id, SEL);
static NSInteger HookMangoOrientation(id self, SEL _cmd) {
    NSInteger result = OrigMangoOrientation(self, _cmd);
    if (result != gLastMangoOrientation) {
        gLastMangoOrientation = result;
        NSString *scenes = nil;
        NSInteger system = SceneOrientation(&scenes);
        Log(@"[MANGO-ORIENTATION] class=DecoratedAppSceneView selector=mango_currentInterfaceOrientation system=%ld input=none result=%ld resultName=%@ mode=%@",
            (long)system, (long)result, OrientationName(result), LayoutModeName(gLastLayoutMode));
    }
    return result;
}

static void (*OrigSetLayoutMode)(id, SEL, NSInteger, NSInteger);
static void HookSetLayoutMode(id self, SEL _cmd, NSInteger mode, NSInteger reason) {
    NSInteger oldMode = ((NSInteger (*)(id, SEL))objc_msgSend)(self, sel_registerName("layoutMode"));
    NSInteger system = SceneOrientation(NULL);
    NSInteger mango = MangoOrientation();
    Log(@"[MANGO-MODE] class=MangoPillElement selector=setLayoutMode:reason: system=%ld mango=%ld old=%ld input=%ld reason=%ld",
        (long)system, (long)mango, (long)oldMode, (long)mode, (long)reason);
    OrigSetLayoutMode(self, _cmd, mode, reason);
    gLastLayoutMode = mode;
}

static void (*OrigHandlePan)(id, SEL, UIPanGestureRecognizer *);
static void HookHandlePan(id self, SEL _cmd, UIPanGestureRecognizer *gesture) {
    UIGestureRecognizerState state = gesture.state;
    CGPoint translation = [gesture translationInView:gesture.view];
    unsigned long long event = 0;
    if (state == UIGestureRecognizerStateEnded) {
        event = __sync_add_and_fetch(&gEventCounter, 1);
        gGestureEvent = event;
        NSInteger mango = MangoOrientation();
        NSInteger system = SceneOrientation(NULL);
        NSInteger mode = ((NSInteger (*)(id, SEL))objc_msgSend)(self, sel_registerName("layoutMode"));
        NSString *predicted = translation.y > 30.0 ? @"defaultAction" :
                              ((translation.y < -30.0 || fabs(translation.x) > 50.0) ? @"dismissWithContent" : @"none");
        Log(@"[MANGO-GESTURE] event=%llu path=MangoPillElement.handlePanGesture state=ended system=%ld orientation=%ld mode=%ld translationX=%.3f translationY=%.3f predicted=%@ staticRule=orientation-independent",
            event, (long)system, (long)mango, (long)mode, translation.x, translation.y, predicted);
        LogTargetWindows(@"MangoPillElement.handlePanGesture.ended", gesture.view);
    }
    OrigHandlePan(self, _cmd, gesture);
    if (event) gGestureEvent = 0;
}

static void (*OrigResizePan)(id, SEL, UIPanGestureRecognizer *);
static void HookResizePan(id self, SEL _cmd, UIPanGestureRecognizer *gesture) {
    UIGestureRecognizerState state = gesture.state;
    unsigned long long event = 0;
    if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateEnded) {
        CGPoint translation = [gesture translationInView:gesture.view];
        NSInteger mango = MangoOrientation();
        NSInteger system = SceneOrientation(NULL);
        NSString *branch = (mango == 3 || mango == 4) ? @"landscape" : @"portraitFallback";
        if (state == UIGestureRecognizerStateEnded) {
            event = __sync_add_and_fetch(&gEventCounter, 1);
            gGestureEvent = event;
        }
        Log(@"[MANGO-GESTURE] event=%llu path=SBSystemApertureViewController._handleResizePan state=%@ system=%ld orientation=%ld branch=%@ translationX=%.3f translationY=%.3f",
            event, state == UIGestureRecognizerStateBegan ? @"began" : @"ended",
            (long)system, (long)mango, branch, translation.x, translation.y);
        LogTargetWindows(state == UIGestureRecognizerStateBegan ?
                         @"SBSystemApertureViewController._handleResizePan.began" :
                         @"SBSystemApertureViewController._handleResizePan.ended", gesture.view);
    }
    OrigResizePan(self, _cmd, gesture);
    if (event) gGestureEvent = 0;
}

static void (*OrigDefaultAction)(id, SEL);
static void HookDefaultAction(id self, SEL _cmd) {
    Log(@"[MANGO-ACTION] event=%llu selector=defaultAction orientation=%ld mode=%ld",
        gGestureEvent, (long)MangoOrientation(), (long)((NSInteger (*)(id, SEL))objc_msgSend)(self, sel_registerName("layoutMode")));
    OrigDefaultAction(self, _cmd);
}

static void (*OrigDismiss)(id, SEL, BOOL);
static void HookDismiss(id self, SEL _cmd, BOOL withContent) {
    Log(@"[MANGO-ACTION] event=%llu selector=dismissWithContent: value=%d orientation=%ld mode=%ld",
        gGestureEvent, withContent, (long)MangoOrientation(),
        (long)((NSInteger (*)(id, SEL))objc_msgSend)(self, sel_registerName("layoutMode")));
    OrigDismiss(self, _cmd, withContent);
}

static void (*OrigOpenSplit)(id, SEL);
static void HookOpenSplit(id self, SEL _cmd) {
    Log(@"[MANGO-ACTION] event=%llu selector=openSplitView orientation=%ld", gGestureEvent, (long)MangoOrientation());
    OrigOpenSplit(self, _cmd);
}

static void (*OrigOpenFullscreen)(id, SEL);
static void HookOpenFullscreen(id self, SEL _cmd) {
    Log(@"[MANGO-ACTION] event=%llu selector=openAppFullscreen orientation=%ld", gGestureEvent, (long)MangoOrientation());
    OrigOpenFullscreen(self, _cmd);
}

static void (*OrigReply)(id, SEL);
static void HookReply(id self, SEL _cmd) {
    Log(@"[MANGO-ACTION] event=%llu selector=replyAction orientation=%ld", gGestureEvent, (long)MangoOrientation());
    OrigReply(self, _cmd);
}

static void (*OrigManagerOrientation)(id, SEL, NSNotification *);
static void HookManagerOrientation(id self, SEL _cmd, NSNotification *notification) {
    OrigManagerOrientation(self, _cmd, notification);
    LogOrientation(@"MangoPillManager.handleInterfaceOrientationChange", gLastLayoutMode);
    LogTargetWindows(@"MangoPillManager.handleInterfaceOrientationChange", nil);
}

static NSString *OrientationTokenInDescription(id object) {
    NSString *text = [object description] ?: @"";
    for (NSString *token in @[@"portraitUpsideDown", @"landscapeRight", @"landscapeLeft", @"portrait"]) {
        if ([text containsString:token]) return token;
    }
    return @"none";
}

static void (*OrigClientSettings)(id, SEL, id, id);
static void HookClientSettings(id self, SEL _cmd, id diff, id context) {
    NSString *token = OrientationTokenInDescription(diff);
    if (![token isEqualToString:@"none"]) {
        Log(@"[MANGO-ORIENTATION-INPUT] class=SBDeviceApplicationSceneHandle selector=mango_didUpdateClientSettingsWithDiff:transitionContext: token=%@ mangoBefore=%ld",
            token, (long)MangoOrientation());
    }
    OrigClientSettings(self, _cmd, diff, context);
    if (![token isEqualToString:@"none"]) {
        Log(@"[MANGO-ORIENTATION-RESULT] token=%@ mangoAfter=%ld", token, (long)MangoOrientation());
    }
}

static void (*OrigLauncherPan)(id, SEL, UIPanGestureRecognizer *);
static void HookLauncherPan(id self, SEL _cmd, UIPanGestureRecognizer *gesture) {
    UIGestureRecognizerState state = gesture.state;
    if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateEnded) {
        UIView *view = gesture.view;
        CGPoint location = [gesture locationInView:view];
        CGPoint translation = [gesture translationInView:view];
        Log(@"[SPLIT-ACTIVATION] selector=launcherPanned: state=%@ system=%ld mango=%ld locationX=%.3f locationY=%.3f translationX=%.3f translationY=%.3f viewBounds=%@",
            state == UIGestureRecognizerStateBegan ? @"began" : @"ended",
            (long)SceneOrientation(NULL), (long)MangoOrientation(), location.x, location.y,
            translation.x, translation.y, NSStringFromCGRect(view.bounds));
    }
    OrigLauncherPan(self, _cmd, gesture);
}

static void (*OrigLauncherPanRight)(id, SEL, UIPanGestureRecognizer *);
static void HookLauncherPanRight(id self, SEL _cmd, UIPanGestureRecognizer *gesture) {
    UIGestureRecognizerState state = gesture.state;
    if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateEnded) {
        UIView *view = gesture.view;
        CGPoint location = [gesture locationInView:view];
        CGPoint translation = [gesture translationInView:view];
        Log(@"[SPLIT-ACTIVATION] selector=launcherPannedRight: state=%@ system=%ld mango=%ld locationX=%.3f locationY=%.3f translationX=%.3f translationY=%.3f viewBounds=%@",
            state == UIGestureRecognizerStateBegan ? @"began" : @"ended",
            (long)SceneOrientation(NULL), (long)MangoOrientation(), location.x, location.y,
            translation.x, translation.y, NSStringFromCGRect(view.bounds));
    }
    OrigLauncherPanRight(self, _cmd, gesture);
}

static BOOL InstallHook(Class cls, const char *selectorName, BOOL classMethod,
                        const char *types, IMP replacement, IMP *original) {
    SEL selector = sel_registerName(selectorName);
    Method method = Nil;
    if (!VerifyMethod(cls, selector, classMethod, types, YES, &method)) return NO;
    Class target = classMethod ? object_getClass(cls) : cls;
    MSHookMessageEx(target, selector, replacement, original);
    Log(@"[HOOK-INSTALLED] class=%@ selector=%@", NSStringFromClass(cls), NSStringFromSelector(selector));
    return YES;
}

static void InstallHooksWhenReady(void) {
    if (gInstalled) return;
    Class pill = objc_getClass("MangoPillElement");
    Class decorated = objc_getClass("DecoratedAppSceneView");
    Class manager = objc_getClass("MangoPillManager");
    if (!pill || !decorated || !manager) {
        static NSInteger attempts = 0;
        attempts++;
        if (attempts <= 120) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ InstallHooksWhenReady(); });
        } else {
            Log(@"[PROBE-ABORT] reason=Mango classes not loaded");
        }
        return;
    }

    Method identity = class_getInstanceMethod(pill, sel_registerName("handlePanGesture:"));
    NSString *path = nil;
    NSString *uuid = nil;
    if (!identity || !IMPBelongsToExpectedMango(method_getImplementation(identity), &path, &uuid)) {
        Log(@"[PROBE-ABORT] reason=Mango identity mismatch path=%@ uuid=%@ expectedUUID=%@",
            path ?: @"unknown", uuid ?: @"unknown", kExpectedMangoUUID);
        return;
    }

    gInstalled = YES;
    Log(@"[MANGO-IDENTITY] path=%@ uuid=%@ expectedUUID=%@ sha256-static=4679a2314e3a2f9e18d65503e5c69d67faaae81ab62b27d4d989a29b057f7ed6",
        path, uuid, kExpectedMangoUUID);

    InstallHook(decorated, "mango_currentInterfaceOrientation", YES, "q16@0:8", (IMP)HookMangoOrientation, (IMP *)&OrigMangoOrientation);
    InstallHook(pill, "setLayoutMode:reason:", NO, "v32@0:8q16q24", (IMP)HookSetLayoutMode, (IMP *)&OrigSetLayoutMode);
    InstallHook(pill, "handlePanGesture:", NO, "v24@0:8@16", (IMP)HookHandlePan, (IMP *)&OrigHandlePan);
    InstallHook(pill, "defaultAction", NO, "v16@0:8", (IMP)HookDefaultAction, (IMP *)&OrigDefaultAction);
    InstallHook(pill, "dismissWithContent:", NO, "v20@0:8B16", (IMP)HookDismiss, (IMP *)&OrigDismiss);
    InstallHook(pill, "openSplitView", NO, "v16@0:8", (IMP)HookOpenSplit, (IMP *)&OrigOpenSplit);
    InstallHook(pill, "openAppFullscreen", NO, "v16@0:8", (IMP)HookOpenFullscreen, (IMP *)&OrigOpenFullscreen);
    InstallHook(pill, "replyAction", NO, "v16@0:8", (IMP)HookReply, (IMP *)&OrigReply);
    InstallHook(manager, "handleInterfaceOrientationChange:", NO, "v24@0:8@16", (IMP)HookManagerOrientation, (IMP *)&OrigManagerOrientation);

    Class aperture = objc_getClass("SBSystemApertureViewController");
    if (aperture) {
        InstallHook(aperture, "_handleResizePan:", NO, "v24@0:8@16", (IMP)HookResizePan, (IMP *)&OrigResizePan);
    } else {
        Log(@"[HOOK-REFUSED] class=SBSystemApertureViewController selector=_handleResizePan: reason=missing-class");
    }

    Class sceneHandle = objc_getClass("SBDeviceApplicationSceneHandle");
    if (sceneHandle) {
        InstallHook(sceneHandle, "mango_didUpdateClientSettingsWithDiff:transitionContext:", NO,
                    "v32@0:8@16@24", (IMP)HookClientSettings, (IMP *)&OrigClientSettings);
    }

    Class viewController = objc_getClass("ViewController");
    if (viewController) {
        InstallHook(viewController, "launcherPanned:", NO, "v24@0:8@16", (IMP)HookLauncherPan, (IMP *)&OrigLauncherPan);
        InstallHook(viewController, "launcherPannedRight:", NO, "v24@0:8@16", (IMP)HookLauncherPanRight, (IMP *)&OrigLauncherPanRight);
    }

    [[NSNotificationCenter defaultCenter] addObserverForName:@"MangoInterfaceOrientationDidChange"
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        LogOrientation(@"MangoInterfaceOrientationDidChange", gLastLayoutMode);
        LogTargetWindows(@"MangoInterfaceOrientationDidChange", nil);
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidChangeStatusBarOrientationNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        LogOrientation(@"UIApplicationDidChangeStatusBarOrientation", gLastLayoutMode);
        LogTargetWindows(@"UIApplicationDidChangeStatusBarOrientation", nil);
    }];
    LogOrientation(@"hooks-installed", gLastLayoutMode);
    LogTargetWindows(@"hooks-installed", nil);
}

__attribute__((constructor)) static void MangoOrientationProbeInit(void) {
    @autoreleasepool {
        gLogQueue = dispatch_queue_create("com.chenxun.mangoorientationprobe.log", DISPATCH_QUEUE_SERIAL);
        gSessionID = NSUUID.UUID.UUIDString;
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:kLogDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions: @0755}
                                                        error:&error];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:kLogPath error:nil];
        if ([attributes fileSize] > 4 * 1024 * 1024) {
            NSString *previous = [kLogDirectory stringByAppendingPathComponent:@"Probe.previous.log"];
            [[NSFileManager defaultManager] removeItemAtPath:previous error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:kLogPath toPath:previous error:nil];
        }
        AppendLine(@"");
        Log(@"[SESSION] start pid=%d version=0.2.0 behavior=read-only rootWindows=UIRootSceneWindow,FBRootWindow log=%@ mkdirError=%@",
            getpid(), kLogPath, error ?: @"none");
        dispatch_async(dispatch_get_main_queue(), ^{ InstallHooksWhenReady(); });
    }
}
