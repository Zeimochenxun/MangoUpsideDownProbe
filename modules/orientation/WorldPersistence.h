#pragma once
#include "WorldMath.h"

// Model equality alone cannot detect a new scene/root half-turn above an
// owned transform. Keep a correction only while both actual bases agree.
static inline int MWKeepWorld(MWTransform current, MWTransform after,
                              int applied, int suspended,
                              MWTransform windowMap, MWTransform rootMap) {
    return MWOwns(current, after, applied, suspended) &&
        MWInvertedBasis(windowMap.a,windowMap.d,windowMap.c,windowMap.b) &&
        MWInvertedBasis(rootMap.a,rootMap.d,rootMap.c,rootMap.b);
}
static inline int MWWindowLayoutTarget(MWTransform raw,MWPoint center,MWPoint pivot,MWTransform *target) {
    if (!MWFinite(raw) || raw.a<=0 || raw.d<=0 || fabs(raw.b)>fabs(raw.a)*.001 || fabs(raw.c)>fabs(raw.d)*.001 ||
        !isfinite(center.x) || !isfinite(center.y) || !isfinite(pivot.x) || !isfinite(pivot.y)) return 0;
    *target=MWTurn(raw,center,pivot);
    return MWFinite(*target);
}
