#pragma once
#import <Foundation/Foundation.h>

// Diagnostics never select an action, change the recognizer, suppress a
// native exception, or cause the original callback to execute twice.
static inline void MSRunObservedPan(id controller, SEL selector, id gesture,
                                   void (*original)(id,SEL,id),
                                   void (^record)(BOOL returned)) {
    @try { if (record) record(NO); }
    @catch (__unused NSException *exception) {}
    original(controller,selector,gesture);
    @try { if (record) record(YES); }
    @catch (__unused NSException *exception) {}
}
