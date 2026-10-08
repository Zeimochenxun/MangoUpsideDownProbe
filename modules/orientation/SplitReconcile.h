#pragma once
#include "WorldMath.h"

// These are UIKit fixedCoordinateSpace samples used for the initial write's
// geometry check. They do not establish a launcher's visual orientation after
// native scene/layout changes while our model transform remains unchanged.
typedef struct {
    MWTransform transform;
    MWPoint points[3], center, pivot;
    int eligible;
} MSSplitSnapshot;

typedef struct {
    MWTransform before, after;
    MSSplitSnapshot suspendedAt;
    int applied, suspended;
} MSSplitOwnership;

typedef MSSplitSnapshot (*MSSplitRead)(void *context);
typedef void (*MSSplitWrite)(void *context, MWTransform transform);

enum {
    MSSplitRestored = 1 << 0,
    MSSplitReleased = 1 << 1,
    MSSplitApplied = 1 << 2,
    MSSplitRejected = 1 << 3
};

static inline int MSSplitFinitePoints(MSSplitSnapshot sample) {
    for (unsigned i = 0; i < 3; ++i)
        if (!isfinite(sample.points[i].x) || !isfinite(sample.points[i].y)) return 0;
    return 1;
}

static inline int MSSplitInverted(MSSplitSnapshot sample) {
    return MSSplitFinitePoints(sample) &&
        MWInvertedBasis(sample.points[1].x - sample.points[0].x,
                        sample.points[2].y - sample.points[0].y,
                        sample.points[2].x - sample.points[0].x,
                        sample.points[1].y - sample.points[0].y);
}

static inline int MSSplitUpright(MSSplitSnapshot sample) {
    if (!MSSplitFinitePoints(sample)) return 0;
    double dx = sample.points[1].x - sample.points[0].x;
    double dy = sample.points[2].y - sample.points[0].y;
    double skewX = sample.points[2].x - sample.points[0].x;
    double skewY = sample.points[1].y - sample.points[0].y;
    return dx > 1e-5 && dy > 1e-5 &&
        fabs(skewY) <= fabs(dx)*.001 && fabs(skewX) <= fabs(dy)*.001;
}

static inline int MSSplitMirrored(MSSplitSnapshot before, MSSplitSnapshot after) {
    // Preserve Beta8.2's post-write check: read the points even if the new
    // footprint fails a fresh preflight, then compare only the expected map.
    if (!MSSplitFinitePoints(after) ||
        !isfinite(before.pivot.x) || !isfinite(before.pivot.y)) return 0;
    for (unsigned i = 0; i < 3; ++i)
        if (fabs(after.points[i].x - (2*before.pivot.x - before.points[i].x)) > .1 ||
            fabs(after.points[i].y - (2*before.pivot.y - before.points[i].y)) > .1) return 0;
    return 1;
}

static inline int MSSplitSameGeometry(MSSplitSnapshot a, MSSplitSnapshot b) {
    if (a.eligible != b.eligible || !MWNear(a.transform,b.transform) ||
        !MSSplitFinitePoints(a) || !MSSplitFinitePoints(b) ||
        !isfinite(a.center.x) || !isfinite(a.center.y) ||
        !isfinite(b.center.x) || !isfinite(b.center.y) ||
        !isfinite(a.pivot.x) || !isfinite(a.pivot.y) ||
        !isfinite(b.pivot.x) || !isfinite(b.pivot.y) ||
        fabs(a.center.x-b.center.x)>.1 || fabs(a.center.y-b.center.y)>.1 ||
        fabs(a.pivot.x-b.pivot.x)>.1 || fabs(a.pivot.y-b.pivot.y)>.1) return 0;
    for (unsigned i=0; i<3; ++i)
        if (fabs(a.points[i].x-b.points[i].x)>.1 || fabs(a.points[i].y-b.points[i].y)>.1) return 0;
    return 1;
}

static inline unsigned MSSplitRestore(MSSplitOwnership *state,
                                     MSSplitSnapshot current,
                                     MSSplitWrite write, void *context) {
    if (!state->applied) return 0;
    int owned = MWOwns(current.transform, state->after, state->applied, state->suspended);
    state->applied = 0;
    if (owned) {
        write(context, state->before);
        return MSSplitRestored;
    }
    return MSSplitReleased;
}

static inline unsigned MSSplitReconcile(MSSplitOwnership *state, int active,
                                       MSSplitRead read, MSSplitWrite write,
                                       void *context) {
    MSSplitSnapshot current = read(context);
    if (!active || !current.eligible) return MSSplitRestore(state, current, write, context);
    if (state->suspended) {
        // Do not repeat a failed write on unchanged unsupported coordinates.
        // A later native layout/scene change must be allowed to recover.
        if (MSSplitSameGeometry(current,state->suspendedAt)) return 0;
        state->suspended = 0;
    }
    unsigned result = 0;
    if (state->applied) {
        // Beta8.2 kept its successfully verified write until another owner
        // replaced that exact matrix. A fixed-coordinate basis change alone
        // must not undo it: UIKit's scene mapping is not launcher visibility.
        if (MWOwns(current.transform, state->after, state->applied, state->suspended)) return 0;
        result |= MSSplitRestore(state, current, write, context);
        // Native layout/rotation hooks repair an external reset during this
        // same callback, using the original first-application guards again.
        current = read(context);
        if (!current.eligible) return result;
    }
    if (MSSplitInverted(current) || !MSSplitUpright(current) ||
        !MWNear(current.transform, (MWTransform){1,0,0,1,0,0})) return result;
    MWTransform turn = MWTurn(current.transform, current.center, current.pivot);
    if (!MWFinite(turn)) return result;
    state->before = current.transform;
    state->after = turn;
    state->applied = 1;
    write(context, turn);
    MSSplitSnapshot actual = read(context);
    if (!MSSplitMirrored(current, actual)) {
        result |= MSSplitRestore(state, actual, write, context);
        state->suspended = 1;
        state->suspendedAt = read(context);
        return result | MSSplitRejected;
    }
    return result | MSSplitApplied;
}

static inline unsigned MSSplitReconcileRecovery(MSSplitOwnership *state,int active,int recover,
                                               MSSplitRead read,MSSplitWrite write,void *context) {
    unsigned result=0;
    if (recover && active && state->applied) {
        MSSplitSnapshot current=read(context);
        // On Dock/library reopen UIKit can supply the scene's half-turn itself.
        // Our old half-turn then renders upright despite an unchanged model.
        // Relinquish only our exact write, and let the normal preflight decide
        // whether the now-native inversion needs any additional correction.
        if (current.eligible && MWOwns(current.transform,state->after,state->applied,state->suspended) && MSSplitUpright(current))
            result=MSSplitRestore(state,current,write,context);
    }
    return result | MSSplitReconcile(state,active,read,write,context);
}
