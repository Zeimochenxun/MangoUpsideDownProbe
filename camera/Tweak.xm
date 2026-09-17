// MangoUpsideDownCamera 2.0.0
// iOS 16.5 / RootHide prototype.
//
// This version no longer tries to rotate app UI. It hooks AVFoundation's
// capture connection layer and forces video connections to
// AVCaptureVideoOrientationPortraitUpsideDown while the device is physically
// inverted. Existing connections are tracked and refreshed on device rotation.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>

static const char *CXDisabled="/var/mobile/Library/Preferences/MangoUpsideDownCamera.disabled";
static const char *CXLogPath="/var/mobile/Library/Logs/MangoUpsideDownCamera.log";

static NSHashTable<AVCaptureConnection *> *CXConnections;
static NSMapTable<AVCaptureConnection *,NSNumber *> *CXRequestedOrientations;
static BOOL CXUpsideDown;
static __thread BOOL CXInternalWrite;

static NSString *CXIdentity(void){
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier?:@"(no-bundle)";
    NSString *process=NSProcessInfo.processInfo.processName?:@"?";
    return [NSString stringWithFormat:@"%@/%@",process,bundle];
}

static void CXLog(NSString *message){
    NSString *line=[NSString stringWithFormat:@"[%@] %@",CXIdentity(),message];
    NSLog(@"[MangoUDCamera] %@",line);
    mkdir("/var/mobile/Library/Logs",0755);
    int fd=open(CXLogPath,O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW,0600);
    if(fd<0)return;
    struct stat st;
    if(fstat(fd,&st)!=0||!S_ISREG(st.st_mode)){close(fd);return;}
    if(st.st_size>512*1024)ftruncate(fd,0);
    NSData *bytes=[[NSString stringWithFormat:@"%.3f %@\n",NSDate.timeIntervalSinceReferenceDate,line] dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *p=bytes.bytes;size_t left=bytes.length;
    while(left){ssize_t n=write(fd,p,left);if(n<0&&errno==EINTR)continue;if(n<=0)break;p+=n;left-=(size_t)n;}
    close(fd);
}

static BOOL CXSupportsOrientation(AVCaptureConnection *connection){
    if(!connection)return NO;
    @try{return connection.isVideoOrientationSupported;}@catch(__unused NSException *e){return NO;}
}

static BOOL CXIsUpsideDown(void){
    @synchronized(CXConnections){return CXUpsideDown;}
}

static void CXWriteOrientation(AVCaptureConnection *connection,AVCaptureVideoOrientation orientation){
    if(!CXSupportsOrientation(connection))return;
    BOOL previous=CXInternalWrite;CXInternalWrite=YES;
    @try{
        if(connection.videoOrientation!=orientation)connection.videoOrientation=orientation;
    }@catch(NSException *e){
        CXLog([NSString stringWithFormat:@"WRITE failed connection=%p error=%@",(__bridge void *)connection,e]);
    }@finally{CXInternalWrite=previous;}
}

static void CXTrackConnection(AVCaptureConnection *connection){
    if(!connection||!CXSupportsOrientation(connection))return;
    BOOL isNew=NO,force=NO;
    @synchronized(CXConnections){
        if(![CXConnections containsObject:connection]){
            isNew=YES;[CXConnections addObject:connection];
            if(![CXRequestedOrientations objectForKey:connection]){
                @try{[CXRequestedOrientations setObject:@(connection.videoOrientation) forKey:connection];}@catch(__unused NSException *e){}
            }
        }
        force=CXUpsideDown;
    }
    if(isNew)CXLog([NSString stringWithFormat:@"TRACK connection=%p orientation=%ld",(__bridge void *)connection,(long)connection.videoOrientation]);
    if(force)CXWriteOrientation(connection,AVCaptureVideoOrientationPortraitUpsideDown);
}

static void CXTrackOutput(AVCaptureOutput *output){
    if(!output)return;
    NSArray<AVCaptureConnection *> *connections=nil;
    @try{connections=output.connections;}@catch(__unused NSException *e){return;}
    for(AVCaptureConnection *connection in connections)CXTrackConnection(connection);
}

static void CXTrackSession(AVCaptureSession *session){
    if(!session)return;
    NSArray<AVCaptureOutput *> *outputs=nil;
    @try{outputs=session.outputs;}@catch(__unused NSException *e){return;}
    for(AVCaptureOutput *output in outputs)CXTrackOutput(output);
}

static void CXApplyAll(void){
    NSArray<AVCaptureConnection *> *connections=nil;BOOL upside=NO;
    @synchronized(CXConnections){connections=CXConnections.allObjects;upside=CXUpsideDown;}
    for(AVCaptureConnection *connection in connections){
        if(!CXSupportsOrientation(connection))continue;
        if(upside){
            CXWriteOrientation(connection,AVCaptureVideoOrientationPortraitUpsideDown);
        }else{
            NSNumber *saved=nil;
            @synchronized(CXConnections){saved=[CXRequestedOrientations objectForKey:connection];}
            if(saved)CXWriteOrientation(connection,(AVCaptureVideoOrientation)saved.integerValue);
        }
    }
}

static void CXRefreshDeviceOrientation(void){
    if(access(CXDisabled,F_OK)==0){
        BOOL changed=NO;
        @synchronized(CXConnections){if(CXUpsideDown){CXUpsideDown=NO;changed=YES;}}
        if(changed)CXApplyAll();
        return;
    }

    UIDeviceOrientation orientation=UIDevice.currentDevice.orientation;
    BOOL valid=NO,newValue=NO;
    switch(orientation){
        case UIDeviceOrientationPortraitUpsideDown: valid=YES;newValue=YES;break;
        case UIDeviceOrientationPortrait:
        case UIDeviceOrientationLandscapeLeft:
        case UIDeviceOrientationLandscapeRight: valid=YES;newValue=NO;break;
        default:return;
    }
    if(!valid)return;

    BOOL changed=NO;
    @synchronized(CXConnections){if(CXUpsideDown!=newValue){CXUpsideDown=newValue;changed=YES;}}
    if(!changed)return;
    CXLog(newValue?@"STATE entered PortraitUpsideDown":@"STATE left PortraitUpsideDown");
    CXApplyAll();
}

%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)orientation {
    if(CXInternalWrite){%orig(orientation);return;}
    if(![self isVideoOrientationSupported]){%orig(orientation);return;}

    @synchronized(CXConnections){
        [CXConnections addObject:self];
        [CXRequestedOrientations setObject:@(orientation) forKey:self];
    }

    if(CXIsUpsideDown()&&access(CXDisabled,F_OK)!=0){
        CXLog([NSString stringWithFormat:@"INTERCEPT connection=%p requested=%ld -> upsideDown",(__bridge void *)self,(long)orientation]);
        %orig(AVCaptureVideoOrientationPortraitUpsideDown);
        return;
    }
    %orig(orientation);
}

%end

%hook AVCaptureSession

- (void)addOutput:(AVCaptureOutput *)output {
    %orig(output);
    CXTrackOutput(output);
    if(CXIsUpsideDown())CXApplyAll();
}

- (void)commitConfiguration {
    %orig;
    CXTrackSession(self);
    if(CXIsUpsideDown())CXApplyAll();
}

- (void)startRunning {
    %orig;
    CXTrackSession(self);
    if(CXIsUpsideDown())CXApplyAll();
}

%end

%hook AVCaptureOutput

- (NSArray<AVCaptureConnection *> *)connections {
    NSArray<AVCaptureConnection *> *result=%orig;
    for(AVCaptureConnection *connection in result)CXTrackConnection(connection);
    return result;
}

%end

%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session {
    %orig(session);
    CXTrackSession(session);
    CXTrackConnection(self.connection);
}

- (AVCaptureConnection *)connection {
    AVCaptureConnection *result=%orig;
    CXTrackConnection(result);
    return result;
}

%end

%ctor {
    @autoreleasepool {
        CXConnections=[NSHashTable weakObjectsHashTable];
        CXRequestedOrientations=[NSMapTable weakToStrongObjectsMapTable];
        CXUpsideDown=NO;

        // Explicitly initialize Logos hooks. This custom constructor must not
        // rely on implicit hook initialization.
        %init;

        dispatch_async(dispatch_get_main_queue(),^{
            [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
            [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification
                                                             object:UIDevice.currentDevice
                                                              queue:NSOperationQueue.mainQueue
                                                         usingBlock:^(__unused NSNotification *note){CXRefreshDeviceOrientation();}];
            CXRefreshDeviceOrientation();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{CXRefreshDeviceOrientation();});
        });

        CXLog(@"INSTALLED 2.0.0 AVFoundation connection hook");
    }
}
