#include "../WorldMath.h"
#include "../Geometry.h"
#include <assert.h>
#include <stdio.h>
static int near(double a,double b){return fabs(a-b)<1e-8;}
int main(void) {
    MWPoint center={180,389.66666666666663}, pivot={180,389.76};
    MWTransform baseline={1,0,0,1,0,0};
    MWTransform turned=MWTurn(baseline,center,pivot);
    assert(near(turned.ty,0.18666666666672));
    assert(MWNear(MWTurn(turned,center,pivot),baseline));
    // Exercise translated/scaled/rotated baselines, asymmetric centers and
    // screen pivots. Every local point must land at 2*pivot-originalPoint.
    for(int i=0;i<1000;i++) {
        double angle=i*0.013;
        MWTransform t={cos(angle)*1.04,sin(angle)*1.04,-sin(angle)*.97,cos(angle)*.97,i*.17,-i*.11};
        MWPoint c={i*.19,400-i*.07}, p={187.5,406}, q={i*.31-100,i*.23-80};
        MWPoint old=MWApply(t,q), result=MWApply(MWTurn(t,c,p),q);
        assert(near(c.x+result.x,2*p.x-(c.x+old.x)));
        assert(near(c.y+result.y,2*p.y-(c.y+old.y)));
        assert(MWNear(MWTurn(MWTurn(t,c,p),c,p),t));
    }
    // Existing 180-degree content rotation is canceled before outer turn.
    MWTransform content={-1.18,0,0,-1.15,0,0};
    MWPoint q={30,10};
    MWTransform upright=MWCancelTurn(content);
    MWPoint inside=MWApply(upright,q);
    assert(near(-inside.x,MWApply(content,q).x));
    assert(near(-inside.y,MWApply(content,q).y));
    // Cancellation keeps scale and translation, and is its own inverse.
    MWTransform shifted={-1.1966,0,0,-1.1821,4.5,-7.25};
    MWTransform once=MWCancelTurn(shifted);
    assert(near(once.a,1.1966)&&near(once.d,1.1821));
    assert(near(once.tx,shifted.tx)&&near(once.ty,shifted.ty));
    assert(MWNear(MWCancelTurn(once),shifted));
    // The inverted-basis test drives both the sweep and the setTransform: path,
    // so it must accept the device's inverted content values and nothing else.
    assert(MWInvertedBasis(-1,-1,0,0));
    assert(MWInvertedBasis(shifted.a,shifted.d,shifted.c,shifted.b));
    assert(!MWInvertedBasis(1,1,0,0));            // already upright
    assert(!MWInvertedBasis(-1,1,0,0));           // mirrored, not turned
    assert(!MWInvertedBasis(1,-1,0,0));
    assert(!MWInvertedBasis(-1,-1,0.5,0.5));      // transitional angle
    assert(!MWInvertedBasis(0,-1,0,0));           // degenerate
    assert(!MWInvertedBasis(-1,NAN,0,0));
    // A near-identity skew from floating point still counts as inverted.
    assert(MWInvertedBasis(-1,-1,1.2246e-16,-1.2246e-16));
    assert(!MWFinite((MWTransform){NAN,0,0,1,0,0}));

    // Integrated placement: physical screen is 390x844. A Mango aperture
    // container still left at y=10 must be mirrored to the physical lower edge.
    MUDFRect screen={0,0,390,844};
    MUDFRect top={145,10,100,36};
    MUDFPoint delta={0,0};
    MUDFRect target={0,0,0,0};

    // Before World turns the parent, the old arithmetic moves down by +788.
    MUDFAffine uprightParent={1,0,0,1,0,0};
    assert(MUDFPlan(screen,top,uprightParent,&delta,&target)==MUDFPlanOK);
    assert(near(target.y,798));
    assert(near(delta.x,0)&&near(delta.y,788));

    // After World turns the parent, the same fixed-space correction must become
    // a negative parent-space translation. This is the key integration case.
    MUDFAffine turnedParent={-1,0,0,-1,0,0};
    assert(MUDFPlan(screen,top,turnedParent,&delta,&target)==MUDFPlanOK);
    assert(near(target.y,798));
    assert(near(delta.x,0)&&near(delta.y,-788));

    // If World already put the island on physical bottom, placement is a no-op.
    MUDFRect bottom={145,798,100,36};
    assert(MUDFPlan(screen,bottom,turnedParent,&delta,&target)==MUDFPlanAlreadyAtOtherEdge);

    // Reconstruct a baseline from an owned translation under the turned parent.
    MUDFRect current=bottom;
    MUDFPoint owned={0,-788};
    MUDFRect reconstructed=MUDFBaselineRect(current,turnedParent,owned);
    assert(near(reconstructed.x,top.x));
    assert(near(reconstructed.y,top.y));

    puts("PASS: whole-world half-turn plus integrated opposite-edge placement geometry");
}
