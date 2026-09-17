#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - UIDevice declarations without linking UIKit

typedef NS_ENUM(NSInteger, CXUIDeviceOrientation) {
    CXUIDeviceOrientationUnknown = 0,
    CXUIDeviceOrientationPortrait = 1,
    CXUIDeviceOrientationPortraitUpsideDown = 2,
    CXUIDeviceOrientationLandscapeLeft = 3,
    CXUIDeviceOrientationLandscapeRight = 4,
    CXUIDeviceOrientationFaceUp = 5,
    CXUIDeviceOrientationFaceDown = 6
};

@interface NSObject (CXUIDeviceMethods)
+ (id)currentDevice;
- (void)beginGeneratingDeviceOrientationNotifications;
- (NSInteger)orientation;
@end

#pragma mark - Globals

static NSHashTable<AVCaptureConnection *> *gTrackedConnections = nil;
static NSMapTable<AVCaptureConnection *, NSNumber *> *gRequestedOrientations = nil;
static BOOL gUpsideDownActive = NO;
static __thread BOOL gInternalOrientationWrite = NO;

#define CXLog(fmt, ...) NSLog(@"[MangoUpsideDownCamera] " fmt, ##__VA_ARGS__)

#pragma mark - Forward declarations

static void CXTrackConnection(AVCaptureConnection *connection);
static void CXTrackOutput(AVCaptureOutput *output);
static void CXTrackSession(AVCaptureSession *session);
static void CXApplyOrientationToAllConnections(void);
static void CXUpdateDeviceOrientationState(void);

#pragma mark - Helpers

static BOOL CXConnectionSupportsOrientation(AVCaptureConnection *connection)
{
    if (!connection) return NO;

    @try {
        return [connection isVideoOrientationSupported];
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static BOOL CXIsUpsideDownActive(void)
{
    @synchronized (gTrackedConnections) {
        return gUpsideDownActive;
    }
}

static void CXWriteOrientation(AVCaptureConnection *connection,
                               AVCaptureVideoOrientation orientation)
{
    if (!CXConnectionSupportsOrientation(connection)) return;

    BOOL previousInternalState = gInternalOrientationWrite;
    gInternalOrientationWrite = YES;

    @try {
        if (connection.videoOrientation != orientation) {
            connection.videoOrientation = orientation;
        }
    } @catch (NSException *exception) {
        CXLog(@"Failed setting orientation on %@: %@", connection, exception);
    } @finally {
        gInternalOrientationWrite = previousInternalState;
    }
}

static void CXRecordRequestedOrientation(AVCaptureConnection *connection,
                                         AVCaptureVideoOrientation orientation)
{
    if (!connection) return;

    @synchronized (gTrackedConnections) {
        [gTrackedConnections addObject:connection];
        [gRequestedOrientations setObject:@(orientation) forKey:connection];
    }
}

static void CXTrackConnection(AVCaptureConnection *connection)
{
    if (!connection || !CXConnectionSupportsOrientation(connection)) return;

    BOOL isNew = NO;
    BOOL forceUpsideDown = NO;

    @synchronized (gTrackedConnections) {
        if (![gTrackedConnections containsObject:connection]) {
            isNew = YES;
            [gTrackedConnections addObject:connection];

            if (![gRequestedOrientations objectForKey:connection]) {
                @try {
                    [gRequestedOrientations setObject:@(connection.videoOrientation)
                                                forKey:connection];
                } @catch (__unused NSException *exception) {
                }
            }
        }

        forceUpsideDown = gUpsideDownActive;
    }

    if (isNew) {
        CXLog(@"Tracking connection %@", connection);
    }

    if (forceUpsideDown) {
        CXWriteOrientation(connection,
                           AVCaptureVideoOrientationPortraitUpsideDown);
    }
}

static void CXTrackOutput(AVCaptureOutput *output)
{
    if (!output) return;

    NSArray<AVCaptureConnection *> *connections = nil;
    @try {
        connections = output.connections;
    } @catch (__unused NSException *exception) {
        return;
    }

    for (AVCaptureConnection *connection in connections) {
        CXTrackConnection(connection);
    }
}

static void CXTrackSession(AVCaptureSession *session)
{
    if (!session) return;

    NSArray<AVCaptureOutput *> *outputs = nil;
    @try {
        outputs = session.outputs;
    } @catch (__unused NSException *exception) {
        return;
    }

    for (AVCaptureOutput *output in outputs) {
        CXTrackOutput(output);
    }
}

static void CXApplyOrientationToAllConnections(void)
{
    NSArray<AVCaptureConnection *> *connections = nil;
    BOOL upsideDown = NO;

    @synchronized (gTrackedConnections) {
        connections = gTrackedConnections.allObjects;
        upsideDown = gUpsideDownActive;
    }

    for (AVCaptureConnection *connection in connections) {
        if (!CXConnectionSupportsOrientation(connection)) continue;

        if (upsideDown) {
            CXWriteOrientation(connection,
                               AVCaptureVideoOrientationPortraitUpsideDown);
            continue;
        }

        NSNumber *savedOrientation = nil;
        @synchronized (gTrackedConnections) {
            savedOrientation = [gRequestedOrientations objectForKey:connection];
        }

        if (!savedOrientation) continue;

        CXWriteOrientation(connection,
                           (AVCaptureVideoOrientation)savedOrientation.integerValue);
    }
}

static void CXUpdateDeviceOrientationState(void)
{
    Class UIDeviceClass = NSClassFromString(@"UIDevice");
    if (!UIDeviceClass || ![UIDeviceClass respondsToSelector:@selector(currentDevice)]) {
        return;
    }

    id device = nil;
    NSInteger orientation = CXUIDeviceOrientationUnknown;

    @try {
        device = [UIDeviceClass currentDevice];
        orientation = [device orientation];
    } @catch (__unused NSException *exception) {
        return;
    }

    BOOL hasNewState = NO;
    BOOL newUpsideDownState = NO;

    switch (orientation) {
        case CXUIDeviceOrientationPortraitUpsideDown:
            hasNewState = YES;
            newUpsideDownState = YES;
            break;

        case CXUIDeviceOrientationPortrait:
        case CXUIDeviceOrientationLandscapeLeft:
        case CXUIDeviceOrientationLandscapeRight:
            hasNewState = YES;
            newUpsideDownState = NO;
            break;

        case CXUIDeviceOrientationUnknown:
        case CXUIDeviceOrientationFaceUp:
        case CXUIDeviceOrientationFaceDown:
        default:
            break;
    }

    if (!hasNewState) return;

    BOOL stateChanged = NO;
    @synchronized (gTrackedConnections) {
        if (gUpsideDownActive != newUpsideDownState) {
            gUpsideDownActive = newUpsideDownState;
            stateChanged = YES;
        }
    }

    if (!stateChanged) return;

    CXLog(@"Device %@ PortraitUpsideDown",
          newUpsideDownState ? @"entered" : @"left");

    CXApplyOrientationToAllConnections();
}

#pragma mark - Hooks

%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)orientation
{
    if (gInternalOrientationWrite) {
        %orig(orientation);
        return;
    }

    BOOL supported = NO;
    @try {
        supported = [self isVideoOrientationSupported];
    } @catch (__unused NSException *exception) {
        supported = NO;
    }

    if (!supported) {
        %orig(orientation);
        return;
    }

    CXRecordRequestedOrientation(self, orientation);

    if (CXIsUpsideDownActive()) {
        CXLog(@"Intercept orientation %ld -> PortraitUpsideDown on %@",
              (long)orientation, self);
        %orig(AVCaptureVideoOrientationPortraitUpsideDown);
        return;
    }

    %orig(orientation);
}

%end

%hook AVCaptureSession

- (void)addOutput:(AVCaptureOutput *)output
{
    %orig(output);
    CXTrackOutput(output);

    if (CXIsUpsideDownActive()) {
        CXApplyOrientationToAllConnections();
    }
}

- (void)commitConfiguration
{
    %orig;
    CXTrackSession(self);

    if (CXIsUpsideDownActive()) {
        CXApplyOrientationToAllConnections();
    }
}

- (void)startRunning
{
    %orig;
    CXTrackSession(self);

    if (CXIsUpsideDownActive()) {
        CXApplyOrientationToAllConnections();
    }
}

%end

%hook AVCaptureOutput

- (NSArray<AVCaptureConnection *> *)connections
{
    NSArray<AVCaptureConnection *> *connections = %orig;

    for (AVCaptureConnection *connection in connections) {
        CXTrackConnection(connection);
    }

    return connections;
}

%end

%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session
{
    %orig(session);
    CXTrackSession(session);

    AVCaptureConnection *connection = nil;
    @try {
        connection = self.connection;
    } @catch (__unused NSException *exception) {
    }

    CXTrackConnection(connection);
}

- (AVCaptureConnection *)connection
{
    AVCaptureConnection *connection = %orig;
    CXTrackConnection(connection);
    return connection;
}

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {
        gTrackedConnections = [NSHashTable weakObjectsHashTable];
        gRequestedOrientations = [NSMapTable weakToStrongObjectsMapTable];

        Class UIDeviceClass = NSClassFromString(@"UIDevice");
        if (!UIDeviceClass || ![UIDeviceClass respondsToSelector:@selector(currentDevice)]) {
            CXLog(@"UIDevice unavailable in %@ (%@); hook is passive",
                  NSProcessInfo.processInfo.processName,
                  NSBundle.mainBundle.bundleIdentifier);
            return;
        }

        id device = nil;
        @try {
            device = [UIDeviceClass currentDevice];
            if ([device respondsToSelector:@selector(beginGeneratingDeviceOrientationNotifications)]) {
                [device beginGeneratingDeviceOrientationNotifications];
            }
        } @catch (NSException *exception) {
            CXLog(@"Failed starting UIDevice orientation: %@", exception);
            return;
        }

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"UIDeviceOrientationDidChangeNotification"
                        object:device
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {
                        CXUpdateDeviceOrientationState();
                    }];

        dispatch_async(dispatch_get_main_queue(), ^{
            CXUpdateDeviceOrientationState();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                CXUpdateDeviceOrientationState();
            });
        });

        CXLog(@"Loaded into %@ (%@)",
              NSProcessInfo.processInfo.processName,
              NSBundle.mainBundle.bundleIdentifier);
    }
}
