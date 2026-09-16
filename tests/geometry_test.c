#include "../Geometry.h"
#include <assert.h>
#include <stdio.h>

static void closeTo(double actual,double expected) { assert(fabs(actual-expected)<1e-7); }
static void knownLogSample(void) {
    MUDFRect screen={0,0,375,812};
    MUDFRect baseline={87.1527777777778,37.152777777777757,196.875,38.19444444444446};
    MUDFAffine parent={25.0/24,0,0,25.0/24,0,25.347222222222204};
    MUDFPoint delta;MUDFRect target;
    assert(MUDFPlan(screen,baseline,parent,&delta,&target)==MUDFPlanOK);
    closeTo(target.y,736.6527777777778);
    closeTo(delta.y,671.52);closeTo(delta.x,0);
    closeTo(target.x,baseline.x);closeTo(target.height,baseline.height);
    // Both positions have exactly the same margin to their respective edge.
    closeTo(screen.height-target.y-target.height,baseline.y);
    // Reconcile the same transformed rectangle 10,000 times: no accumulation.
    MUDFRect current=target;
    for(unsigned n=0;n<10000;++n) {
        MUDFRect unshifted=MUDFBaselineRect(current,parent,delta);
        closeTo(unshifted.y,baseline.y);
        assert(MUDFPlan(screen,unshifted,parent,&delta,&target)==MUDFPlanOK);
        current=target;closeTo(current.y,736.6527777777778);
    }
}
static void changingHeightAndParent(void) {
    MUDFRect screen={0,0,375,812};
    const double heights[]={36.6666666667,162.6666666667,89.6666666667,38.6666666667};
    for(unsigned n=0;n<4;++n) {
        MUDFRect base={32.6666666667*25/24,(11.3333333333+24.3333333333)*25/24,
                       295*25.0/24,heights[n]*25/24};
        MUDFPoint delta;MUDFRect target;
        assert(MUDFPlan(screen,base,(MUDFAffine){25.0/24,0,0,25.0/24,0,25},&delta,&target)==MUDFPlanOK);
        closeTo(target.y+target.height,812-base.y);
    }
    // Nonzero fixed-space origin, rotated/scaled parent: inverse vector mapping.
    MUDFRect shifted={-10,100,375,812},base={30,125,100,50},target;
    MUDFAffine rotated={0,2,-3,0,17,24};MUDFPoint delta;
    assert(MUDFPlan(shifted,base,rotated,&delta,&target)==MUDFPlanOK);
    closeTo(target.y,837);
    MUDFPoint fixed=MUDFVectorToFixed(rotated,delta);
    closeTo(fixed.x,0);closeTo(fixed.y,712);
}
static void restoreAndReject(void) {
    MUDFAffine original={0.8,0.1,-0.2,1.2,5,7};
    MUDFPoint delta={3,671.52};
    MUDFAffine applied=MUDFWithTranslation(original,delta);
    closeTo(applied.a,original.a);closeTo(applied.d,original.d);
    closeTo(applied.tx,8);closeTo(applied.ty,678.52);
    // Removing only the owned translation preserves the system matrix.
    MUDFAffine restored=MUDFWithTranslation(applied,(MUDFPoint){-delta.x,-delta.y});
    assert(MUDFAffineNear(restored,original));
    applied.a=0.7;assert(!MUDFAffineNear(applied,MUDFWithTranslation(original,delta)));
    MUDFRect screen={0,0,375,812},target;MUDFPoint d;
    MUDFAffine identity={1,0,0,1,0,0};
    assert(MUDFPlan(screen,(MUDFRect){10,740,100,40},identity,&d,&target)==MUDFPlanAlreadyAtOtherEdge);
    assert(MUDFPlan(screen,(MUDFRect){10,NAN,100,40},identity,&d,&target)==MUDFPlanInvalid);
    assert(MUDFPlan(screen,(MUDFRect){10,10,100,0},identity,&d,&target)==MUDFPlanInvalid);
    assert(MUDFPlan(screen,(MUDFRect){10,10,100,600},identity,&d,&target)==MUDFPlanInvalid);
    assert(MUDFPlan(screen,(MUDFRect){10,10,100,40},(MUDFAffine){0,0,0,0,0,0},&d,&target)==MUDFPlanInvalid);
}
int main(void) {
    knownLogSample();changingHeightAndParent();restoreAndReject();
    puts("PASS: captured geometry, 10000 reconciliations, varying heights, coordinate inversion, restoration arithmetic, rejection guards");
    return 0;
}
