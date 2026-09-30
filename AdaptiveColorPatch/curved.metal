float3 outRGB = mangoIslandAdaptiveColor(bg.rgb, u.tintColor);
    float miaHighlightEdge = miaHighlightAmount(bg.rgb, u.tintColor);
    if (miaHighlightEdge > 0.001) {
        float miaEdgeFresnel = fresnelAtRatio(bezelRatio, u.refractiveIndex) * edgeOpacity;
        float miaDarkRim = clamp(miaEdgeFresnel * 0.34 * miaHighlightEdge, 0.0, 0.14);
        outRGB *= (1.0 - miaDarkRim);
    }