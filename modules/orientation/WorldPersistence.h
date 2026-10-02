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
