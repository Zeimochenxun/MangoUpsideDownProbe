#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

static inline CGPoint MSB9PanQueryValue(CGPoint value,id queried,id scoped,unsigned depth,BOOL mainThread) {
    if (depth && mainThread && queried && queried==scoped) value.y=-value.y;
    return value;
}

static inline CGPoint MSB9PanQueryValueInSpace(CGPoint value,id queried,id scoped,unsigned depth,BOOL mainThread,BOOL invertedSpace) {
    return invertedSpace ? MSB9PanQueryValue(value,queried,scoped,depth,mainThread) : value;
}
static inline void MSB9RunPanQueries(id gesture,void (^originalCall)(void),id __weak *scoped,unsigned *depth) {
    id previous=*scoped; unsigned priorDepth=*depth;
    *scoped=gesture; ++*depth;
    @try { originalCall(); }
    @finally { *depth=priorDepth; *scoped=previous; }
}

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
