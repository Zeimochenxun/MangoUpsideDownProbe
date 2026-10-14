#pragma once
#import <Foundation/Foundation.h>

// Geometry setters must see the native logical transform. Nested setters on
// the same window participate in one transaction. No gesture callback is
// wrapped in this restoration: its local coordinate mapping stays inverted.
static inline void XMRunGeometryMutation(unsigned *depth, void (^restore)(void),
                                         void (^original)(void), void (^finish)(void)) {
    BOOL outer = (*depth)++ == 0;
    @try {
        if (outer) restore();
        original();
    } @finally {
        --(*depth);
        if (outer) finish();
    }
}
