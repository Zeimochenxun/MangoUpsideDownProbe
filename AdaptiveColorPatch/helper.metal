float miaMaster(uint c) {
    if (c == 0u) return 0.00; if (c == 1u) return 0.15; if (c == 2u) return 0.30; if (c == 3u) return 0.45;
    if (c == 4u) return 0.60; if (c == 5u) return 0.75; if (c == 6u) return 0.90; return 1.00;
}
float miaLumaStart(uint c) {
    if (c == 0u) return 0.00; if (c == 1u) return 0.04; if (c == 2u) return 0.08; if (c == 3u) return 0.12;
    if (c == 4u) return 0.18; if (c == 5u) return 0.24; if (c == 6u) return 0.32; return 0.42;
}
float miaLumaEnd(uint c) {
    if (c == 0u) return 0.18; if (c == 1u) return 0.26; if (c == 2u) return 0.34; if (c == 3u) return 0.42;
    if (c == 4u) return 0.52; if (c == 5u) return 0.64; if (c == 6u) return 0.78; return 0.92;
}
float miaDarkTarget(uint c) {
    if (c == 0u) return 0.20; if (c == 1u) return 0.35; if (c == 2u) return 0.50; if (c == 3u) return 0.65;
    if (c == 4u) return 0.80; if (c == 5u) return 0.88; if (c == 6u) return 0.94; return 1.00;
}
float miaBrightTarget(uint c) {
    if (c == 0u) return 0.00; if (c == 1u) return 0.025; if (c == 2u) return 0.05; if (c == 3u) return 0.08;
    if (c == 4u) return 0.12; if (c == 5u) return 0.18; if (c == 6u) return 0.26; return 0.36;
}
float miaDarkOpacity(uint c) {
    if (c == 0u) return 0.00; if (c == 1u) return 0.08; if (c == 2u) return 0.16; if (c == 3u) return 0.24;
    if (c == 4u) return 0.34; if (c == 5u) return 0.46; if (c == 6u) return 0.62; return 0.80;
}
float miaBrightOpacity(uint c) {
    if (c == 0u) return 0.00; if (c == 1u) return 0.10; if (c == 2u) return 0.20; if (c == 3u) return 0.30;
    if (c == 4u) return 0.42; if (c == 5u) return 0.56; if (c == 6u) return 0.70; return 0.85;
}
uint miaMarkerAlpha(uint packed) {
    uint folded = packed ^ (packed >> 5) ^ (packed >> 10) ^ (packed >> 15);
    return 8u + ((folded + 21u) % 24u);
}
uint miaPackedMarker(float4 tint) {
    uint rByte = uint(round(clamp(tint.r, 0.0, 1.0) * 255.0));
    uint gByte = uint(round(clamp(tint.g, 0.0, 1.0) * 255.0));
    uint bByte = uint(round(clamp(tint.b, 0.0, 1.0) * 255.0));
    uint aByte = uint(round(clamp(tint.a, 0.0, 1.0) * 255.0));
    bool markerLight = rByte >= 128u && gByte >= 128u && bByte >= 128u;
    bool markerDark = rByte < 128u && gByte < 128u && bByte < 128u;
    if (!markerLight && !markerDark) return 0xFFFFFFFFu;
    uint encoded = (rByte & 0x7Fu) | ((gByte & 0x7Fu) << 7) | ((bByte & 0x7Fu) << 14);
    uint packed = encoded ^ (markerLight ? 0x0E67A9u : 0x119856u);
    if (aByte != miaMarkerAlpha(packed)) return 0xFFFFFFFFu;
    uint startCode = (packed >> 3) & 7u;
    uint endCode = (packed >> 6) & 7u;
    uint darkTargetCode = (packed >> 9) & 7u;
    uint brightTargetCode = (packed >> 12) & 7u;
    if (miaLumaEnd(endCode) <= miaLumaStart(startCode) + 0.009) return 0xFFFFFFFFu;
    if (miaBrightTarget(brightTargetCode) > miaDarkTarget(darkTargetCode)) return 0xFFFFFFFFu;
    return packed;
}
bool miaIsIslandMarker(float4 tint) { return miaPackedMarker(tint) != 0xFFFFFFFFu; }
float miaHighlightAmount(float3 background, float4 tint) {
    uint p=miaPackedMarker(tint);
    if(p==0xFFFFFFFFu||(p&7u)==0u)return 0.0;
    float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));
    return smoothstep(0.68, 0.92, luminance);
}
float3 mangoIslandAdaptiveColor(float3 background, float4 tint)
{
    uint packed = miaPackedMarker(tint);
    if (packed == 0xFFFFFFFFu) return mix(background, tint.rgb, tint.a);
    uint masterCode = packed & 7u;
    uint startCode = (packed >> 3) & 7u;
    uint endCode = (packed >> 6) & 7u;
    uint darkTargetCode = (packed >> 9) & 7u;
    uint brightTargetCode = (packed >> 12) & 7u;
    uint darkOpacityCode = (packed >> 15) & 7u;
    uint brightOpacityCode = (packed >> 18) & 7u;
    float start = miaLumaStart(startCode);
    float end = miaLumaEnd(endCode);
    float luminance = dot(background, float3(0.2126, 0.7152, 0.0722));
    float bright = smoothstep(start, end, luminance);
    float target = mix(miaDarkTarget(darkTargetCode), miaBrightTarget(brightTargetCode), bright);
    float opacity = mix(miaDarkOpacity(darkOpacityCode), miaBrightOpacity(brightOpacityCode), bright);
    float master = miaMaster(masterCode);
    float3 normalAdaptive = mix(background, float3(target), clamp(opacity * master, 0.0, 1.0));
    float highlight = smoothstep(0.68, 0.92, luminance);
    float highlightOpacity = opacity * mix(1.0, 0.72, highlight) * master;
    float desiredLuma = mix(luminance, target, clamp(highlightOpacity, 0.0, 1.0));
    float scale = desiredLuma / max(luminance, 0.001);
    float3 chromaPreserved = clamp(background * scale, 0.0, 1.0);
    float3 highlightGlass = mix(background, chromaPreserved, 0.82);
    return mix(normalAdaptive, highlightGlass, highlight);
}

                                      