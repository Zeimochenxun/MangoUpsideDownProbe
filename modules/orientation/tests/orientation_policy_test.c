#include "../OrientationPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // A local cached portrait/unknown must not reset a still-inverted system.
    assert(MSB8ResolvedOrientation(1,2) == 2);
    assert(MSB8ResolvedOrientation(0,2) == 2);
    // A real upright exit is immediate; no previous upside-down value latches.
    assert(MSB8ResolvedOrientation(1,1) == 1);
    assert(MSB8ResolvedOrientation(0,0) == 0);
    for (long native = 2; native <= 4; ++native)
        for (long system = 0; system <= 4; ++system)
            assert(MSB8ResolvedOrientation(native,system) == native);
    // Pan semantics follow the physical window, even during cached portrait.
    assert(MSB8PanNeedsCorrection(1,1,1));
    assert(MSB8PanNeedsCorrection(2,1,1));
    assert(!MSB8PanNeedsCorrection(1,0,1));
    assert(!MSB8PanNeedsCorrection(2,1,0));
    assert(!MSB8PanNeedsCorrection(0,1,1));
    assert(!MSB8PanNeedsCorrection(3,1,1));
    assert(!MSB8PanNeedsCorrection(4,1,1));
    puts("PASS: shared orientation policy, transient portrait fallback, upright/landscape exits, physically owned pan semantics");
    return 0;
}
