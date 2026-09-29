#!/usr/bin/env python3
from pathlib import Path

path = Path("TweakSafe.m")
source = path.read_text(encoding="utf-8")
original = source


def replace_exact(old: str, new: str, expected: int = 1) -> None:
    global source
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"stability patch mismatch: expected {expected} occurrence(s), found {count}: {old[:100]!r}")
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

# 2) Adaptive/highlight decisions use a stable unwarped reference sample.
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

# 3) Describe the complete original flat early-return block so the runtime patch
# can keep non-Island Mango glass byte-equivalent while allowing Island pixels to
# fall through into the same mapped-sampling pipeline as the refracted bezel.
replace_exact(
    'static NSString *const FlatOld = @"flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);";\nstatic NSString *const CurvedOld = @"float3 outRGB = mix(bg.rgb, u.tintColor.rgb, u.tintColor.a);";',
    'static NSString *const FlatOld = @"flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);";\nstatic NSString *const FlatBlockOld =\n@"if (R < shortest * 0.45 && distFromSide >= bezel) {\\n"\n @"        float4 flat = src.sample(s, captureUV);\\n"\n @"        flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);\\n"\n @"        return flat;\\n"\n @"    }";\nstatic NSString *const CurvedOld = @"float3 outRGB = mix(bg.rgb, u.tintColor.rgb, u.tintColor.a);";'
)

replace_exact(
    'Occurrences(source, FlatOld) != 1 ||\n        Occurrences(source, CurvedOld) != 1 ||',
    'Occurrences(source, FlatOld) != 1 ||\n        Occurrences(source, FlatBlockOld) != 1 ||\n        Occurrences(source, CurvedOld) != 1 ||'
)

old_edit = '''NSString *edited = [source stringByReplacingOccurrencesOfString:FlatOld
                                                           withString:@"flat.rgb = mangoIslandAdaptiveColor(flat.rgb, u.tintColor);"];'''
new_edit = '''NSString *edited = [source stringByReplacingOccurrencesOfString:FlatBlockOld
                                                           withString:@"if (R < shortest * 0.45 && distFromSide >= bezel) {\\n    if (!miaIsIslandMarker(u.tintColor) || bezel < 0.5) {\\n        float4 flat = src.sample(s, captureUV);\\n        flat.rgb = mix(flat.rgb, u.tintColor.rgb, u.tintColor.a);\\n        return flat;\\n    }\\n    // Island marker: no early return. The center continues through the same\\n    // backdropSampleUV pipeline as the bezel with zero displacement.\\n}"];'''
replace_exact(old_edit, new_edit)

# 4) Curved/general path uses the same reference luminance as the center. The
# visual background can still refract/dispersion-shift; tint state cannot drift.
replace_exact(
    'withString:@"float3 outRGB = mangoIslandAdaptiveColor(bg.rgb, u.tintColor);\\n    float miaHighlightEdge = miaHighlightAmount(bg.rgb, u.tintColor);',
    'withString:@"float3 miaReference = src.sample(s, captureUV).rgb;\\n    float3 outRGB = mangoIslandAdaptiveColor(bg.rgb, miaReference, u.tintColor);\\n    float miaHighlightEdge = miaHighlightAmount(miaReference, u.tintColor);'
)

# Version/log signature for device-side verification.
replace_exact('MangoIslandAdaptiveColor 0.1.3', 'MangoIslandAdaptiveColor 0.1.3.2')
replace_exact(
    '[SHADER] 0.1.3 Island-only adaptive contrast glass compiled; non-marker glass retains original mix',
    '[SHADER] 0.1.3.2 unified-sampling Island glass compiled; flat-fallthrough=1 stable-reference=1 unified-marker=1'
)
replace_exact(
    '[SESSION] 0.1.3 island-only highlight-glass process=%@ bundle=%@',
    '[SESSION] 0.1.3.2 unified-sampling island-only process=%@ bundle=%@'
)
replace_exact(
    '[SESSION] 0.1.3 MetalClass=%@ shaderSeen=%d patched=%d',
    '[SESSION] 0.1.3.2 MetalClass=%@ shaderSeen=%d patched=%d'
)

if source == original:
    raise SystemExit("stability patch made no changes")

path.write_text(source, encoding="utf-8")
print("Applied MangoIslandAdaptiveColor 0.1.3.2 unified-sampling patch")
