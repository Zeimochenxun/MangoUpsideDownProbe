#pragma once
#import <Foundation/Foundation.h>
NSArray<NSString *> *MSCrashReportDirectories(void);
// Copies at most three complete, readable mobile-user SpringBoard reports.
// Does not alter source reports or run a command.
NSArray<NSURL *> *MSCopyRecentSpringBoardReports(NSArray<NSString *> *directories,
                                               NSString *output,NSError **error);
