#!/usr/bin/env python3
from pathlib import Path

path = Path("Tweak.m")
source = path.read_text(encoding="utf-8")
original = source


def replace_exact(old: str, new: str, expected: int = 1) -> None:
    global source
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"geometry sync patch mismatch: expected {expected}, found {count}: {old[:120]!r}")
    source = source.replace(old, new)

# Keep per-host stable idle geometry. SBSystemApertureContainerView may switch
# its model bounds to an activity-sized container during an inactive long press;
# the Idle glass must not adopt that width independently of Mango's pill.
replace_exact(
    "static char BackgroundKey, StateKey, LastElementHostKey, GlassModeKey, OpaqueSinceKey, LastParameterReapplyKey, EdgeAttemptKey, EdgeSeenKey;",
    "static char BackgroundKey, StateKey, LastElementHostKey, GlassModeKey, OpaqueSinceKey, LastParameterReapplyKey, EdgeAttemptKey, EdgeSeenKey, StableIdleBoundsKey, GeometryGuardKey;"
)

helper = r'''
static CGRect IdleGlassFrameForHost(UIView *host, BOOL *guardingOut) {
    CGRect current = host.bounds;
    if (guardingOut) *guardingOut = NO;
    if (!isfinite(current.size.width) || !isfinite(current.size.height) ||
        current.size.width <= 1.0 || current.size.height <= 1.0) return current;

    NSValue *saved = objc_getAssociatedObject(host, &StableIdleBoundsKey);
    if (!saved) {
        objc_setAssociatedObject(host, &StableIdleBoundsKey, [NSValue valueWithCGRect:current], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return current;
    }

    CGRect stable = saved.CGRectValue;
    if (!isfinite(stable.size.width) || !isfinite(stable.size.height) ||
        stable.size.width <= 1.0 || stable.size.height <= 1.0) {
        objc_setAssociatedObject(host, &StableIdleBoundsKey, [NSValue valueWithCGRect:current], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return current;
    }

    CGFloat widthAllowance = MAX(10.0, stable.size.width * 0.08);
    CGFloat heightAllowance = MAX(4.0, stable.size.height * 0.08);
    BOOL previewExpansion = current.size.width > stable.size.width + widthAllowance ||
                            current.size.height > stable.size.height + heightAllowance;

    if (!previewExpansion) {
        // Small layout drift and shrinkage are legitimate idle geometry updates.
        if (!CGRectEqualToRect(stable, current)) {
            objc_setAssociatedObject(host, &StableIdleBoundsKey, [NSValue valueWithCGRect:current], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return current;
    }

    if (guardingOut) *guardingOut = YES;
    return CGRectMake(CGRectGetMidX(current) - stable.size.width * 0.5,
                      CGRectGetMidY(current) - stable.size.height * 0.5,
                      stable.size.width,
                      stable.size.height);
}

'''
replace_exact("static void Update(UIView *host) {", helper + "static void Update(UIView *host) {")

old_geometry = '''                if (bg.superview != host) [host insertSubview:bg atIndex:0];
                if (!CGRectEqualToRect(bg.frame, host.bounds)) bg.frame = host.bounds;
                CGFloat radius = host.bounds.size.height / 2.0;
                if (bg.layer.cornerRadius != radius) bg.layer.cornerRadius = radius;'''
new_geometry = '''                BOOL geometryGuard = NO;
                CGRect targetFrame = IdleGlassFrameForHost(host, &geometryGuard);
                BOOL previousGuard = [objc_getAssociatedObject(host, &GeometryGuardKey) boolValue];
                if (geometryGuard != previousGuard) {
                    objc_setAssociatedObject(host, &GeometryGuardKey, @(geometryGuard), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    NSValue *saved = objc_getAssociatedObject(host, &StableIdleBoundsKey);
                    CGRect stable = saved ? saved.CGRectValue : CGRectZero;
                    Log([NSString stringWithFormat:@"[IDLE-GEOMETRY] guard=%d host=%.2fx%.2f idle=%.2fx%.2f",
                         geometryGuard, host.bounds.size.width, host.bounds.size.height,
                         stable.size.width, stable.size.height]);
                }
                if (bg.superview != host) [host insertSubview:bg atIndex:0];
                [UIView performWithoutAnimation:^{
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    if (!CGRectEqualToRect(bg.frame, targetFrame)) bg.frame = targetFrame;
                    CGFloat radius = targetFrame.size.height / 2.0;
                    if (fabs(bg.layer.cornerRadius - radius) > 0.001) bg.layer.cornerRadius = radius;
                    [CATransaction commit];
                }];'''
replace_exact(old_geometry, new_geometry)

old_alpha = '''                CGFloat backingOpacity = MAX(0, MIN(1, 1 - coverage));
                if (fabs(bg.alpha - backingOpacity) > 0.001) bg.alpha = backingOpacity;
                if (bg.hidden) bg.hidden = NO;'''
new_alpha = '''                CGFloat backingOpacity = MAX(0, MIN(1, 1 - coverage));
                [UIView performWithoutAnimation:^{
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    if (fabs(bg.alpha - backingOpacity) > 0.001) bg.alpha = backingOpacity;
                    if (bg.hidden) bg.hidden = NO;
                    [CATransaction commit];
                }];'''
replace_exact(old_alpha, new_alpha)

# Do not let hide/remove operations acquire their own implicit animation either.
old_hide = '''                if (!bg.hidden) bg.hidden = YES;
                if ([state isEqualToString:@"activity"] && bg.superview) [bg removeFromSuperview];'''
new_hide = '''                [UIView performWithoutAnimation:^{
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    if (!bg.hidden) bg.hidden = YES;
                    if ([state isEqualToString:@"activity"] && bg.superview) [bg removeFromSuperview];
                    [CATransaction commit];
                }];'''
replace_exact(old_hide, new_hide)

replace_exact(
    '[SESSION] version=1.1.5-active-edge background=Mango-glass activity-detaches-idle touch=unchanged',
    '[SESSION] version=1.1.6-geometry-sync background=Mango-glass idle-size-guard=1 implicit-animation=off activity-detaches-idle touch=unchanged'
)

if source == original:
    raise SystemExit("geometry sync patch made no changes")

path.write_text(source, encoding="utf-8")
print("Applied MangoIdleIsland 1.1.6 idle geometry sync patch")
