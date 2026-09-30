if (miaHighlightEdge > 0.001) glare *= mix(1.0, 0.55, miaHighlightEdge);
    outRGB = 1.0 - (1.0 - outRGB) * (1.0 - glare);