#import <Foundation/Foundation.h>
#import "../../src/StartupDiagnostics.h"
#include <dlfcn.h>
#include <assert.h>
#include <stdio.h>

int main(int argc,const char *argv[]) { @autoreleasepool {
    assert(argc==3);
    assert(MSWritePreferenceFlag(@"Enabled",NO,NULL));
    assert(MSWritePreferenceFlag(@"DebugEnabled",YES,NULL));
    assert(MSWritePreferenceValue(@"DebugSessionToken",@(NSDate.date.timeIntervalSince1970),NULL));
    assert(MSDiagnosticsActive());
    assert([MSImageUUID(NULL) isEqual:@"unavailable"]);
    struct { struct mach_header_64 h;struct uuid_command u; } fixture={0};
    fixture.h.magic=MH_MAGIC_64;fixture.h.ncmds=1;fixture.h.sizeofcmds=sizeof(fixture.u);
    fixture.u.cmd=LC_UUID;fixture.u.cmdsize=sizeof(fixture.u);fixture.u.uuid[15]=1;
    assert([MSImageUUID((const struct mach_header *)&fixture) isEqual:@"00000000-0000-0000-0000-000000000001"]);
    fixture.u.cmdsize=4;assert([MSImageUUID((const struct mach_header *)&fixture) isEqual:@"unavailable"]);
    fixture.h.ncmds=4097;assert([MSImageUUID((const struct mach_header *)&fixture) isEqual:@"unavailable"]);
    NSString *before=MSStartupSnapshot(0,YES);
    assert([before containsString:@"plannedMask=0"] && [before containsString:@"suiteImagesCurrently=0"]);
    // Load a harmless host fixture to prove the observer reports a stale or
    // externally loaded suite image even when its own planned mask is zero.
    void *handle=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);assert(handle);
    void *outside=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);assert(outside);
    NSString *after=MSStartupSnapshot(0,YES);
    assert([after containsString:@"repairImagesAnyPath=5"]);
    assert([after containsString:@"suiteImagesCurrently=1"] && [after containsString:@"image=MangoIdleIsland.dylib source=suite-module UUID="]);
    NSFileManager *files=NSFileManager.defaultManager;
    NSString *directory=[NSString stringWithUTF8String:jbroot("/var/mobile/Library/Logs")];
    assert([files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
    MSDiagnosticsLog(@"Startup",after);
    NSString *path=[directory stringByAppendingPathComponent:@"MangoSuiteDiagnostics/Startup.log"];
    NSString *text=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    assert([text containsString:@"version=1.2.0~beta9.6"] && [text containsString:@"plannedMask=0"] && [text containsString:@"suiteImagesCurrently=1"]);
    // This is a test fixture with no constructor or hooks, not a loaded tweak.
    assert(!dlclose(handle));assert(!dlclose(outside));
    puts("PASS: production startup observer records with master disabled, checks bounded UUID commands and detects already loaded modules both inside and outside the suite directory despite a zero planned mask");
} return 0; }
