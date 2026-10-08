#pragma once
#include <math.h>
// Only bridge a recently observed inverted scene. Enabling support must not
// force a portrait device upside down, nor suppress an explicit landscape.
static inline long MSRecoverOrientation(long resolved,int nativeEnabled,double now,double *lastInverted) {
    if (!nativeEnabled) { *lastInverted=-INFINITY; return resolved; }
    if (resolved==2) { *lastInverted=now; return 2; }
    if ((resolved==0 || resolved==1) && isfinite(*lastInverted) && now>=*lastInverted && now-*lastInverted<=2) return 2;
    if (resolved==3 || resolved==4) *lastInverted=-INFINITY;
    return resolved;
}
