// Exact helper bodies from the generated IdleIsland 1.1.9 baseline.
// Full baseline normalized SHA-256:
// 213948934e9b6b505b43ed1010d52723c27890716384d04f3e8f964794763402
// Verified against reverse-restored source by test_patch_scope_and_both_call_sites.
static CGFloat EffectiveOpacity(UIView *v, UIView *host) {
    CGFloat opacity = 1;
    for (UIView *p = v; p && p != host; p = p.superview) {
        if (p.hidden || p.layer.hidden) return 0;
        CALayer *layer = p.layer.presentationLayer ?: p.layer;
        opacity *= MIN(p.alpha, layer.opacity);
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
