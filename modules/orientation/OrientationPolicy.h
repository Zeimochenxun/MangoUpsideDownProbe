#pragma once

// Mango's cached direction can fall back to portrait during a local scene
// transition while SpringBoard's status bar remains upside-down. This only
// fills that portrait/unknown gap; explicit landscape and upright exits pass.
static inline long MSB8ResolvedOrientation(long mango, long system) {
    if ((mango == 0 || mango == 1) && system == 2) return 2;
    return mango;
}

// The verified Beta9 pan has the same portrait branch for directions 1/2.
// Compensate its y only while our window is physically inverted and owned.
static inline int MSB8PanNeedsCorrection(long mango, int owned, int inverted) {
    return (mango == 1 || mango == 2) && owned && inverted;
}
static inline int MSB9PanNeedsCorrection(long direction,int apertureTarget,int inverted) {
    return (direction==1 || direction==2) && apertureTarget && inverted;
}
