#pragma once
#include <math.h>

// Mango's MangoPillElement pan handler never looks at orientation: on Ended it
// reads one translationInView: and treats y < -30 / y > 30 as the two vertical
// actions. With the interface turned upside-down (orientation 2) the user's
// "up" is the device's +y, so the handler must see the negated fixed-space y.
// Deriving it from the screen's fixed space (not from the view's own
// transform) makes this correct whether or not the view chain is already
// rotated: if local already equals -fixed the result is unchanged.
static inline double MSPillSwipeY(long orientation, double localY, double fixedY) {
    if (orientation != 2 || !isfinite(localY) || !isfinite(fixedY)) return localY;
    return -fixedY;
}
static inline int MSPillSwipeChanges(double localY, double userY) {
    return fabs(userY - localY) > 1e-6;
}
