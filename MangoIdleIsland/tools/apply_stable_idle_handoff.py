#!/usr/bin/env python3
from pathlib import Path

path = Path("Tweak.m")
source = path.read_text(encoding="utf-8")
original = source


def replace_exact(old: str, new: str, expected: int = 1) -> None:
    global source
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"stable-idle patch mismatch: expected {expected}, found {count}: {old[:160]!r}")
    source = source.replace(old, new)

# The idle backdrop is always framed explicitly by Update(). Prevent UIKit from
# resizing it to a preview/active host size before our post-layout state check.
replace_exact(
    "    view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;",
    "    view.autoresizingMask = UIViewAutoresizingNone;"
)

old_eligibility = '''static NSString *Eligibility(UIView *host, CGFloat *activity) {
    *activity = 0;
    if (Disabled) return @"disabled";
    UIWindow *w = host.window;
    if (![w isKindOfClass:WindowClass] || !w.userInteractionEnabled) return @"window-excluded";
    if (!Visible(host)) return @"host-not-visible";
    CGSize size = host.bounds.size;
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 100 || size.width > 350 || size.height < 28 || size.height > 145) return @"geometry-excluded";
    NSMutableArray<UIView *> *todo = [host.subviews mutableCopy];
    UIView *own = objc_getAssociatedObject(host, &BackgroundKey);
    NSUInteger count = 0;
    CGFloat elementOpacity = 0, glassOpacity = 0;
    while (todo.count && count++ < 256) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        if (v == own) continue;
        if (ElementClass && [v isKindOfClass:ElementClass]) elementOpacity = MAX(elementOpacity, EffectiveOpacity(v, host));
        // Only Island-domain Mango glass is allowed to control the idle/active
        // handoff. Other Mango glass surfaces must not suppress Idle Island.
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
    if (todo.count) return @"scan-limit";
    // Activity content can precede its glass. Treat either as activity so
    // a dormant glass never masks an already visible media element.
    *activity = MAX(glassOpacity, elementOpacity);
    return *activity > 0.01 ? @"activity" : @"background";
}'''

new_eligibility = '''static BOOL StableIdleGeometry(CGSize size) {
    // Device logs show stable compact Island geometries around 125x36.67,
    // 129x38, 133x39.33 and 137.67x40.67. Long-press preview is 150x44.
    // Keep the supplemental glass strictly on the compact side of that split.
    return isfinite(size.width) && isfinite(size.height) &&
           size.width >= 110.0 && size.width <= 145.0 &&
           size.height >= 28.0 && size.height <= 45.0;
}

static NSString *Eligibility(UIView *host, CGFloat *activity) {
    *activity = 0;
    if (Disabled) return @"disabled";
    UIWindow *w = host.window;
    if (![w isKindOfClass:WindowClass] || !w.userInteractionEnabled) return @"window-excluded";
    if (!Visible(host)) return @"host-not-visible";
    CGSize size = host.bounds.size;
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 100 || size.width > 350 || size.height < 28 || size.height > 145) return @"geometry-excluded";
    BOOL stableIdleGeometry = StableIdleGeometry(size);
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
    if (todo.count) return @"scan-limit";

    *activity = MAX(glassOpacity, elementOpacity);
    if (*activity > 0.01) return @"activity";
    // A no-content geometry such as 150x44 is a press/preview transition, not
    // idle. Never keep an independent supplemental glass in that animation.
    return stableIdleGeometry ? @"background" : @"transition";
}'''
replace_exact(old_eligibility, new_eligibility)

old_update = '''static void Update(UIView *host) {
    if (InUpdate || !NSThread.isMainThread) return;
    InUpdate = YES;
    @try {
        CGFloat activity = 0;
        NSString *state = Eligibility(host, &activity);
        BOOL eligible = [state isEqualToString:@"background"] || [state isEqualToString:@"activity"];
        UIView *bg = objc_getAssociatedObject(host, &BackgroundKey);
        BOOL constructor = eligible && GlassConstructorVerified && !GlassConstructionFailed;
        BOOL mango = constructor && (OriginalIslandGlassSeen || MangoGlassSetting());
        BOOL upgrading = eligible && bg && mango && ![objc_getAssociatedObject(bg, &GlassModeKey) boolValue];
        if ([state isEqualToString:@"background"] && (!bg || upgrading)) {
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
            if ([state isEqualToString:@"background"]) {
                if (bg.superview != host) [host insertSubview:bg atIndex:0];
                if (!CGRectEqualToRect(bg.frame, host.bounds)) bg.frame = host.bounds;
                CGFloat radius = host.bounds.size.height / 2.0;
                if (bg.layer.cornerRadius != radius) bg.layer.cornerRadius = radius;
                CFTimeInterval now = CACurrentMediaTime();
                NSNumber *since = objc_getAssociatedObject(host, &OpaqueSinceKey);
                if (activity < 0.98) {
                    since = nil;
                    objc_setAssociatedObject(host, &OpaqueSinceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else if (!since) {
                    since = @(now);
                    objc_setAssociatedObject(host, &OpaqueSinceKey, since, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                CGFloat coverage = activity >= 0.98 && now - since.doubleValue < 0.06 ? 0 : activity;
                CGFloat backingOpacity = MAX(0, MIN(1, 1 - coverage));
                if (fabs(bg.alpha - backingOpacity) > 0.001) bg.alpha = backingOpacity;
                if (bg.hidden) bg.hidden = NO;
            } else {
                // A detached idle backdrop cannot participate in Mango's
                // live activity rendering or backdrop composition.
                if (!bg.hidden) bg.hidden = YES;
                if ([state isEqualToString:@"activity"] && bg.superview) [bg removeFromSuperview];
                objc_setAssociatedObject(host, &OpaqueSinceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        NSString *old = objc_getAssociatedObject(host, &StateKey);
        if (![old isEqualToString:state]) {
            Pulse();
            Log([NSString stringWithFormat:@"[STATE] host=%p state=%@ size=%.2fx%.2f background=%.2f",
                 (void *)host, state, host.bounds.size.width, host.bounds.size.height, bg.alpha]);
            objc_setAssociatedObject(host, &StateKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @finally {
        InUpdate = NO;
    }
}'''

new_update = '''static void Update(UIView *host) {
    if (InUpdate || !NSThread.isMainThread) return;
    InUpdate = YES;
    @try {
        CGFloat activity = 0;
        NSString *state = Eligibility(host, &activity);
        BOOL stableGeometry = StableIdleGeometry(host.bounds.size);
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
            Log([NSString stringWithFormat:@"[STATE] host=%p state=%@ stable=%d activity=%.3f size=%.2fx%.2f background=%.3f",
                 (void *)host, state, stableGeometry, activity,
                 host.bounds.size.width, host.bounds.size.height, bg ? bg.alpha : 0.0]);
            objc_setAssociatedObject(host, &StateKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @finally {
        InUpdate = NO;
    }
}'''
replace_exact(old_update, new_update)

replace_exact(
    '[SESSION] version=1.1.5-active-edge background=Mango-glass activity-detaches-idle touch=unchanged',
    '[SESSION] version=1.1.9-stable-idle-handoff background=Mango-glass stable-idle-only=1 inverse-native-opacity=1 activity-detaches-idle touch=unchanged'
)

if source == original:
    raise SystemExit("stable-idle patch made no changes")

path.write_text(source, encoding="utf-8")
print("Applied MangoIdleIsland 1.1.9 stable-idle handoff state machine")
