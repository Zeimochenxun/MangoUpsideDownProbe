#import <Foundation/Foundation.h>
#import <limits.h>
#import <stdio.h>
#import <stdlib.h>
#import "roothide.h"
const char *jbroot(const char *path) {
    static char mapped[PATH_MAX];
    const char *root = getenv("MANGOSUITE_HOST_ROOT");
    if (!root || root[0] != '/') abort();
    if (snprintf(mapped, sizeof(mapped), "%s%s", root, path) >= (int)sizeof(mapped)) abort();
    return mapped;
}
