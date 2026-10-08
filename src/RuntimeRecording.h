#pragma once
#import <Foundation/Foundation.h>
#import <roothide.h>
#import "RuntimeSettings.h"
#include "DiagnosticsPolicy.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>

// This recorder observes existing decisions; it never sets a view or preference.
// Each translation unit has a finite session. All callers are on the main queue.
static inline BOOL MSDiagnosticsActive(void) {
    if (!NSThread.isMainThread) return NO;
    if (!MSPreferenceFlag(MSRuntimeSettings(), @"DebugEnabled")) return NO;
    id token = MSRuntimeSettings()[@"DebugSessionToken"];
    double began = [token isKindOfClass:NSNumber.class] ? [token doubleValue] : 0;
    double now = NSDate.date.timeIntervalSince1970;
    return MSDiagnosticSessionActive(1,began,now);
}

static inline void MSDiagnosticsLog(NSString *module, NSString *message) {
    if (!MSDiagnosticsActive() || !message.length ||
        !([module isEqualToString:@"Idle"] || [module isEqualToString:@"World"] || [module isEqualToString:@"Split"] || [module isEqualToString:@"Glass"] || [module isEqualToString:@"Startup"])) return;
    int fd = -1;
    @try {
        static NSTimeInterval rateSecond;
        static unsigned count;
        NSTimeInterval timestamp = NSDate.date.timeIntervalSince1970;
        NSTimeInterval second = floor(timestamp);
        if (rateSecond != second) { rateSecond = second; count = 0; }
        if (count++ >= 8) return;
        const char *mapped = jbroot("/var/mobile/Library/Logs/MangoSuiteDiagnostics");
        if (!mapped) return;
        struct stat info;
        if (mkdir(mapped, 0700) && errno != EEXIST) return;
        if (lstat(mapped, &info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid()) return;
        NSString *path = [[NSString stringWithUTF8String:mapped] stringByAppendingPathComponent:[module stringByAppendingString:@".log"]];
        fd = open(path.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_NONBLOCK, 0600);
        if (fd < 0) return;
        if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || info.st_nlink != 1) return;
        if (message.length > 8192) message = [[message substringToIndex:8100] stringByAppendingString:@"\n[message-truncated]"];
        NSData *line = [[NSString stringWithFormat:@"%.3f version=1.2.0~beta9.6 session=%.3f pid=%d module=%@ %@\n", timestamp, [MSRuntimeSettings()[@"DebugSessionToken"] doubleValue], getpid(), module, message] dataUsingEncoding:NSUTF8StringEncoding];
        if (info.st_size + (off_t)line.length > 256 * 1024 && ftruncate(fd, 0)) return;
        const uint8_t *bytes = line.bytes;
        size_t remaining = line.length;
        while (remaining) {
            ssize_t written = write(fd, bytes, remaining);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) break;
            bytes += written; remaining -= (size_t)written;
        }
    } @catch (__unused NSException *exception) {
        // A diagnostic failure cannot change a native callback's outcome.
    } @finally {
        if (fd >= 0) close(fd);
    }
}
