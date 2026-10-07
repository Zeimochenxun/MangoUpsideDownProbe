#include <assert.h>
#include <stdio.h>
#include "../src/Policy.h"

int main(void) {
    unsigned cases = 0;
    for (unsigned bits = 0; bits < 512; ++bits) {
        MSState s = { !!(bits&1), !!(bits&2), !!(bits&4), !!(bits&8), !!(bits&16),
                      !!(bits&32), !!(bits&64), !!(bits&128), !!(bits&256) };
        unsigned sb = MSModulesForProcess(s, MS_SPRINGBOARD);
        unsigned bb = MSModulesForProcess(s, MS_BACKBOARD);
        assert(MSModulesForProcess(s, MS_OTHER) == 0);
        if (!s.enabled) { assert(sb == 0); assert(bb == 0); }
        assert(!(sb & MS_ADAPTIVE));
        assert(!(bb & (MS_IDLE | MS_WORLD | MS_SPLIT)));
        assert(!!(bb & MS_ADAPTIVE) == (s.enabled && s.adaptive));
        assert(!!(sb & MS_IDLE) == (s.enabled && s.idle && !s.idleEmergency));
        assert(!!(sb & MS_WORLD) == (s.enabled && s.world && !s.worldEmergency && !s.legacyOrientation));
        assert(!!(sb & MS_SPLIT) == (s.enabled && s.split && !s.splitEmergency && !s.legacyOrientation));
        ++cases;
    }
    puts("PASS: 512 switch/emergency/legacy combinations across three process scopes");
    return cases == 512 ? 0 : 1;
}
