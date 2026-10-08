#import <UIKit/UIKit.h>
#import "Prefs.h"
#import "../src/SuitePreferences.h"
#import <roothide.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

// Export a bounded snapshot; never run a shell or read notification contents.
static NSString *ReadLog(NSString *name) {
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
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"日志无法读取。\n";
}

@interface MangoSuiteDiagnosticsController : MangoSuitePrefsController
@property(nonatomic) BOOL exporting;
- (void)startRecording;
- (void)exportAll;
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
    [notice setProperty:@"开启后记录20分钟；点击开始可重新计时。每个模块最多256KB。日志包含尺寸、方向、动画和开关状态，不保存通知文字或采色截图。新修复与采色参数约0.5秒内生效，主模块开关仍需重启用户空间。" forKey:@"footerText"];
    [self addSwitch:@"启用调试记录" key:@"DebugEnabled"];
    NSArray *rows = @[@[@"开始／重新开始记录", NSStringFromSelector(@selector(startRecording))],
        @[@"提取全部相关日志", NSStringFromSelector(@selector(exportAll))],
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
    if (self.exporting) return;
    self.exporting = YES;
    NSDictionary *settings = MSReadPreferences(NULL) ?: @{};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSMutableString *report = [NSMutableString stringWithFormat:@"Mango Suite 1.2.0~beta9.2\nMango 1.0-Beta9-1 / iOS 16.5\n导出时间：%@\n", NSDate.date];
        for (NSString *key in [@[@"Enabled",@"IdleEnabled",@"WorldEnabled",@"SplitEnabled",@"DebugEnabled",@"DebugSessionToken",@"EdgeThickness",@"EdgeDynamics"] arrayByAddingObjectsFromArray:MSRepairKeys()])
            [report appendFormat:@"%@=%@\n",key,settings[key] ?: @"默认"];
        for (NSString *module in modules) [report appendFormat:@"\n========== %@ ==========\n%@",module,ReadLog(module)];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MangoSuiteExports"];
        NSFileManager *files = NSFileManager.defaultManager;
        NSError *error = nil;
        BOOL created = [files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
        NSArray *old = created ? [files contentsOfDirectoryAtPath:directory error:NULL] : @[];
        // Only our own named temporary reports are cleaned up.
        for (NSString *name in old)
            if ([name hasPrefix:@"MangoSuite-"] && [name hasSuffix:@".txt"])
                [files removeItemAtPath:[directory stringByAppendingPathComponent:name] error:NULL];
        NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"MangoSuite-%@.txt",NSUUID.UUID.UUIDString]];
        BOOL saved = created && [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (saved) chmod(path.fileSystemRepresentation,0600);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.exporting = NO;
            if (!saved) { [self showMessage:error.localizedDescription ?: @"无法生成日志文件。" title:@"提取失败"]; return; }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.view;
            share.popoverPresentationController.sourceRect = self.view.bounds;
            [self presentViewController:share animated:YES completion:nil];
        });
    });
}
- (void)exportAll { [self exportModules:@[@"Idle",@"Glass",@"World",@"Split"]]; }
- (void)exportGlass { [self exportModules:@[@"Idle",@"Glass"]]; }
- (void)exportSplit { [self exportModules:@[@"Split"]]; }
- (void)exportOrientation { [self exportModules:@[@"World"]]; }
@end
