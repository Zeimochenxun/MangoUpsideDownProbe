#pragma once
#include "SplitReconcile.h"
typedef struct {
    MSSplitSnapshot local;
    int physicalUpright;
} MSSurfaceSnapshot;
typedef MSSurfaceSnapshot (*MSSurfaceRead)(void *context);
typedef struct {
    MSSplitOwnership turn;
    MWPoint center, pivot;
} MSSurfaceOwnership;
// Unlike a full-screen window, a launcher/picker can be off-center and scaled.
// center and pivot are both sampled in its immediate parent's coordinates.
static inline unsigned MSSurfaceReconcile(MSSurfaceOwnership *state,int active,
                                           MSSurfaceRead read,MSSplitWrite write,void *context) {
    MSSurfaceSnapshot sample=read(context);
    MSSplitSnapshot current=sample.local;
    unsigned result=0;
    if (!active || !current.eligible) return MSSplitRestore(&state->turn,current,write,context);
    if (state->turn.applied) {
        if (!MWOwns(current.transform,state->turn.after,1,0)) {
            result|=MSSplitRestore(&state->turn,current,write,context);
        } else if (sample.physicalUpright) {
            result|=MSSplitRestore(&state->turn,current,write,context);
            sample=read(context); current=sample.local;
        } else if (fabs(state->center.x-current.center.x)>.01 || fabs(state->center.y-current.center.y)>.01 ||
                   fabs(state->pivot.x-current.pivot.x)>.01 || fabs(state->pivot.y-current.pivot.y)>.01) {
            MWTransform next=MWTurn(state->turn.before,current.center,current.pivot);
            if (!MWFinite(next)) return result;
            state->turn.after=next; state->center=current.center; state->pivot=current.pivot;
            write(context,next); return result|MSSplitApplied;
        } else return result;
    }
    if (!current.eligible || !sample.physicalUpright || !MWFinite(current.transform)) return result;
    MWTransform next=MWTurn(current.transform,current.center,current.pivot);
    if (!MWFinite(next)) return result;
    state->turn.before=current.transform; state->turn.after=next; state->turn.applied=1;
    state->center=current.center; state->pivot=current.pivot;
    write(context,next);
    MSSplitSnapshot after=read(context).local;
    // Three points and pivot share parent-local space; a physical half-turn
    // commutes with any affine parent map. No UIWindow-only sample is used.
    if (!MSSplitMirrored(current,after)) {
        result|=MSSplitRestore(&state->turn,after,write,context);
        return result|MSSplitRejected;
    }
    return result|MSSplitApplied;
}
