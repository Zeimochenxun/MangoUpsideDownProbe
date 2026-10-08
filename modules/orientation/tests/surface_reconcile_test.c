#include "../SurfaceReconcile.h"
#include "../WorldPersistence.h"
#include <assert.h>
#include <stdio.h>
typedef struct { MWTransform model, parent; MWPoint center,pivot; int eligible, broken; unsigned writes; } Fixture;
static MSSurfaceSnapshot readSurface(void *context) {
    Fixture *f=context;
    MSSplitSnapshot s={.transform=f->model,.center=f->center,.pivot=f->pivot,.eligible=f->eligible};
    const MWPoint local[3]={{0,0},{1,0},{0,1}};
    MWPoint physical[3];
    for (unsigned i=0;i<3;i++) {
        MWPoint p=MWApply(f->model,local[i]); p.x+=f->center.x;p.y+=f->center.y;
        s.points[i]=p; physical[i]=MWApply(f->parent,p);
    }
    if (f->broken && f->writes) s.points[1].x+=10;
    int upright=MWInvertedBasis(physical[0].x-physical[1].x,physical[0].y-physical[2].y,physical[2].x-physical[0].x,physical[1].y-physical[0].y);
    return (MSSurfaceSnapshot){s,upright};
}
static void writeSurface(void *context,MWTransform value) { Fixture *f=context;f->model=value;++f->writes; }
int main(void) {
    const MWTransform identity={1,0,0,1,0,0};
    Fixture f={.model={.8,0,0,.8,3,-4},.parent=identity,.center={20,780},.pivot={187.5,406},.eligible=1};
    MSSurfaceOwnership owned={0};
    MSSurfaceSnapshot before=readSurface(&f);
    assert(MSSurfaceReconcile(&owned,1,readSurface,writeSurface,&f)==MSSplitApplied);
    assert(MSSplitMirrored(before.local,readSurface(&f).local));
    assert(f.model.a==-.8 && f.model.d==-.8);
    for (unsigned i=0;i<10000;i++) assert(MSSurfaceReconcile(&owned,1,readSurface,writeSurface,&f)==0);
    assert(f.writes==1);
    f.center=(MWPoint){40,700};
    assert(MSSurfaceReconcile(&owned,1,readSurface,writeSurface,&f)==MSSplitApplied);
    assert(MWNear(f.model,MWTurn(owned.turn.before,f.center,f.pivot)));
    assert(MSSurfaceReconcile(&owned,0,readSurface,writeSurface,&f)==MSSplitRestored);
    assert(f.model.a==.8 && f.model.tx==3);
    // A library already beneath a corrected launcher inherits the parent turn.
    f=(Fixture){.model=identity,.parent={-1,0,0,-1,375,812},.center={25,780},.pivot={25,780},.eligible=1};owned=(MSSurfaceOwnership){0};
    assert(MSSurfaceReconcile(&owned,1,readSurface,writeSurface,&f)==0 && f.writes==0);
    // If native code turns that child too, normalize it at its own center:
    // the library's placement remains inherited, without a second screen mirror.
    f.model=(MWTransform){-1,0,0,-1,0,0};
    assert(MSSurfaceReconcile(&owned,1,readSurface,writeSurface,&f)==MSSplitApplied);
    assert(MWNear(f.model,identity));
    for (unsigned i=0;i<10000;i++) assert(MSSurfaceReconcile(&owned,1,readSurface,writeSurface,&f)==0);
    f.model.tx=19;
    assert(MSSurfaceReconcile(&owned,0,readSurface,writeSurface,&f)==MSSplitReleased && f.model.tx==19);
    // Invalid maps never leave a half-applied write.
    f=(Fixture){.model=identity,.parent=identity,.center={20,780},.pivot={187.5,406},.eligible=1,.broken=1};owned=(MSSurfaceOwnership){0};
    assert(MSSurfaceReconcile(&owned,1,readSurface,writeSurface,&f)&MSSplitRejected);
    assert(!owned.turn.applied && MWNear(f.model,identity));
    // Parameter changes preserve the window's inverted animation endpoint.
    for (unsigned i=1;i<200;i++) {
        MWTransform raw={i*.01,0,0,i*.01,8,-3},target;
        assert(MWWindowLayoutTarget(raw,(MWPoint){190,400},(MWPoint){187.5,406},&target));
        assert(target.a==-raw.a && target.d==-raw.d && target.tx==-13 && target.ty==15);
    }
    MWTransform target;
    assert(!MWWindowLayoutTarget((MWTransform){-1,0,0,-1,0,0},f.center,f.pivot,&target));
    assert(!MWWindowLayoutTarget((MWTransform){1,.1,0,1,0,0},f.center,f.pivot,&target));
    assert(!MWWindowLayoutTarget((MWTransform){NAN,0,0,1,0,0},f.center,f.pivot,&target));
    puts("PASS: production surface policy handles off-center launcher/menu/library, parent inversion, child double-turn, native scale, center changes, 20000 stable passes, foreign ownership, rejection and window layout endpoints");
    return 0;
}
