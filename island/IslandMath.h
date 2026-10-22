#pragma once
// Platform-independent arithmetic for the Dynamic Island package. No UIKit in
// here, so tests/island_test.c runs it on any host.
//
// Frames of reference used by every function below:
//   fixed   UIScreen.fixedCoordinateSpace: physical screen, never rotated.
//   local   the aperture window's own coordinate space. SpringBoard gives that
//           window a uniform scale (25/24 on the supplied device log), and
//           World/Suite turn it by 180 degrees while the phone is upside down.
//           Because the turn is applied to the WINDOW, local space always
//           reads the way the user sees the screen: +x right, +y down, in the
//           upright and in the inverted phone alike. That is the whole trick:
//           an adjustment written in local space needs no orientation maths.
//   visual  what the user sees, in points. visual = unit * local + origin.
#include <math.h>
#include <stdbool.h>

typedef struct { double x, y; } IMPoint;
typedef struct { double a, b, c, d, tx, ty; } IMAffine;  // CGAffineTransform layout

#define IM_SCALE_MIN 0.60
#define IM_SCALE_MAX 1.50
#define IM_OFFSET_MAX 80.0
// 11pt top inset + half of the 37pt resting pill of an iPhone 14 Pro: the
// point the island grows and shrinks around. Inferred from public device
// metrics, not read from SpringBoard.
#define IM_ANCHOR_Y_DEFAULT 29.5

// What the user asks for, in visual points. offsetX > 0 moves right and
// offsetY > 0 moves down, as seen by the user, whichever way the phone is held.
typedef struct { double scale, offsetX, offsetY, anchorY; } IMAdjust;

static inline double IMClamp(double v, double lo, double hi, double fallback) {
    if (!isfinite(v)) return fallback;
    return v < lo ? lo : (v > hi ? hi : v);
}

static inline IMAdjust IMSanitize(IMAdjust in) {
    return (IMAdjust){
        IMClamp(in.scale, IM_SCALE_MIN, IM_SCALE_MAX, 1.0),
        IMClamp(in.offsetX, -IM_OFFSET_MAX, IM_OFFSET_MAX, 0.0),
        IMClamp(in.offsetY, -IM_OFFSET_MAX, IM_OFFSET_MAX, 0.0),
        IMClamp(in.anchorY, 0.0, 200.0, IM_ANCHOR_Y_DEFAULT)};
}

// An identity adjustment must leave no footprint at all: the package then owns
// no transform anywhere and the aperture is exactly stock.
static inline bool IMIsIdentity(IMAdjust a) {
    return fabs(a.scale - 1.0) < 0.0005 && fabs(a.offsetX) < 0.005 && fabs(a.offsetY) < 0.005;
}

static inline IMAffine IMIdentity(void) { return (IMAffine){1, 0, 0, 1, 0, 0}; }

static inline bool IMAffineNear(IMAffine p, IMAffine q) {
    return fabs(p.a - q.a) < 1e-6 && fabs(p.b - q.b) < 1e-6 &&
           fabs(p.c - q.c) < 1e-6 && fabs(p.d - q.d) < 1e-6 &&
           fabs(p.tx - q.tx) < 1e-4 && fabs(p.ty - q.ty) < 1e-4;
}

static inline bool IMAffineFinite(IMAffine t) {
    return isfinite(t.a) && isfinite(t.b) && isfinite(t.c) && isfinite(t.d) &&
           isfinite(t.tx) && isfinite(t.ty);
}

// Points of the screen per point of window-local space: the window's own
// uniform scale, read from the magnitude of its transform so that a 180-degree
// turn (negative diagonal) does not change it. Anything implausible counts as 1;
// the unit only converts the user's offsets, so a wrong guess is a few percent
// of cosmetic error, never a geometry error.
static inline double IMWindowUnit(IMAffine window) {
    double unit = sqrt(fabs(window.a * window.d - window.b * window.c));
    return (isfinite(unit) && unit >= 0.5 && unit <= 2.0) ? unit : 1.0;
}

// UIView semantics: a view whose anchor sits at `anchor` (its layer.position,
// in the parent's space) with transform `t` sends the untransformed parent-space
// point `p` to the returned point. t.tx/t.ty act in the parent's space.
static inline IMPoint IMViewMap(IMAffine t, IMPoint anchor, IMPoint p) {
    double rx = p.x - anchor.x, ry = p.y - anchor.y;
    return (IMPoint){anchor.x + t.a * rx + t.c * ry + t.tx,
                     anchor.y + t.b * rx + t.d * ry + t.ty};
}

// The mapping the user asked for, in local space: scale about the fixed point
// `pivot`, then move by the offsets (converted from screen points).
static inline IMPoint IMAdjustMap(IMAdjust adj, double unit, IMPoint pivot, IMPoint p) {
    return (IMPoint){pivot.x + adj.scale * (p.x - pivot.x) + adj.offsetX / unit,
                     pivot.y + adj.scale * (p.y - pivot.y) + adj.offsetY / unit};
}

// Transform for an inner pass-through node so that IMViewMap(result, nodeAnchor, p)
// equals IMAdjustMap(adj, unit, pivot, p) for every p. `nodeAnchor` and `pivot`
// are both in the node's parent space, which the caller has verified is the
// window's local space translated only (no scale, no rotation).
static inline IMAffine IMNodeTransform(IMAdjust adj, double unit, IMPoint pivot, IMPoint nodeAnchor) {
    double s = adj.scale;
    return (IMAffine){s, 0, 0, s,
                      (1.0 - s) * (pivot.x - nodeAnchor.x) + adj.offsetX / unit,
                      (1.0 - s) * (pivot.y - nodeAnchor.y) + adj.offsetY / unit};
}

// A basis is "pure translation" when unit vectors keep their length and
// direction: the three probe points (origin, +x, +y) of a conversion.
static inline bool IMBasisIsTranslation(IMPoint o, IMPoint x, IMPoint y) {
    return isfinite(o.x) && isfinite(o.y) && isfinite(x.x) && isfinite(x.y) && isfinite(y.x) && isfinite(y.y) &&
           fabs((x.x - o.x) - 1.0) < 1e-4 && fabs(x.y - o.y) < 1e-4 &&
           fabs(y.x - o.x) < 1e-4 && fabs((y.y - o.y) - 1.0) < 1e-4;
}

// Orientation of a window's own basis in fixed space, for logs and the status
// line only. Nothing in the geometry above depends on it.
typedef enum { IMWindowUpright, IMWindowTurned, IMWindowOther } IMWindowTurn;

static inline IMWindowTurn IMClassifyWindowBasis(IMPoint o, IMPoint x, IMPoint y) {
    double dx = x.x - o.x, dy = y.y - o.y, skewX = y.x - o.x, skewY = x.y - o.y;
    if (!isfinite(dx) || !isfinite(dy) || !isfinite(skewX) || !isfinite(skewY)) return IMWindowOther;
    if (fabs(skewY) > fabs(dx) * 1e-3 || fabs(skewX) > fabs(dy) * 1e-3) return IMWindowOther;
    if (dx > 1e-5 && dy > 1e-5) return IMWindowUpright;
    if (dx < -1e-5 && dy < -1e-5) return IMWindowTurned;
    return IMWindowOther;
}

// Who writes the node's transform. The package never fights: it writes only
// over identity or over its own last value, and steps aside from anything else.
typedef enum {
    IMOwnKeep,      // nothing to do
    IMOwnWrite,     // write `desired`
    IMOwnRelease,   // restore identity if the value is still ours, then forget it
    IMOwnConflict   // someone else's non-identity value is there: leave it alone
} IMOwnAction;

static inline IMOwnAction IMOwnDecide(bool wanted, bool owned, IMAffine current, IMAffine applied, IMAffine desired) {
    bool identity = IMAffineNear(current, IMIdentity());
    if (owned) {
        if (IMAffineNear(current, applied)) {
            if (!wanted) return IMOwnRelease;
            return IMAffineNear(current, desired) ? IMOwnKeep : IMOwnWrite;
        }
        // Not our value any more. SpringBoard resetting it to identity is
        // harmless (write again); anything else belongs to someone else.
        if (identity) return wanted ? IMOwnWrite : IMOwnRelease;
        return IMOwnConflict;
    }
    if (!wanted) return IMOwnKeep;
    return identity ? IMOwnWrite : IMOwnConflict;
}
