#!/usr/bin/env python3
from pathlib import Path

path = Path("TweakSafe.m")
source = path.read_text(encoding="utf-8")
original = source


def replace_exact(old: str, new: str, expected: int = 1) -> None:
    global source
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"stability patch mismatch: expected {expected} occurrence(s), found {count}: {old[:80]!r}")
    source = source.replace(old, new)

# 1) Light/Dark are transport markers, not visual colors. Keep them byte-identical
# so Mango's trait/tint interpolation cannot create invalid checksum frames.
old_dark = '''static NSString *DarkMarkerForPacked(uint32_t packed) {
    uint32_t encoded = packed ^ 0x119856u;
    unsigned r = encoded & 0x7Fu;
    unsigned g = (encoded >> 7) & 0x7Fu;
    unsigned b = (encoded >> 14) & 0x7Fu;
    unsigned a = MarkerAlphaForPacked(packed);
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", r, g, b, a];
}'''
new_dark = '''static NSString *DarkMarkerForPacked(uint32_t packed) {
    // Stability: Light/Dark carry identical transport bytes. Mango may animate
    // between these two preference colors; X -> X keeps every intermediate
    // frame a valid Island marker instead of briefly falling back to raw tint.
    return LightMarkerForPacked(packed);
}'''
replace_exact(old_dark, new_dark)

# 2) Adaptive/highlight decisions must use a stable unwarped reference sample.
replace_exact(
    '@"float3 mangoIslandAdaptiveColor(float3 background, float4 tint)\\n"',
    '@"float3 mangoIslandAdaptiveColor(float3 background, float3 referenceBackground, float4 tint)\\n"'
)

anchor = '@"float3 mangoIslandAdaptiveColor(float3 background, float3 referenceBackground, float4 tint)\\n"'
pos = source.index(anchor)
luma_old = '@"    float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));\\n"'
luma_pos = source.find(luma_old, pos)
if luma_pos < 0:
    raise SystemExit("stability patch mismatch: adaptive luminance line not found")
source = source[:luma_pos] + '@"    float luminance = dot(referenceBackground, float3(0.2126, 0.7152, 0.0722));\\n"' + source[luma_pos + len(luma_old):]

# 3) Flat and curved paths share the same color decision source. Curved keeps
# refraction/dispersion/Fresnel; those optics no longer feed back into tint state.
replace_exact(
    'withString:@"flat.rgb = mangoIslandAdaptiveColor(flat.rgb, u.tintColor);"',
    'withString:@"flat.rgb = mangoIslandAdaptiveColor(flat.rgb, flat.rgb, u.tintColor);"'
)
replace_exact(
    'withString:@"float3 outRGB = mangoIslandAdaptiveColor(bg.rgb, u.tintColor);\\n    float miaHighlightEdge = miaHighlightAmount(bg.rgb, u.tintColor);',
    'withString:@"float3 miaReference = src.sample(s, captureUV).rgb;\\n    float3 outRGB = mangoIslandAdaptiveColor(bg.rgb, miaReference, u.tintColor);\\n    float miaHighlightEdge = miaHighlightAmount(miaReference, u.tintColor);'
)

# Version/log signature for device-side verification.
replace_exact('MangoIslandAdaptiveColor 0.1.3', 'MangoIslandAdaptiveColor 0.1.3.1')
replace_exact(
    '[SHADER] 0.1.3 Island-only adaptive contrast glass compiled; non-marker glass retains original mix',
    '[SHADER] 0.1.3.1 stable-reference Island glass compiled; unified-marker=1 reference-luma=1'
)
replace_exact(
    '[SESSION] 0.1.3 island-only highlight-glass process=%@ bundle=%@',
    '[SESSION] 0.1.3.1 stable-reference island-only process=%@ bundle=%@'
)
replace_exact(
    '[SESSION] 0.1.3 MetalClass=%@ shaderSeen=%d patched=%d',
    '[SESSION] 0.1.3.1 MetalClass=%@ shaderSeen=%d patched=%d'
)

if source == original:
    raise SystemExit("stability patch made no changes")

path.write_text(source, encoding="utf-8")
print("Applied MangoIslandAdaptiveColor 0.1.3.1 stability patch")
