#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../src/PillSwipePolicy.h"

int main(void) {
    // Upright, landscape and unknown orientations are never touched.
    const long untouched[] = {0, 1, 3, 4, -1, 99};
    for (unsigned i = 0; i < sizeof untouched / sizeof *untouched; ++i)
        for (double y = -80; y <= 80; y += 10)
            assert(MSPillSwipeY(untouched[i], y, -y) == y && MSPillSwipeY(untouched[i], y, y) == y);
    // Upside-down, view chain NOT rotated (local == fixed): swipe is mirrored.
    assert(MSPillSwipeY(2, -50, -50) == 50);
    assert(MSPillSwipeY(2, 50, 50) == -50);
    assert(MSPillSwipeChanges(-50, MSPillSwipeY(2, -50, -50)));
    // Upside-down, view chain already rotated (local == -fixed): unchanged.
    assert(MSPillSwipeY(2, 50, -50) == 50);
    assert(!MSPillSwipeChanges(50, MSPillSwipeY(2, 50, -50)));
    // The handler's thresholds are +/-30: a 40pt swipe crosses, a 20pt one does not.
    assert(MSPillSwipeY(2, -40, -40) > 30 && MSPillSwipeY(2, 40, 40) < -30);
    assert(fabs(MSPillSwipeY(2, -20, -20)) < 30);
    // Unusable geometry falls back to the native value.
    assert(MSPillSwipeY(2, 7, NAN) == 7 && MSPillSwipeY(2, 7, INFINITY) == 7);
    assert(isnan(MSPillSwipeY(2, NAN, 5)));
    puts("PASS: pill swipe policy mirrors only upside-down vertical translation and leaves already-turned views alone");
    return 0;
}
