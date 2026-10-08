"""Execute production notification routing against Foundation view/provider stubs."""
from pathlib import Path
import re
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/"modules/visual/MangoIdleIsland/Tweak.m").read_text(encoding="utf-8")
def extract(name):
    match=re.search(r"^static [^\n]+\b"+name+r"\([^\n]*\) \{",SOURCE,re.M)
    assert match,name
    depth,end=1,match.end()
    while depth:
        if SOURCE[end]=="{":depth+=1
        elif SOURCE[end]=="}":depth-=1
        end+=1
    return SOURCE[match.start():end]
STUBS=r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <assert.h>
#include <string.h>
#include <stdio.h>
@interface UIView : NSObject
@property(nonatomic,weak) UIView *superview;
@end
@implementation UIView
@end
@interface Host : UIView
@end
@implementation Host
@end
@interface Provider : NSObject
@property(nonatomic,strong) UIView *providedView;
@end
@implementation Provider
@end
@interface Aggregate : NSObject
@property(nonatomic,strong) Provider *primaryContentViewProvider;
@end
@implementation Aggregate
@end
@interface Pill : NSObject
@property(nonatomic,strong) id userNotification,layoutHost;
@property(nonatomic,strong) Aggregate *viewProvider;
@end
@implementation Pill
@end
static Class HostClass;
static NSHashTable<id> *Pills;
static unsigned NotificationHooks=15;
static __weak UIView *CapturedHost;
static BOOL CapturedNotification;
static unsigned Captures;
// Test image-origin gate accepts only our fixture classes. Actual Mango class
// identity/UUID verification is separately compiled against the iOS runtime.
static BOOL B9ClassIsHello(Class cls) { return cls==Pill.class || cls==Provider.class || cls==Aggregate.class; }
static NSDictionary *MSRuntimeSettings(void) { return @{@"DebugSessionToken":@1}; }
static BOOL MSDiagnosticsActive(void) { return NO; }
static void MSDiagnosticsLog(NSString *module,NSString *message) { (void)module;(void)message; }
static void MSIslandNotificationState(id element,UIView *host,BOOL notification) {
    assert(element);CapturedHost=host;CapturedNotification=notification;++Captures;
}
'''
CASES=r'''
int main(void) { @autoreleasepool {
    HostClass=Host.class;
    Host *host=[Host new];UIView *view=[UIView new];view.superview=host;
    Provider *provider=[Provider new];provider.providedView=view;
    Aggregate *aggregate=[Aggregate new];aggregate.primaryContentViewProvider=provider;
    Pill *pill=[Pill new];pill.viewProvider=aggregate;pill.userNotification=[NSObject new];
    // Negative control: Beta9.3 asked the aggregate for providedView, which it
    // does not have. The current production code reaches the primary provider.
    assert(![aggregate respondsToSelector:sel_registerName("providedView")]);
    NotificationRefresh(pill);assert(CapturedHost==host && CapturedNotification && Captures==1);
    pill.userNotification=nil;NotificationRefresh(pill);
    assert(CapturedHost==host && !CapturedNotification && Captures==2);
    pill.userNotification=[NSObject new];view.superview=nil;NotificationRefresh(pill);
    assert(!CapturedHost && CapturedNotification && Captures==3);
    pill.layoutHost=host;NotificationRefresh(pill);assert(CapturedHost==host && CapturedNotification);
    pill.layoutHost=[NSObject new];pill.viewProvider=nil;NotificationRefresh(pill);assert(!CapturedHost);
    assert(Pills.count==1);
    puts("PASS: production notification routing reaches aggregate primary provider, honors structured notification presence, removes detached/reused hosts and accepts direct layout host; Beta9.3 aggregate negative control reproduces missed halo identification");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix="mango-notification-routing-") as directory:
    source,binary=Path(directory)/"routing.m",Path(directory)/"routing"
    source.write_text(STUBS+"\n"+"\n".join(extract(n) for n in ("ClassMethodSignature","HostFor","VerifiedObject","NotificationRefresh"))+CASES,encoding="utf-8")
    subprocess.run(["xcrun","clang","-fobjc-arc","-Wall","-Wextra","-Werror","-framework","Foundation",str(source),"-o",str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
