// Exact helper bodies from IdleIsland 1.1.9.1~alpha1.
// Input raw SHA-256:
// ca17e881eb6a7dc4ba3f9e3cbb4638f143e1536e67e16f70eb9331b6f8e13ce5
// Verified against the fixed inputs/Tweak.alpha1.m snapshot by source-scope test.
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
    // Require a returning bounds animation to reach its compact destination.
    // A host transform/position animation carries its child glass with it and
    // must not be treated as a mismatched local bounds size.
    return StableIdleGeometry(visible) &&
           fabs(visible.width - model.width) <= 0.5 &&
           fabs(visible.height - model.height) <= 0.5;
}
