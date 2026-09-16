    }
    return result; // Do not swap top/bottom or reinterpret insets as a frame.
}
static void (*OrigFallback)(id, SEL, id);
static void HookFallback(id self, SEL cmd, id element) {
    BOOL observe = Enabled() && [NSThread isMainThread];
    NSArray<UIWindow *> *before = observe ? Windows() : nil;
    OrigFallback(self, cmd, element);
    if (!observe) return;
    Log(@"showFallbackPill: called (fallback route positively identified)");
    for (UIWindow *w in Windows()) {
        if (![before containsObject:w]) {
            [gFallbackWindows addObject:w];
            CaptureView(w, @"new-window-during-showFallbackPill");
        }
    }
    // An added window is a candidate until its geometry/hierarchy is checked.
}
static void (*OrigApertureAppear)(id, SEL, BOOL);
static void HookApertureAppear(id self, SEL cmd, BOOL animated) {
    OrigApertureAppear(self, cmd, animated);
    if (!Enabled() || ![NSThread isMainThread]) return;
    if ([self isKindOfClass:[UIViewController class]]) {
        gAperture = (UIViewController *)self;
        Snapshot(@"SBSystemApertureViewController.viewWillAppear");
    }
}
static BOOL Signature(Class c, SEL s, const char *ret, NSArray<NSString *> *args) {
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m || method_getNumberOfArguments(m) != args.count + 2) return NO;
    char type[512] = {0}; method_getReturnType(m, type, sizeof(type));
    if (strcmp(type, ret) != 0) return NO;
    for (NSUInteger i = 0; i < args.count; ++i) {
        memset(type, 0, sizeof(type));
        method_getArgumentType(m, (unsigned)i + 2, type, sizeof(type));
        if (strcmp(type, args[i].UTF8String) != 0) return NO;
    }
    return YES;
}
static BOOL VerifiedMangoLoaded(void) {
    const uint8_t expected[16] = {0x67,0xc0,0xd7,0xc2,0x44,0x87,0x3f,0xd2,0x95,0x35,0x06,0x77,0x45,0xae,0x4b,0x8f};
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *path = _dyld_get_image_name(i);
        if (!path) continue;
        const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
        if (strcasecmp(base, "mango.dylib") != 0) continue;
        const struct mach_header *raw = _dyld_get_image_header(i);
        if (!raw || raw->magic != MH_MAGIC_64) return NO;
        const struct mach_header_64 *h = (const struct mach_header_64 *)raw;
        const uint8_t *p = (const uint8_t *)(h + 1), *end = p + h->sizeofcmds;
        for (uint32_t n = 0; n < h->ncmds; ++n) {
            if (p + sizeof(struct load_command) > end) return NO;
            const struct load_command *c = (const struct load_command *)p;
            if (c->cmdsize < sizeof(*c) || c->cmdsize > (size_t)(end - p)) return NO;
            if (c->cmd == LC_UUID && c->cmdsize >= sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)p)->uuid, expected, 16) == 0;
            p += c->cmdsize;
        }
        return NO;
    }
    return NO;
}
static void Heartbeat(unsigned remaining) {
    if (!Enabled() || remaining == 0) return;
    Snapshot(@"periodic");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ Heartbeat(remaining - 1); });
}
static void TryInstall(void) {
    if (gInstalled || !Enabled()) return;
    if (!VerifiedMangoLoaded()) {
        if (++gTryCount < 40) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                                            dispatch_get_main_queue(), ^{ TryInstall(); });
        else Log(@"No matching Mango UUID within 20 seconds; no hooks installed.");
        return;
    }
    Class manager = objc_getClass("MangoPillManager"), element = objc_getClass("MangoPillElement");
    Class aperture = objc_getClass("SBSystemApertureViewController");
    SEL orientation = sel_registerName("handleInterfaceOrientationChange:");
    SEL fallback = sel_registerName("showFallbackPill:");
    SEL layout = sel_registerName("layoutHostContainerViewDidLayoutSubviews:");
    SEL outsets = sel_registerName("preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:");
    SEL appear = sel_registerName("viewWillAppear:");
    NSArray *oneObject = @[@"@"];
    NSArray *outsetArgs = @[[NSString stringWithUTF8String:@encode(NSInteger)],
                            [NSString stringWithUTF8String:@encode(UIEdgeInsets)],
                            [NSString stringWithUTF8String:@encode(UIEdgeInsets)]];
    if (!Signature(manager, orientation, "v", oneObject) || !Signature(manager, fallback, "v", oneObject) ||
        !Signature(element, layout, "v", oneObject) || !Signature(element, outsets, @encode(UIEdgeInsets), outsetArgs)) {
        Log(@"Runtime signature mismatch; no hooks installed."); return;
    }
    gFallbackWindows = [NSHashTable weakObjectsHashTable];
    gHostViews = [NSHashTable weakObjectsHashTable];
    gLastCapture = [NSMapTable weakToStrongObjectsMapTable];
    MSHookMessageEx(manager, orientation, (IMP)HookOrientation, (IMP *)&OrigOrientation);
    MSHookMessageEx(manager, fallback, (IMP)HookFallback, (IMP *)&OrigFallback);
    MSHookMessageEx(element, layout, (IMP)HookLayoutHost, (IMP *)&OrigLayoutHost);
    MSHookMessageEx(element, outsets, (IMP)HookOutsets, (IMP *)&OrigOutsets);
    BOOL nativeSignature = Signature(aperture, appear, "v", @[@"B"]) || Signature(aperture, appear, "v", @[@"c"]);
    if (nativeSignature) MSHookMessageEx(aperture, appear, (IMP)HookApertureAppear, (IMP *)&OrigApertureAppear);
    gInstalled = YES;
    Log(@"Installed observational hooks; original behavior preserved.");
    Log(nativeSignature ? @"native-appear=yes" : @"native-appear=no");
    // Use the actual local notification observed in the supplied binary.
    // This is NSNotificationCenter, not a Darwin notification.
    [NSNotificationCenter.defaultCenter addObserverForName:@"MangoInterfaceOrientationDidChange" object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (!Enabled()) return;
            id value = note.userInfo[@"orientation"];
            if ([value isKindOfClass:[NSNumber class]])
                Log([NSString stringWithFormat:@"local-notification orientation=%ld", (long)[value integerValue]]);
            Snapshot(@"local-notification");
        }];
    Heartbeat(300); // Ten minutes, two-second sampling, bounded 1 MiB file.
}
__attribute__((constructor)) static void StartProbe(void) {
    @autoreleasepool {
        if (!Enabled()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ TryInstall(); });
    }
