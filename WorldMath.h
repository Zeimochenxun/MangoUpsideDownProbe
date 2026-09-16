#pragma once
#include <math.h>
typedef struct { double a,b,c,d,tx,ty; } MWTransform;
typedef struct { double x,y; } MWPoint;
static inline MWPoint MWApply(MWTransform t, MWPoint p) {
    return (MWPoint){t.a*p.x+t.c*p.y+t.tx,t.b*p.x+t.d*p.y+t.ty};
}
// Convert a parent-space half-turn about pivot to a UIView transform. UIView
// center stays fixed; translations include its displacement about that pivot.
static inline MWTransform MWTurn(MWTransform t, MWPoint center, MWPoint pivot) {
    return (MWTransform){-t.a,-t.b,-t.c,-t.d,
        2*(pivot.x-center.x)-t.tx,2*(pivot.y-center.y)-t.ty};
}
static inline int MWFinite(MWTransform t) {
    return isfinite(t.a)&&isfinite(t.b)&&isfinite(t.c)&&isfinite(t.d)&&isfinite(t.tx)&&isfinite(t.ty);
}
static inline int MWNear(MWTransform a, MWTransform b) {
    return fabs(a.a-b.a)<1e-6 && fabs(a.b-b.b)<1e-6 &&
        fabs(a.c-b.c)<1e-6 && fabs(a.d-b.d)<1e-6 &&
        fabs(a.tx-b.tx)<1e-4 && fabs(a.ty-b.ty)<1e-4;
}
