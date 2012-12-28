//  Copyright (c) 2012 Rob Mayoff. All rights reserved.

#import "DqdObserverSet.h"
#import "Lidar2D.h"
#import "NSData+Lidar2D.h"
#import "TouchCalibration.h"
#import "TouchDetector.h"
#import "TouchThresholdCalibration.h"
#import <vector>

using std::vector;

@interface TouchDetector () <Lidar2DObserver, TouchThresholdCalibrationDelegate, TouchCalibrationDelegate>
@end

@implementation TouchDetector {
    Lidar2D *device_;
    DqdObserverSet *observers_;
    void (^distancesReportHandler_)(NSData *distanceData);
    TouchThresholdCalibration *touchThresholdCalibration_;
    TouchCalibration *touchCalibration_;
    NSString *calibrationDataKey_;
    
    Lidar2DDistance touchDistance_;
}

#pragma mark - Public API

- (void)dealloc {
    [device_ removeObserver:self];
}

- (id)initWithDevice:(Lidar2D *)device {
    if ((self = [super init])) {
        device_ = device;
        [device addObserver:self];
        touchThresholdCalibration_ = [[TouchThresholdCalibration alloc] init];
        touchThresholdCalibration_.delegate = self;
        touchCalibration_ = [[TouchCalibration alloc] init];
        touchCalibration_.delegate = self;
        touchCalibration_.thresholdCalibration = touchThresholdCalibration_;
        [self setAppropriateNonBusyState];
    }
    return self;
}

- (void)reset {
    [touchThresholdCalibration_ reset];
    [touchCalibration_ reset];
    [self setAppropriateNonBusyState];
}

@synthesize state = _state;

- (BOOL)canStartCalibratingTouchThreshold {
    return ![self isBusy] && device_.isConnected;
}

- (void)startCalibratingTouchThreshold {
    [self requireNotBusy];
    [touchThresholdCalibration_ reset];
    self.state = TouchDetectorState_CalibratingTouchThreshold;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(NSData *distanceData) {
        TouchDetector *self = me;
        [self calibrateTouchThresholdWithDistanceData:distanceData];
    };
}

- (BOOL)canStartCalibratingTouchAtPoint {
    return ![self isBusy] && device_.isConnected && touchThresholdCalibration_.ready;
}

- (void)startCalibratingTouchAtPoint:(CGPoint)point {
    [self requireNotBusy];
    [touchCalibration_ startCalibratingTouchAtScreenPoint:point];
    self.state = TouchDetectorState_CalibratingTouch;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(NSData *distanceData) {
        TouchDetector *self = me;
        [self calibrateTouchWithDistanceData:distanceData];
    };
}

- (void)addObserver:(id<TouchDetectorObserver>)observer {
    if (!observers_) {
        observers_ = [[DqdObserverSet alloc] initWithProtocol:@protocol(TouchDetectorObserver)];
    }
    [observers_ addObserver:observer];
}

- (void)removeObserver:(id<TouchDetectorObserver>)observer {
    [observers_ removeObserver:observer];
}

- (void)notifyObserverOfCurrentState:(id<TouchDetectorObserver>)observer {
    switch (_state) {
        case TouchDetectorState_AwaitingTouchThresholdCalibration:
            [observer touchDetectorIsAwaitingTouchThresholdCalibration:self];
            break;
        case TouchDetectorState_CalibratingTouchThreshold:
            [observer touchDetectorIsCalibratingTouchThreshold:self];
            break;
        case TouchDetectorState_AwaitingTouchCalibration:
            [observer touchDetectorIsAwaitingTouchCalibration:self];
            break;
        case TouchDetectorState_CalibratingTouch:
            [observer touchDetector:self isCalibratingTouchAtPoint:touchCalibration_.currentCalibrationScreenPoint];
            break;
        case TouchDetectorState_DetectingTouches:
            [observer touchDetectorIsDetectingTouches:self];
            break;
    }
}

#pragma mark - Lidar2DObserver protocol

- (void)lidar2dDidConnect:(Lidar2D *)device {
    touchCalibration_.radiansPerRay = device.coverageDegrees * (2 * M_PI / 360.0) / device.rayCount;
    calibrationDataKey_ = [@"calibration-" stringByAppendingString:device.serialNumber];
    [self loadCalibrationData];
    [self setAppropriateNonBusyState];
}

-  (void)lidar2DDidTerminate:(Lidar2D *)device {
    (void)device;
    // Nothing to do
}

- (void)lidar2d:(Lidar2D *)device didReceiveDistanceData:(NSData *)distanceData {
    (void)device;
    if (distancesReportHandler_) {
        distancesReportHandler_(distanceData);
    }
}

#pragma mark - Implementation details - general state management

- (void)setState:(TouchDetectorState)state {
    if (_state != state) {
        _state = state;
        [self saveCalibrationData];
        [self notifyObserverOfCurrentState:observers_.proxy];
    }
}

- (void)setAppropriateNonBusyState {
    TouchDetectorState newState =
        !touchThresholdCalibration_.ready ? TouchDetectorState_AwaitingTouchThresholdCalibration
        : !touchCalibration_.ready ? TouchDetectorState_AwaitingTouchCalibration
        : TouchDetectorState_DetectingTouches;
    if (newState != _state) {
        self.state = newState;
        if (newState == TouchDetectorState_DetectingTouches) {
            [self startDetectingTouches];
        }
    }
}

// When this returns YES, it means I'm doing something that reads from the device, so I can't start anything new that reads from the device.
- (BOOL)isBusy {
    switch (_state) {
        case TouchDetectorState_AwaitingTouchThresholdCalibration: return NO;
        case TouchDetectorState_CalibratingTouchThreshold: return YES;
        case TouchDetectorState_AwaitingTouchCalibration: return NO;
        case TouchDetectorState_CalibratingTouch: return YES;
        case TouchDetectorState_DetectingTouches: return NO;
    }
}

// I throw an exception if I'm busy.
- (void)requireNotBusy {
    if ([self isBusy]) {
        [NSException raise:NSInternalInconsistencyException format:@"received %s while in state %@", __func__, [self stateString]];
    }
}

- (NSString *)stateString {
#define StateString(State) case TouchDetectorState_##State: return @#State
    switch (_state) {
        StateString(AwaitingTouchThresholdCalibration);
        StateString(CalibratingTouchThreshold);
        StateString(AwaitingTouchCalibration);
        StateString(CalibratingTouch);
        StateString(DetectingTouches);
    }
#undef StateString
}

#pragma mark - Calibration data serialization

static NSString *const kTouchThresholdKey = @"touchThreshold";
static NSString *const kTouchKey = @"touch";

- (void)loadCalibrationData {
    NSDictionary *plist = [[NSUserDefaults standardUserDefaults] valueForKey:calibrationDataKey_];
    if (plist) {
        [touchThresholdCalibration_ restoreDataPropertyList:plist[kTouchThresholdKey]];
        [touchCalibration_ restoreDataPropertyList:plist[kTouchKey]];
    }
}

- (void)saveCalibrationData {
    NSDictionary *plist = @{
        kTouchThresholdKey: [touchThresholdCalibration_ dataPropertyList],
        kTouchKey: [touchCalibration_ dataPropertyList]
    };
    [[NSUserDefaults standardUserDefaults] setValue:plist forKey:calibrationDataKey_];
}

#pragma mark - Touch threshold calibration details

- (void)calibrateTouchThresholdWithDistanceData:(NSData *)distanceData {
    [touchThresholdCalibration_ calibrateWithDistanceData:distanceData];
    [self stopCalibratingTouchThresholdIfReady];
}

- (void)stopCalibratingTouchThresholdIfReady {
    if (touchThresholdCalibration_.ready) {
        distancesReportHandler_ = nil;
        [observers_.proxy touchDetectorDidFinishCalibratingTouchThreshold:self];
        [self setAppropriateNonBusyState];
    }
}

- (void)touchThresholdCalibration:(TouchThresholdCalibration *)calibration didUpdateThresholds:(const Lidar2DDistance *)thresholds count:(NSUInteger)count {
    (void)calibration;
    [observers_.proxy touchDetector:self didUpdateTouchThresholds:thresholds count:count];
}

#pragma mark - Touch calibration details

- (void)calibrateTouchWithDistanceData:(NSData *)distanceData {
    [touchCalibration_ calibrateWithDistanceData:distanceData];
}

- (void)touchCalibrationDidSucceed {
    [self stopCalibratingTouchWithResult:TouchCalibrationResult_Success];
}

- (void)touchCalibrationDidFailWithMultipleTouches {
    [self stopCalibratingTouchWithResult:TouchCalibrationResult_MultipleTouchesDetected];
}

- (void)touchCalibrationDidFailWithNoTouches {
    [self stopCalibratingTouchWithResult:TouchCalibrationResult_NoTouchDetected];
}

- (void)stopCalibratingTouchWithResult:(TouchCalibrationResult)result {
    distancesReportHandler_ = nil;
    [observers_.proxy touchDetector:self didFinishCalibratingTouchAtPoint:touchCalibration_.currentCalibrationScreenPoint withResult:result];
    [self setAppropriateNonBusyState];
}

#pragma mark - Touch detection details

static BOOL isValidScreenPoint(CGPoint point) {
    for (NSScreen *screen in [NSScreen screens]) {
        if (CGRectContainsPoint(screen.frame, point))
            return YES;
    }
    return NO;
}

- (void)detectTouchesWithDistanceData:(NSData *)distanceData {
    __block vector<CGPoint> touchPoints;
    Lidar2DDistance const *distances = distanceData.lidar2D_distances;

#if 0

    [touchThresholdCalibration_ forEachTouchedSweepInDistanceData:distanceData do:^(NSRange sweepRange) {
        NSUInteger middleRayIndex = sweepRange.location + sweepRange.length / 2;
        Lidar2DDistance distance = distances[middleRayIndex];
        CGPoint sensorPoint = [self sensorPointForRayIndex:middleRayIndex distance:distance];
        CGPoint screenPoint = [self screenPointForSensorPoint:sensorPoint];
        if (isValidScreenPoint(screenPoint)) {
            touchPoints.push_back(screenPoint);
        }
    }];

#else

    // Alternative implementation. Only accepts touches with at least 3 consecutive touched rays; uses angle of middle ray and averaged distance of all rays except first and last.
    float currentDistanceWeight = 0.3;
    [touchThresholdCalibration_ forEachTouchedSweepInDistanceData:distanceData do:^(NSRange sweepRange) {
        if (sweepRange.length < 3)
            return;
        ++sweepRange.location;
        sweepRange.length -= 2;
        Lidar2DDistance sum = 0;
        for (NSUInteger i = 0; i < sweepRange.length; ++i) {
            sum += distances[sweepRange.location + i];
        }
        
        NSUInteger middleRayIndex = sweepRange.location + sweepRange.length / 2;
        Lidar2DDistance currentDistance = sum / sweepRange.length;
        touchDistance_ = (touchDistance_ > 0)
            ? currentDistanceWeight * currentDistance + (1.0 - currentDistanceWeight) * touchDistance_
            : currentDistance;

        CGPoint screenPoint = [touchCalibration_ screenPointForRayIndex:middleRayIndex distance:touchDistance_];
        if (isValidScreenPoint(screenPoint)) {
            touchPoints.push_back(screenPoint);
        }
    }];

    if(touchPoints.size() == 0) {
        touchDistance_ = -1.0;
    }

#endif

    [observers_.proxy touchDetector:self didDetectTouches:touchPoints.size() atScreenPoints:touchPoints.data()];
}

- (void)startDetectingTouches {
    self.state = TouchDetectorState_DetectingTouches;

    __weak TouchDetector *me = self;
    distancesReportHandler_ = ^(NSData *distanceData) {
        [me detectTouchesWithDistanceData:distanceData];
    };
}

@end
