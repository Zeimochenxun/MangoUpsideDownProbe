#import "CrashReports.h"
#import <roothide.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <dirent.h>

NSArray<NSString *> *MSCrashReportDirectories(void) {
    NSMutableOrderedSet<NSString *> *result=[NSMutableOrderedSet new];
    for (NSString *path in @[@"/var/mobile/Library/Logs/CrashReporter",@"/var/mobile/Library/Logs/CrashReporter/Retired"]) {
        const char *mapped=jbroot(path.fileSystemRepresentation);
        if (mapped) [result addObject:[NSString stringWithUTF8String:mapped]];
        [result addObject:[@"/rootfs" stringByAppendingString:path]];
    }
    return result.array;
}
static BOOL ReportName(NSString *name) {
    if (![name.lastPathComponent isEqualToString:name] ||
        !([name hasPrefix:@"SpringBoard-"] || [name hasPrefix:@"SpringBoard_"])) return NO;
    return [@[@"ips",@"crash"] containsObject:name.pathExtension.lowercaseString];
}
static BOOL SpringBoardData(NSData *data,NSString *extension) {
    if ([extension.lowercaseString isEqualToString:@"ips"]) {
        NSData *newline=[@"\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange split=[data rangeOfData:newline options:0 range:NSMakeRange(0,MIN(data.length,16384))];
        NSData *head=split.location==NSNotFound ? data : [data subdataWithRange:NSMakeRange(0,split.location)];
        id json=[NSJSONSerialization JSONObjectWithData:head options:0 error:NULL];
        if (![json isKindOfClass:NSDictionary.class]) json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![json isKindOfClass:NSDictionary.class]) return NO;
        return [json[@"app_name"] isEqual:@"SpringBoard"] || [json[@"procName"] isEqual:@"SpringBoard"];
    }
    NSData *head=[data subdataWithRange:NSMakeRange(0,MIN(data.length,16384))];
    NSString *text=[[NSString alloc] initWithData:head encoding:NSUTF8StringEncoding];
    if (!text) return NO;
    NSRegularExpression *process=[NSRegularExpression regularExpressionWithPattern:@"(?m)^Process:[ \\t]+SpringBoard(?:[ \\t]|$)" options:0 error:NULL];
    return [process firstMatchInString:text options:0 range:NSMakeRange(0,text.length)]!=nil;
}
static NSData *ReadReport(NSString *path,NSDictionary *candidate) {
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    if (fd<0) return nil;
    NSMutableData *data=[NSMutableData new];
    struct stat before,after;
    BOOL valid=!fstat(fd,&before) && S_ISREG(before.st_mode) && before.st_uid==getuid() &&
        before.st_nlink==1 && before.st_size>0 && before.st_size<=2*1024*1024 &&
        (uint64_t)before.st_ino==[candidate[@"inode"] unsignedLongLongValue] &&
        (uint64_t)before.st_dev==[candidate[@"device"] unsignedLongLongValue];
    if (valid) {
        uint8_t buffer[16384];
        while (data.length<(NSUInteger)before.st_size) {
            ssize_t n=read(fd,buffer,MIN(sizeof(buffer),(NSUInteger)before.st_size-data.length));
            if (n<0 && errno==EINTR) continue;
            if (n<=0) break;
            [data appendBytes:buffer length:(NSUInteger)n];
        }
        valid=data.length==(NSUInteger)before.st_size && !fstat(fd,&after) &&
            before.st_size==after.st_size && before.st_mtime==after.st_mtime && after.st_nlink==1;
    }
    close(fd);
    return valid && SpringBoardData(data,path.pathExtension) ? data : nil;
}
NSArray<NSURL *> *MSCopyRecentSpringBoardReports(NSArray<NSString *> *directories,NSString *output,NSError **error) {
    if (error) *error=nil;
    NSFileManager *files=NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:output withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return nil;
    NSMutableArray<NSDictionary *> *candidates=[NSMutableArray new];
    NSMutableSet *identities=[NSMutableSet new];
    for (NSString *directory in directories) {
        DIR *handle=opendir(directory.fileSystemRepresentation);
        if (!handle) continue;
        struct dirent *entry;unsigned visited=0;
        while (visited++<4096 && (entry=readdir(handle))) {
            NSString *name=[NSString stringWithUTF8String:entry->d_name];
            if (!name) continue;
            if (!ReportName(name)) continue;
            NSString *path=[directory stringByAppendingPathComponent:name];
            struct stat info;
            if (lstat(path.fileSystemRepresentation,&info) || !S_ISREG(info.st_mode) ||
                info.st_uid!=getuid() || info.st_nlink!=1 || info.st_size<=0 || info.st_size>2*1024*1024) continue;
            NSString *identity=[NSString stringWithFormat:@"%llu:%llu",(unsigned long long)info.st_dev,(unsigned long long)info.st_ino];
            if ([identities containsObject:identity]) continue;
            [identities addObject:identity];
            [candidates addObject:@{@"path":path,@"time":@((double)info.st_mtime),@"inode":@((uint64_t)info.st_ino),@"device":@((uint64_t)info.st_dev)}];
        }
        closedir(handle);
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) { return [b[@"time"] compare:a[@"time"]]; }];
    NSMutableArray<NSURL *> *copied=[NSMutableArray new];
    unsigned attempted=0;
    for (NSDictionary *candidate in candidates) {
        if (attempted++>=16) break;
        NSString *path=candidate[@"path"];
        NSData *data=ReadReport(path,candidate);
        if (!data) continue;
        NSString *name=[NSString stringWithFormat:@"MangoSuite-%@-%@",NSUUID.UUID.UUIDString,path.lastPathComponent];
        NSString *destination=[output stringByAppendingPathComponent:name];
        if (![data writeToFile:destination options:NSDataWritingAtomic error:error] || chmod(destination.fileSystemRepresentation,0600)) return nil;
        [copied addObject:[NSURL fileURLWithPath:destination]];
        if (copied.count==3) break;
    }
    return copied;
}
