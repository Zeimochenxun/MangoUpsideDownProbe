#import <Foundation/Foundation.h>
#import "../../src/Beta9Compatibility.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSError *error = [NSError errorWithDomain:@"host.stale-error" code:99 userInfo:nil];
        BOOL valid = MSValidateBeta9Files(&error);
        BOOL expected = strcmp(argv[1], "pass") == 0;
        if (valid != expected || (!valid && !error) || (valid && error)) {
            NSLog(@"FAIL: compatibility=%d expected=%d error=%@", valid, expected, error); return 1;
        }
        printf("PASS: actual installed-file guard %s\n", valid ? "accepts matching Beta9 headers" : "rejects incompatible or malformed headers");
        return 0;
    }
}
