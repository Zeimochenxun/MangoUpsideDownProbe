#import "Beta9Compatibility.h"
#import <mach-o/loader.h>
#import <roothide.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static BOOL ImageMatches(NSString *filename, NSString *identifier) {
    NSString *relative = [@"/Library/MobileSubstrate/DynamicLibraries" stringByAppendingPathComponent:filename];
    const char *path = jbroot(relative.fileSystemRepresentation);
    FILE *file = fopen(path, "rb");
    if (!file) return NO;
    struct mach_header_64 header;
    BOOL valid = fread(&header, sizeof(header), 1, file) == 1 && header.magic == MH_MAGIC_64 &&
                 header.cputype == CPU_TYPE_ARM64 && (uint32_t)header.cpusubtype == 0x80000002u &&
                 header.filetype == MH_DYLIB && header.ncmds > 0 && header.ncmds <= 4096 &&
                 header.sizeofcmds >= sizeof(struct load_command) && header.sizeofcmds <= 262144;
    unsigned char *commands = valid ? malloc(header.sizeofcmds) : NULL;
    valid = valid && commands && fread(commands, header.sizeofcmds, 1, file) == 1;
    fclose(file);
    BOOL matched = NO;
    if (valid) {
        size_t position = 0;
        for (uint32_t i = 0; i < header.ncmds; ++i) {
            if (position + sizeof(struct load_command) > header.sizeofcmds) { valid = NO; break; }
            struct load_command command;
            memcpy(&command, commands + position, sizeof(command));
            if (command.cmdsize < sizeof(command) || command.cmdsize > header.sizeofcmds - position) { valid = NO; break; }
            if (command.cmd == LC_UUID) {
                if (command.cmdsize != sizeof(struct uuid_command) || matched) { valid = NO; break; }
                NSUUID *actual = [[NSUUID alloc] initWithUUIDBytes:commands + position + sizeof(command)];
                matched = [actual.UUIDString isEqualToString:identifier];
                if (!matched) { valid = NO; break; }
            }
            position += command.cmdsize;
        }
        valid = valid && position == header.sizeofcmds;
    }
    free(commands);
    return valid && matched;
}

BOOL MSValidateBeta9Files(NSError **error) {
    if (error) *error = nil;
    NSDictionary *expected = @{
        @"MangoPanda.dylib": @"2081DA7E-6C9B-30AA-9B3E-2DA9628A5B95",
        @"MangoHello.dylib": @"2E847FEA-97B0-3739-9097-3CEDCC5E1D1A",
        @"MangoOSRendering.dylib": @"7D067B62-6203-3D64-BE8A-3A4A7E965959",
    };
    for (NSString *name in expected) {
        if (!ImageMatches(name, expected[name])) {
            if (error) *error = [NSError errorWithDomain:@"com.chenxun.mangosuite.compatibility" code:1
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"%@ 不是本版适配的原版 Mango Beta9 模块。", name]}];
            return NO;
        }
    }
    return YES;
}
