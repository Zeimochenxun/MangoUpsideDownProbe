#pragma once
#include <math.h>
#include <stdbool.h>

// Platform-independent arithmetic used by both the tweak and the host tests.
typedef struct { double x, y; } MUDFPoint;
typedef struct { double x, y, width, height; } MUDFRect;
typedef struct { double a, b, c, d, tx, ty; } MUDFAffine;
typedef enum {
    MUDFPlanOK, MUDFPlanInvalid, MUDFPlanAlreadyAtOtherEdge
} MUDFPlanResult;

static inline bool MUDFFiniteRect(MUDFRect r) {
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.width) &&
           isfinite(r.height) && r.width > 0 && r.height > 0;
}

static inline bool MUDFAffineNear(MUDFAffine a, MUDFAffine b) {
    return fabs(a.a-b.a) < 1e-7 && fabs(a.b-b.b) < 1e-7 &&
           fabs(a.c-b.c) < 1e-7 && fabs(a.d-b.d) < 1e-7 &&
           fabs(a.tx-b.tx) < 1e-5 && fabs(a.ty-b.ty) < 1e-5;
}

static inline MUDFPoint MUDFVectorToFixed(MUDFAffine parent, MUDFPoint v) {
    return (MUDFPoint){parent.a*v.x + parent.c*v.y,
                       parent.b*v.x + parent.d*v.y};
}

static inline MUDFAffine MUDFWithTranslation(MUDFAffine base, MUDFPoint delta) {
    // tx/ty are in the immediate parent's coordinates. Do not concatenate a
    // rotation or a scale, and do not multiply delta by the container's matrix.
    base.tx += delta.x; base.ty += delta.y;
    return base;
}

static inline MUDFRect MUDFBaselineRect(MUDFRect current, MUDFAffine parent,
                                       MUDFPoint ownTranslation) {
    MUDFPoint fixed = MUDFVectorToFixed(parent, ownTranslation);
    current.x -= fixed.x; current.y -= fixed.y;
    return current;
}

static inline MUDFPlanResult MUDFPlan(MUDFRect screen, MUDFRect baseline,
                                     MUDFAffine parent, MUDFPoint *delta,
                                     MUDFRect *target) {
    if (!delta || !target || !MUDFFiniteRect(screen) || !MUDFFiniteRect(baseline))
        return MUDFPlanInvalid;
    double det = parent.a*parent.d - parent.b*parent.c;
    if (!isfinite(det) || fabs(det) < 1e-8 ||
        !isfinite(parent.a) || !isfinite(parent.b) ||
        !isfinite(parent.c) || !isfinite(parent.d)) return MUDFPlanInvalid;
    // Only the upper-edge configuration evidenced in this device log is covered.
    if (baseline.y + baseline.height/2 >= screen.y + screen.height/2)
        return MUDFPlanAlreadyAtOtherEdge;
    if (baseline.height > screen.height/2 || baseline.y < screen.y - 1 ||
        baseline.y + baseline.height > screen.y + screen.height + 1)
        return MUDFPlanInvalid;
    *target = baseline;
    target->y = 2*screen.y + screen.height - baseline.y - baseline.height;
    double dy = target->y - baseline.y;
    // Inverse of the parent-to-fixed linear map, applied to (0, dy).
    *delta = (MUDFPoint){-parent.c*dy/det, parent.a*dy/det};
    if (!isfinite(delta->x) || !isfinite(delta->y)) return MUDFPlanInvalid;
    return MUDFPlanOK;
}
