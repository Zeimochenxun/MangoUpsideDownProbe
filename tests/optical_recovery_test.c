#define main prior_split_suite
#include "../modules/orientation/tests/split_reconcile_test.c"
#undef main
#include "../modules/orientation/RecoveryPolicy.h"
#include "../modules/visual/MangoIdleIsland/OpticalMath.h"

int main(void) {
    MSSplitOwnership state={0}; Fixture fixture=upright();
    assert(MSSplitReconcileRecovery(&state,1,1,readSnapshot,writeTransform,&fixture)==MSSplitApplied);
    mirroredScreen(&fixture);
    // Minimize/reopen: same model, new native scene half-turn.
    fixture.native=NativeTurn;
    assert(MSSplitUpright(readSnapshot(&fixture)));
    assert(MSSplitReconcileRecovery(&state,1,1,readSnapshot,writeTransform,&fixture)==MSSplitRestored);
    assert(!state.applied && fixture.writes==2);
    mirroredScreen(&fixture); launcherInverted(&fixture);
    for (unsigned i=0;i<10000;i++) assert(MSSplitReconcileRecovery(&state,1,1,readSnapshot,writeTransform,&fixture)==0);
    assert(fixture.writes==2);
    // Return to native upright mapping: apply exactly one correction again.
    fixture.native=Identity;
    assert(MSSplitReconcileRecovery(&state,1,1,readSnapshot,writeTransform,&fixture)==MSSplitApplied);
    mirroredScreen(&fixture);
    fixture.model.tx+=17; // Foreign writer is never restored to our baseline.
    assert(MSSplitReconcileRecovery(&state,0,1,readSnapshot,writeTransform,&fixture)==MSSplitReleased);
    assert(fixture.model.tx==17);
    fixture=upright(); state=(MSSplitOwnership){0};
    assert(MSSplitReconcileRecovery(&state,1,0,readSnapshot,writeTransform,&fixture)==MSSplitApplied);
    fixture.native=NativeTurn;
    assert(MSSplitReconcileRecovery(&state,1,0,readSnapshot,writeTransform,&fixture)==0); // Off preserves previous policy.

    double last=-INFINITY;
    assert(MSRecoverOrientation(1,1,10,&last)==1); // Enable alone never forces inversion.
    assert(MSRecoverOrientation(2,1,11,&last)==2);
    assert(MSRecoverOrientation(0,1,12,&last)==2);
    assert(MSRecoverOrientation(1,1,12.9,&last)==2);
    assert(MSRecoverOrientation(1,1,13.1,&last)==1); // No permanent stale latch.
    assert(MSRecoverOrientation(2,1,14,&last)==2);
    assert(MSRecoverOrientation(3,1,14.1,&last)==3);
    assert(MSRecoverOrientation(1,1,14.2,&last)==1);
    assert(MSRecoverOrientation(2,1,15,&last)==2);
    assert(MSRecoverOrientation(1,0,15.1,&last)==1);

    for (unsigned h=1;h<=300;h++) for (unsigned w=1;w<=400;w+=7) {
        double radius=MSOpticalRadius(w,h,1.2);
        assert(isfinite(radius) && radius>=0 && radius<=fmin(w,h)*.5);
    }
    assert(MSOpticalRadius(NAN,36,1)==0 && MSOpticalRadius(130,-1,1)==0);
    assert(MSOpticalRadius(130,36,1)==17.5);
    MSColorBin bins[13]={0}; MSRGB dominant;
    assert(!MSColorDominant(bins,&dominant));
    // A broad moderate blue area beats a tiny saturated red highlight.
    for (unsigned i=0;i<80;i++) MSColorAccumulate(bins,(MSRGB){.3,.4,.7});
    for (unsigned i=0;i<3;i++) MSColorAccumulate(bins,(MSRGB){1,0,0});
    assert(MSColorDominant(bins,&dominant) && dominant.b>dominant.r);
    MSColorBin neutral[13]={0};
    for (unsigned i=0;i<50;i++) MSColorAccumulate(neutral,(MSRGB){.5,.5,.5});
    assert(MSColorDominant(neutral,&dominant));
    assert(dominant.r==dominant.g && dominant.g==dominant.b);
    MSRGB p={0,0,0},target={1,.5,.25};
    for (unsigned i=0;i<60;i++) {
        p=MSColorSmooth(p,target,1.0/60,.5);
        assert(p.r>=0 && p.r<=1 && p.g>=0 && p.g<=.5 && p.b>=0 && p.b<=.25);
    }
    MSRGB q={0,0,0};
    for (unsigned i=0;i<30;i++) q=MSColorSmooth(q,target,1.0/30,.5);
    assert(fabs(p.r-q.r)<1e-9 && fabs(p.g-q.g)<1e-9);
    puts("PASS: real recovery policy handles Dock/library scene remap, no repeated turns, foreign ownership, independent off, bounded direction bridge, capsule degeneracy, area/saturation color choice and frame-rate-independent smoothing");
    return 0;
}
