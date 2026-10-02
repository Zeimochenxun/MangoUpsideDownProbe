#pragma once
#include "WorldMath.h"

typedef enum { XMPlanInvalid = 0, XMPlanNativeInverted = 1, XMPlanApply = 2 } XMPlanResult;

// The model transform is in the window parent's space, while mapping and
// anchor are measured in fixed screen space. Infer the parent-vector mapping
// instead of assuming that UIWindowScene coordinates equal screen coordinates.
static inline XMPlanResult XMPlanHalfTurn(MWTransform baseline, MWTransform mapping,
                                         MWPoint fixedAnchor, MWPoint fixedPivot,
                                         MWTransform *after) {
    if (!after || !MWFinite(baseline) || !MWFinite(mapping) ||
        !isfinite(fixedAnchor.x) || !isfinite(fixedAnchor.y) ||
        !isfinite(fixedPivot.x) || !isfinite(fixedPivot.y)) return XMPlanInvalid;
    if (MWInvertedBasis(mapping.a, mapping.d, mapping.c, mapping.b)) return XMPlanNativeInverted;
    if (mapping.a <= 1e-5 || mapping.d <= 1e-5 ||
        fabs(mapping.b) > fabs(mapping.a)*.001 || fabs(mapping.c) > fabs(mapping.d)*.001)
        return XMPlanInvalid;
    double determinant = mapping.a*mapping.d - mapping.b*mapping.c;
    double modelDeterminant = baseline.a*baseline.d - baseline.b*baseline.c;
    if (!isfinite(determinant) || fabs(determinant) < 1e-10 ||
        !isfinite(modelDeterminant) || fabs(modelDeterminant) < 1e-10) return XMPlanInvalid;
    MWPoint delta = {2*(fixedPivot.x-fixedAnchor.x), 2*(fixedPivot.y-fixedAnchor.y)};
    MWPoint local = {(mapping.d*delta.x-mapping.c*delta.y)/determinant,
                    (-mapping.b*delta.x+mapping.a*delta.y)/determinant};
    MWPoint parent = {baseline.a*local.x+baseline.c*local.y,
                     baseline.b*local.x+baseline.d*local.y};
    MWTransform planned = {-baseline.a,-baseline.b,-baseline.c,-baseline.d,
                           baseline.tx+parent.x,baseline.ty+parent.y};
    if (!MWFinite(planned)) return XMPlanInvalid;
    *after = planned;
    return XMPlanApply;
}
