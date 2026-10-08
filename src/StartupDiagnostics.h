#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "RuntimeRecording.h"
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <string.h>

// Inspect dyld's existing images without dlopen, dlsym, hooks or UIKit calls.
static inline NSString *MSImageUUID(const struct mach_header *header) {
    if (!header || header->magic!=MH_MAGIC_64 || header->sizeofcmds>1024*1024 || header->ncmds>4096) return @"unavailable";
    const uint8_t *p=(const uint8_t *)header+sizeof(struct mach_header_64);
    const uint8_t *end=p+header->sizeofcmds;
    for (uint32_t i=0;i<header->ncmds;i++) {
        if ((size_t)(end-p)<sizeof(struct load_command)) break;
        const struct load_command *cmd=(const struct load_command *)p;
        if (cmd->cmdsize<sizeof(*cmd) || cmd->cmdsize>(size_t)(end-p)) break;
        if (cmd->cmd==LC_UUID && cmd->cmdsize>=sizeof(struct uuid_command))
            return [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)p)->uuid].UUIDString;
        p+=cmd->cmdsize;
    }
    return @"unavailable";
}
static inline NSString *MSStartupSnapshot(unsigned plannedMask,BOOL isolationAtStartup) {
    NSMutableArray<NSString *> *images=[NSMutableArray new];
    unsigned suitePresent=0,total=0;
    for (uint32_t i=0;i<_dyld_image_count();i++) {
        const char *raw=_dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path=[NSString stringWithUTF8String:raw],*name=path.lastPathComponent;
        BOOL suite=[path containsString:@"/MangoSuite/Modules/"];
        BOOL interesting=suite || [path containsString:@"/DynamicLibraries/"] ||
            [name hasPrefix:@"Mango"] || [name isEqualToString:@"AMangoSuiteLoader.dylib"];
        if (!interesting) continue;
        total++;
        if (suite) {
            if ([name isEqualToString:@"MangoIdleIsland.dylib"]) suitePresent|=1;
            if ([name isEqualToString:@"MangoIslandAdaptiveColor.dylib"]) suitePresent|=2;
            if ([name isEqualToString:@"MangoUpsideDownWorld.dylib"]) suitePresent|=4;
            if ([name isEqualToString:@"MangoSplitUpsideDownFix.dylib"]) suitePresent|=8;
        }
        if (images.count<64) [images addObject:[NSString stringWithFormat:@"image=%@ source=%@ UUID=%@",name,suite ? @"suite-module" : @"other-injection-or-native",MSImageUUID(_dyld_get_image_header(i))]];
    }
    return [NSString stringWithFormat:@"STARTUP compiled-loader=1.2.0~beta9.6 plannedMask=%u isolationAtStartup=%d isolationRequested=%d suiteImagesCurrently=%u interestingImageCount=%u truncated=%d hook-installation=unknown\n%@",
        plannedMask,isolationAtStartup,MSPreferenceFlag(MSRuntimeSettings(),@"CrashIsolationEnabled"),suitePresent,total,total>64,[images componentsJoinedByString:@"\n"]];
}
static inline void MSStartStartupDiagnostics(unsigned plannedMask,BOOL isolationAtStartup) {
    static dispatch_source_t timer;
    static double recordedSession;
    static NSString *last;
    void (^record)(void)=^{
        @try {
        if (!MSDiagnosticsActive()) return;
        double session=[MSRuntimeSettings()[@"DebugSessionToken"] doubleValue];
        NSString *snapshot=MSStartupSnapshot(plannedMask,isolationAtStartup);
        if (recordedSession!=session || ![last isEqualToString:snapshot]) {
            recordedSession=session;last=snapshot;MSDiagnosticsLog(@"Startup",snapshot);
        }
        } @catch (__unused NSException *exception) {}
    };
    record();
    timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    if (!timer) return;
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),2*NSEC_PER_SEC,200*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,record);dispatch_resume(timer);
}
