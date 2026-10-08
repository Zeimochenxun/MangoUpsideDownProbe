#import <Foundation/Foundation.h>
#import "../../src/CrashReports.h"
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>

int main(int argc,const char *argv[]) { @autoreleasepool {
    assert(argc==2);
    NSString *root=[NSString stringWithUTF8String:argv[1]];
    NSString *source=[root stringByAppendingPathComponent:@"reports"],*output=[root stringByAppendingPathComponent:@"export"];
    NSFileManager *files=NSFileManager.defaultManager;
    assert([files createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSMutableArray<NSString *> *names=[NSMutableArray new];NSMutableArray<NSData *> *original=[NSMutableArray new];
    for (int i=0;i<6;i++) {
        NSString *name=[NSString stringWithFormat:@"SpringBoard-%d.%@",i,i%2 ? @"crash" : @"ips"];
        NSString *text=i%2 ? [NSString stringWithFormat:@"Process: SpringBoard [%d]\nReason: test only\n",i] :
            [NSString stringWithFormat:@"{\"app_name\":\"SpringBoard\"}\n{\"procName\":\"SpringBoard\",\"test\":%d}\n",i];
        NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];NSString *path=[source stringByAppendingPathComponent:name];
        assert([data writeToFile:path atomically:YES]);
        assert([files setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:1000+i]} ofItemAtPath:path error:NULL]);
        [names addObject:name];[original addObject:data];
    }
    NSData *other=[@"{\"app_name\":\"OtherApp\"}\n{}\n" dataUsingEncoding:NSUTF8StringEncoding];
    assert([other writeToFile:[source stringByAppendingPathComponent:@"SpringBoard-wrong.ips"] atomically:YES]);
    assert([original[0] writeToFile:[source stringByAppendingPathComponent:@"OtherApp.ips"] atomically:YES]);
    assert([@"not a crash report" writeToFile:[source stringByAppendingPathComponent:@"SpringBoard-invalid.ips"] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    assert(symlink([[source stringByAppendingPathComponent:names[0]] fileSystemRepresentation],[[source stringByAppendingPathComponent:@"SpringBoard-link.ips"] fileSystemRepresentation])==0);
    NSString *outside=[root stringByAppendingPathComponent:@"hardlink-original.ips"];
    assert([original[0] writeToFile:outside atomically:YES]);
    assert(link(outside.fileSystemRepresentation,[[source stringByAppendingPathComponent:@"SpringBoard-hardlink.ips"] fileSystemRepresentation])==0);
    assert([[NSMutableData dataWithLength:2*1024*1024+1] writeToFile:[source stringByAppendingPathComponent:@"SpringBoard-huge.ips"] atomically:YES]);
    assert([files createDirectoryAtPath:[source stringByAppendingPathComponent:@"SpringBoard-directory.ips"] withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSString *unicodeSource=[root stringByAppendingPathComponent:@"unicode-reports"];
    assert([files createDirectoryAtPath:unicodeSource withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSMutableData *unicode=[[@"Process: SpringBoard [99]\n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if ((16384-unicode.length)%3==0) [unicode appendData:[@"x" dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableString *body=[NSMutableString new];for (int i=0;i<6000;i++) [body appendString:@"你"];
    [unicode appendData:[body dataUsingEncoding:NSUTF8StringEncoding]];
    assert(![[NSString alloc] initWithData:[unicode subdataWithRange:NSMakeRange(0,16384)] encoding:NSUTF8StringEncoding]);
    assert([unicode writeToFile:[unicodeSource stringByAppendingPathComponent:@"SpringBoard-unicode.crash"] atomically:YES]);
    NSArray<NSURL *> *unicodeCopy=MSCopyRecentSpringBoardReports(@[unicodeSource],[root stringByAppendingPathComponent:@"unicode-export"],NULL);
    assert(unicodeCopy.count==1 && [[NSData dataWithContentsOfURL:unicodeCopy[0]] isEqual:unicode]);
    NSError *error=nil;NSArray<NSURL *> *copied=MSCopyRecentSpringBoardReports(@[source,source],output,&error);
    assert(copied.count==3 && !error);
    for (unsigned i=0;i<3;i++) {
        unsigned index=5-i;NSURL *destination=copied[i];
        assert([destination.lastPathComponent hasSuffix:names[index]]);
        assert([[NSData dataWithContentsOfURL:destination] isEqual:original[index]]);
        struct stat info;assert(!lstat(destination.fileSystemRepresentation,&info) && (info.st_mode&0777)==0600 && info.st_uid==getuid());
    }
    for (unsigned i=0;i<names.count;i++) assert([[NSData dataWithContentsOfFile:[source stringByAppendingPathComponent:names[i]]] isEqual:original[i]]);
    assert(MSCopyRecentSpringBoardReports(@[[root stringByAppendingPathComponent:@"missing"]],[root stringByAppendingPathComponent:@"empty"],&error).count==0 && !error);
    NSString *blocked=[root stringByAppendingPathComponent:@"blocked"];
    assert([other writeToFile:blocked atomically:YES]);
    assert(!MSCopyRecentSpringBoardReports(@[source],blocked,&error) && error);
    assert([[NSData dataWithContentsOfFile:blocked] isEqual:other]);
    puts("PASS: production crash collector copies the newest three complete matching reports, preserves source bytes, deduplicates candidates and rejects symlink/hardlink/oversize/wrong-process/directory inputs; UTF-8 boundary, empty and blocked destinations handled");
} return 0; }
