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
        for (unsigned optical=0;optical<=1;optical++) {
            unsigned actual=MSModulesWithOptics(s,MS_SPRINGBOARD,optical);
            assert(!!(actual&MS_IDLE)==(s.enabled && !s.idleEmergency && (s.idle||optical)));
            assert((actual&~MS_IDLE)==(sb&~MS_IDLE));
            assert(MSModulesWithOptics(s,MS_BACKBOARD,optical)==bb);
            assert(MSModulesWithOptics(s,MS_OTHER,optical)==0);
        }
        for (int process=MS_OTHER;process<=MS_BACKBOARD;process++) for (int optical=0;optical<=1;optical++) {
            assert(MSModulesWithIsolation(s,process,optical,1)==0);
            assert(MSModulesWithIsolation(s,process,optical,0)==MSModulesWithOptics(s,process,optical));
        }
        ++cases;
    }
    puts("PASS: 512 switch/emergency/legacy combinations across three process scopes");
    MSState negative={.enabled=1,.adaptive=1,.world=1,.split=1};
    assert(MSModulesWithOptics(negative,MS_SPRINGBOARD,1)!=0);
    assert(MSModulesWithOptics(negative,MS_BACKBOARD,1)==MS_ADAPTIVE);
    assert(MSModulesWithIsolation(negative,MS_SPRINGBOARD,1,1)==0);
    assert(MSModulesWithIsolation(negative,MS_BACKBOARD,1,1)==0);
    puts("PASS: full isolation suppresses every module in 3072 process/optical/state cases; optical fallback and backboard shader negative controls detected");
    return cases == 512 ? 0 : 1;
}
