#include "../WorldMath.h"
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
    MWTransform upright={-content.a,-content.b,-content.c,-content.d,0,0};
    MWPoint inside=MWApply(upright,q);
    assert(near(-inside.x,MWApply(content,q).x));
    assert(near(-inside.y,MWApply(content,q).y));
    assert(!MWFinite((MWTransform){NAN,0,0,1,0,0}));
    puts("PASS: whole-world half-turn, inverse, scaled content and nonfinite guard");
}
