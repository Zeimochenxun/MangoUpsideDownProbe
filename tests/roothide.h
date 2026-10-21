// Host stand-in for RootHide's jbroot(): maps paths under $DD_TEST_ROOT.
#pragma once
#include <stdio.h>
#include <stdlib.h>

static inline const char *jbroot(const char *path) {
    static char mapped[4096];
    const char *root = getenv("DD_TEST_ROOT");
    snprintf(mapped, sizeof mapped, "%s%s", root ? root : "/tmp/doubledock-test", path);
    return mapped;
}
