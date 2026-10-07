#import <Foundation/Foundation.h>
#import "../../src/SuitePreferences.h"
#import "../../src/Policy.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSError *error = nil;
        NSDictionary *snapshot = MSReadPreferences(&error);
        if (!snapshot) { NSLog(@"FAIL: %@", error); return 1; }
        NSArray *keys = @[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled"];
        unsigned mask = 0;
        for (unsigned i = 0; i < keys.count; i++) if (MSPreferenceFlag(snapshot, keys[i])) mask |= 1u << i;
        if (mask != (unsigned)strtoul(argv[1], NULL, 10)) { NSLog(@"FAIL: persisted mask=%u", mask); return 1; }
        MSState state = {.enabled = !!(mask & 1), .idle = !!(mask & 2), .adaptive = !!(mask & 4), .world = !!(mask & 8), .split = !!(mask & 16)};
        printf("PASS: separate process reads saved selection=%u SpringBoard=%u backboardd=%u\n", mask,
               MSModulesForProcess(state, MS_SPRINGBOARD), MSModulesForProcess(state, MS_BACKBOARD));
        return 0;
    }
}
