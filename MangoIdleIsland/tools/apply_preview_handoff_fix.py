#!/usr/bin/env python3
from pathlib import Path

path = Path("Tweak.m")
source = path.read_text(encoding="utf-8")
original = source


def replace_exact(old: str, new: str, expected: int = 1) -> None:
    global source
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"preview handoff patch mismatch: expected {expected}, found {count}: {old[:140]!r}")
    source = source.replace(old, new)

# This patch is applied after apply_idle_geometry_sync.py, so these 1.1.6 symbols
# must already exist. Add one per-glass marker for native preview suppression.
replace_exact(
    "static char BackgroundKey, StateKey, LastElementHostKey, GlassModeKey, OpaqueSinceKey, LastParameterReapplyKey, EdgeAttemptKey, EdgeSeenKey, StableIdleBoundsKey, GeometryGuardKey;",
    "static char BackgroundKey, StateKey, LastElementHostKey, GlassModeKey, OpaqueSinceKey, LastParameterReapplyKey, EdgeAttemptKey, EdgeSeenKey, StableIdleBoundsKey, GeometryGuardKey, PreviewSuppressedKey;"
)

replace_exact(
    "    NSMutableArray<UIView *> *todo = [host.subviews mutableCopy];\n    UIView *own = objc_getAssociatedObject(host, &BackgroundKey);\n    NSUInteger count = 0;\n    CGFloat elementOpacity = 0, glassOpacity = 0;",
    "    NSMutableArray<UIView *> *todo = [host.subviews mutableCopy];\n    UIView *own = objc_getAssociatedObject(host, &BackgroundKey);\n    NSMutableArray<UIView *> *nativeIslandGlasses = [NSMutableArray array];\n    NSUInteger count = 0;\n    CGFloat elementOpacity = 0, glassOpacity = 0;"
)

replace_exact(
    "        if (IsIslandGlass(v)) {\n            EnsureActiveEdge(v);",
    "        if (IsIslandGlass(v)) {\n            [nativeIslandGlasses addObject:v];\n            EnsureActiveEdge(v);"
)

old_tail = '''    if (todo.count) return @"scan-limit";
    // Activity content can precede its glass. Treat either as activity so
    // a dormant glass never masks an already visible media element.
    *activity = MAX(glassOpacity, elementOpacity);
    return *activity > 0.01 ? @"activity" : @"background";'''
new_tail = '''    if (todo.count) return @"scan-limit";

    // Long-press/preview on an otherwise idle Island can make Mango expose its
    // native Island MGLiveBackdropView before any real SAUIElement content is
    // visible. That creates two complete glass surfaces: our idle backdrop plus
    // Mango's preview/active-sized glass. Never composite both at once.
    BOOL previewGlassOnly = glassOpacity > 0.01 && elementOpacity <= 0.01;
    if (previewGlassOnly) {
        for (UIView *glass in nativeIslandGlasses) {
            if (!objc_getAssociatedObject(glass, &PreviewSuppressedKey)) {
                CALayer *presentation = glass.layer.presentationLayer;
                CGRect pf = presentation ? presentation.frame : glass.layer.frame;
                Log([NSString stringWithFormat:@"[PREVIEW-HANDOFF] suppress ptr=%p model=%.2fx%.2f presentation=%.2fx%.2f host=%.2fx%.2f",
                     (void *)glass,
                     glass.frame.size.width, glass.frame.size.height,
                     pf.size.width, pf.size.height,
                     host.bounds.size.width, host.bounds.size.height]);
                objc_setAssociatedObject(glass, &PreviewSuppressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [UIView performWithoutAnimation:^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                glass.hidden = YES;
                [CATransaction commit];
            }];
        }
        *activity = 0;
        return @"background";
    }

    // A real activity has actual aperture element content. Restore only native
    // glasses that this tweak suppressed, then let the normal activity handoff
    // detach the idle backdrop.
    if (elementOpacity > 0.01) {
        for (UIView *glass in nativeIslandGlasses) {
            if ([objc_getAssociatedObject(glass, &PreviewSuppressedKey) boolValue]) {
                objc_setAssociatedObject(glass, &PreviewSuppressedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [UIView performWithoutAnimation:^{
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    glass.hidden = NO;
                    [CATransaction commit];
                }];
                Log([NSString stringWithFormat:@"[PREVIEW-HANDOFF] restore ptr=%p elementOpacity=%.3f", (void *)glass, elementOpacity]);
            }
        }
    }

    // Activity content can precede its glass. Treat either as activity so
    // a dormant glass never masks an already visible media element.
    *activity = MAX(glassOpacity, elementOpacity);
    return *activity > 0.01 ? @"activity" : @"background";'''
replace_exact(old_tail, new_tail)

replace_exact(
    '[SESSION] version=1.1.6-geometry-sync background=Mango-glass idle-size-guard=1 implicit-animation=off activity-detaches-idle touch=unchanged',
    '[SESSION] version=1.1.7-preview-handoff background=Mango-glass duplicate-preview-suppression=1 idle-size-guard=1 implicit-animation=off activity-detaches-idle touch=unchanged'
)

if source == original:
    raise SystemExit("preview handoff patch made no changes")

path.write_text(source, encoding="utf-8")
print("Applied MangoIdleIsland 1.1.7 preview handoff fix")
