#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Shared with the Foundation host regression. Guards stay in World.m; this
// helper is only the synchronous temporary mutation around the original call.
static inline void MSB8RunPanCorrection(CGPoint before,
                                      void (^setTranslation)(CGPoint),
                                      void (^originalCall)(void),
                                      unsigned *depth) {
    ++*depth;
    @try {
        setTranslation(CGPointMake(before.x,-before.y));
        originalCall();
    } @finally {
        @try { setTranslation(before); }
        @finally { --*depth; }
    }
}
