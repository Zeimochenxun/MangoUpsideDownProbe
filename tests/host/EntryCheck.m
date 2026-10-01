#import <Preferences/PSListController.h>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        Class principal = bundle.principalClass;
        NSString *expected = [NSString stringWithUTF8String:argv[2]];
        if (![NSStringFromClass(principal) isEqualToString:expected]) {
            NSLog(@"FAIL principal=%@ expected=%@", NSStringFromClass(principal), expected); return 1;
        }
        if (![expected isEqualToString:@"MangoSuitePrefsController"]) {
            puts("REPRODUCED: invalid CFBundlePrincipalClass falls back to the glass page"); return 0;
        }
        PSListController *controller = [principal new];
        NSArray *items = [controller specifiers];
        NSMutableArray *keys = [NSMutableArray new];
        NSMutableArray *links = [NSMutableArray new];
        for (PSSpecifier *item in items) {
            if (item.cellType == PSSwitchCell) [keys addObject:[item propertyForKey:@"key"]];
            if (item.cellType == PSLinkCell) [links addObject:NSStringFromClass(item.detailClass)];
        }
        NSArray *required = @[@"Enabled", @"IdleEnabled", @"AdaptiveEnabled", @"WorldEnabled", @"SplitEnabled"];
        NSArray *children = @[@"MangoSuiteGlassController", @"MangoIslandAdaptiveColorPrefsController"];
        if (![keys isEqual:required] || ![links isEqual:children]) {
            NSLog(@"FAIL switches=%@ links=%@", keys, links); return 1;
        }
        puts("PASS: NSBundle opens the root page with master + all four independent switches and both parameter links");
        return 0;
    }
}
