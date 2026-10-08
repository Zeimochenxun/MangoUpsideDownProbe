#import <UIKit/UIKit.h>
#import "Prefs.h"
#import "../src/SuitePreferences.h"
#import "../src/CrashReports.h"
#import <roothide.h>
#include "../src/DiagnosticsPolicy.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

// Export a bounded snapshot; never run a shell or read notification contents.
static NSString *ReadLog(NSString *name, double session) {
    NSString *base = [NSString stringWithUTF8String:jbroot("/var/mobile/Library/Logs/MangoSuiteDiagnostics")];
    NSString *path = [base stringByAppendingPathComponent:[name stringByAppendingString:@".log"]];
    int fd = open(path.fileSystemRepresentation, O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    if (fd < 0) return @"尚无该模块日志，请先开始记录并复现问题。\n";
    NSMutableData *data = [NSMutableData new];
    struct stat info;
    if (!fstat(fd,&info) && S_ISREG(info.st_mode) && info.st_uid == getuid() && info.st_nlink == 1 && info.st_size >= 0 && info.st_size <= 262144) {
        uint8_t buffer[4096];
        while (data.length < 262144) {
            ssize_t n = read(fd,buffer,MIN(sizeof(buffer),262144-data.length));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            [data appendBytes:buffer length:(NSUInteger)n];
        }
    }
    close(fd);
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return @"日志无法读取。\n";
    NSMutableString *current=[NSMutableString new];
    BOOL include=NO;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        const char *bytes=line.UTF8String;
        if (MSDiagnosticRecordHeader(bytes)) include=MSDiagnosticRecordCurrent(bytes,session);
        if (include) [current appendFormat:@"%@\n",line];
    }
    return current.length ? current : @"本次记录尚无该模块日志，请开始记录并复现问题。\n";
}

@interface MangoSuiteDiagnosticsController : MangoSuitePrefsController
@property(nonatomic) BOOL exporting;
- (void)startRecording;
- (void)exportAll;
- (void)exportCrashReports;
- (void)exportModules:(NSArray<NSString *> *)modules crashes:(BOOL)crashes;
- (void)exportGlass;
- (void)exportSplit;
- (void)exportOrientation;
@end
@implementation MangoSuiteDiagnosticsController
- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"调试日志"; _specifiers = [NSMutableArray new];
    [self addSection:nil];
    PSSpecifier *notice=_specifiers.lastObject;
    [notice setProperty:@"开启后记录20分钟；点击开始可重新计时。每个模块最多256KB。日志包含尺寸、方向、动画和开关状态，不保存通知文字或采色截图。隔离模式下仍可记录启动状态。崩溃提取会复制最多3份完整的 SpringBoard 系统原文报告供你分享；未找到报告不表示未崩溃。" forKey:@"footerText"];
    [self addSwitch:@"启用调试记录" key:@"DebugEnabled"];
    NSArray *rows = @[@[@"开始／重新开始记录", NSStringFromSelector(@selector(startRecording))],
        @[@"提取全部相关日志", NSStringFromSelector(@selector(exportAll))],
        @[@"提取最近 SpringBoard 崩溃报告与日志", NSStringFromSelector(@selector(exportCrashReports))],
        @[@"提取边缘、玻璃、光晕与采色日志", NSStringFromSelector(@selector(exportGlass))],
        @[@"提取启动器与分屏日志", NSStringFromSelector(@selector(exportSplit))],
        @[@"提取倒置与上下滑日志", NSStringFromSelector(@selector(exportOrientation))]];
    for (NSArray *row in rows) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:row[0] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [item setButtonAction:NSSelectorFromString(row[1])]; [_specifiers addObject:item];
    }
    return _specifiers;
}
- (void)startRecording {
    NSError *error = nil;
    if (!MSWritePreferenceValue(@"DebugSessionToken", @(NSDate.date.timeIntervalSince1970), &error) ||
        !MSWritePreferenceFlag(@"DebugEnabled", YES, &error)) {
        [self showMessage:error.localizedDescription title:@"记录未能开始"]; return;
    }
    [self reloadSpecifiers];
    [self showMessage:@"已经开始记录。请复现异常，再回到本页点击提取相关日志。" title:@"记录已开始"];
}
- (void)exportModules:(NSArray<NSString *> *)modules {
    [self exportModules:modules crashes:NO];
}
- (void)exportModules:(NSArray<NSString *> *)modules crashes:(BOOL)crashes {
    if (self.exporting) return;
    self.exporting = YES;
    NSDictionary *settings = MSReadPreferences(NULL) ?: @{};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSMutableString *report = [NSMutableString stringWithFormat:@"Mango Suite 1.2.0~beta9.6\nMango 1.0-Beta9-1 / iOS 16.5\n导出时间：%@\n", NSDate.date];
        for (NSString *key in [@[@"Enabled",@"CrashIsolationEnabled",@"IdleEnabled",@"AdaptiveEnabled",@"WorldEnabled",@"SplitEnabled",@"DebugEnabled",@"DebugSessionToken",@"EdgeThickness",@"EdgeDynamics"] arrayByAddingObjectsFromArray:MSRepairKeys()])
            [report appendFormat:@"%@=%@\n",key,settings[key] ?: @"默认"];
        double session=[settings[@"DebugSessionToken"] doubleValue];
        for (NSString *module in modules) [report appendFormat:@"\n========== %@ ==========\n%@",module,ReadLog(module,session)];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MangoSuiteExports"];
        NSFileManager *files = NSFileManager.defaultManager;
        NSError *error = nil;
        BOOL created = [files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
        NSArray *old = created ? [files contentsOfDirectoryAtPath:directory error:NULL] : @[];
        // Only our own named temporary reports are cleaned up.
        for (NSString *name in old)
            if ([name hasPrefix:@"MangoSuite-"] && [@[@"txt",@"ips",@"crash"] containsObject:name.pathExtension.lowercaseString])
                [files removeItemAtPath:[directory stringByAppendingPathComponent:name] error:NULL];
        NSArray<NSURL *> *crashFiles=@[];
        if (crashes && created) {
            crashFiles=MSCopyRecentSpringBoardReports(MSCrashReportDirectories(),directory,&error);
            [report appendFormat:@"\n崩溃报告提取：复制%lu份；最多3份，每份最多2MB，同用户、完整文件且进程标识为 SpringBoard。%@\n",(unsigned long)crashFiles.count,error.localizedDescription ?: @""];
            if (!crashFiles.count) [report appendString:@"未找到可读取的合格报告。可能未生成、位置不同、权限受限或超过限制；这不能证明没有崩溃。可以单独提供原始 .ips／.crash。\n"];
            for (NSURL *file in crashFiles) [report appendFormat:@"report=%@\n",file.lastPathComponent];
        }
        NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"MangoSuite-%@.txt",NSUUID.UUID.UUIDString]];
        BOOL saved = created && [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (saved) chmod(path.fileSystemRepresentation,0600);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.exporting = NO;
            if (!saved) { [self showMessage:error.localizedDescription ?: @"无法生成日志文件。" title:@"提取失败"]; return; }
            NSMutableArray *items=[NSMutableArray arrayWithObject:[NSURL fileURLWithPath:path]];
            [items addObjectsFromArray:crashFiles ?: @[]];
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.view;
            share.popoverPresentationController.sourceRect = self.view.bounds;
            [self presentViewController:share animated:YES completion:nil];
        });
    });
}
- (void)exportAll { [self exportModules:@[@"Startup",@"Idle",@"Glass",@"World",@"Split"]]; }
- (void)exportCrashReports { [self exportModules:@[@"Startup",@"Idle",@"Glass",@"World",@"Split"] crashes:YES]; }
- (void)exportGlass { [self exportModules:@[@"Startup",@"Idle",@"Glass"]]; }
- (void)exportSplit { [self exportModules:@[@"Startup",@"Split"]]; }
- (void)exportOrientation { [self exportModules:@[@"Startup",@"World"]]; }
@end
