#include "../WorldPersistence.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    MWTransform identity={1,0,0,1,0,0};
    MWTransform turned={-1,0,0,-1,0,0};
    // Stable media layout must retain the same correction without restoring.
    for(unsigned i=0;i<10000;++i)
        assert(MWKeepWorld(turned,turned,1,0,turned,turned));
    // A new scene or root half-turn makes a matching model render upright.
    assert(!MWKeepWorld(turned,turned,1,0,identity,identity));
    assert(!MWKeepWorld(turned,turned,1,0,turned,identity));
    // External resets and a native half-turn without ownership are preserved.
    assert(!MWKeepWorld(identity,turned,1,0,turned,turned));
    assert(!MWKeepWorld(turned,turned,0,0,turned,turned));
    assert(!MWKeepWorld(turned,turned,1,1,turned,turned));
    MWTransform unknown={NAN,0,0,-1,0,0};
    assert(!MWKeepWorld(turned,turned,1,0,unknown,turned));
    puts("PASS: actual world persistence policy, stable media basis, scene/root double-turn detection, external/native ownership guards");
    return 0;
}
