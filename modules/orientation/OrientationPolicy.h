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
// Device log (Beta9.9): with the interface upside-down World turns the aperture
// window, yet the resize pan's view sits in a different, unturned window whose
// map to the fixed screen is the identity. Its translation is therefore in
// fixed (device) coordinates while the user sees the turned interface, so the
// handler's vertical direction is reversed. A view that is itself turned
// already reports the visual direction and must not be flipped again.
static inline int MSB10PanNeedsFlip(long direction,int uprightToFixed) {
    return direction==2 && uprightToFixed;
}
static inline int MSB9PanNeedsCorrection(long direction,int apertureTarget,int inverted) {
    return (direction==1 || direction==2) && apertureTarget && inverted;
}
