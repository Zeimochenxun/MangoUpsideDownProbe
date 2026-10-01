#import "Beta8Compatibility.h"
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

BOOL MSValidateBeta8Files(NSError **error) {
    if (error) *error = nil;
    NSDictionary *expected = @{
        @"MangoPanda.dylib": @"05FEE465-833B-3982-AC57-CC721F1DA2E5",
        @"MangoHello.dylib": @"15D63429-C2F1-3997-B6A2-3E0F803D8FED",
        @"MangoOSRendering.dylib": @"0D23BE7C-63FC-335E-A5B2-6773627BA077",
    };
    for (NSString *name in expected) {
        if (!ImageMatches(name, expected[name])) {
            if (error) *error = [NSError errorWithDomain:@"com.chenxun.mangosuite.compatibility" code:1
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"%@ 不是本版适配的原版 Mango Beta8 模块。", name]}];
            return NO;
        }
    }
    return YES;
}
