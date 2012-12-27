//
//  TouchDetector.h
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/13/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSData+Lidar2D.h"

typedef enum {
    TouchDetectorState_AwaitingTouchThresholdCalibration, // I need to calibrate my touch threshold parameters.  Tell the user to remove all obstructions (touches) from the sensitive area and then send me `calibrateTouchThreshold`.
    TouchDetectorState_CalibratingTouchThreshold, // I am currently calibrating my touch threshold parameters.  Tell the user not to obstruct (touch) the sensitive area.
    TouchDetectorState_AwaitingTouchCalibration, // I need to calibrate my touch-mapping parameters.  Show the user a point in the sensitive area and ask her to touch it, then send me `calibrateTouchAtPoint:`.
    TouchDetectorState_CalibratingTouch, // I am currently calibrating my touch-mapping parameters.  Tell the user to touch the point you sent me in the most recent `calibrateTouchAtPoint:` message.
    TouchDetectorState_DetectingTouches, //
} TouchDetectorState;

typedef enum {
    TouchCalibrationResult_Success,
    TouchCalibrationResult_NoTouchDetected,
    TouchCalibrationResult_MultipleTouchesDetected
} TouchCalibrationResult;

@protocol TouchDetectorObserver;

@interface TouchDetector : NSObject

- (id)initWithDevice:(Lidar2D *)device;

@property (nonatomic, readonly) TouchDetectorState state;

// This is YES when you can send me `startCalibratingTouchThreshold`.  I check my state and whether the device is connected.
@property (nonatomic, readonly) BOOL canStartCalibratingTouchThreshold;

// When I receive this, I calibrate my data parameters on the assumption that nothing is currently touching the screen.  I take several readings after receiving this message.  You can send me this at any time to recalibrate my idle parameters.  If I'm in state `TouchDetectorState_AwaitingIdleCalibration`, I will change to state `TouchDetectorState_AwaitingTouchCalibration` and notify my delegate when I finish calibrating my idle parameters.
- (void)startCalibratingTouchThreshold;

// This is YES when you can send me `startCalibratingTouchAtPoint:`.  I check my state and whether the device is connected.
@property (nonatomic, readonly) BOOL canStartCalibratingTouchAtPoint;

// When I receive this, I try to detect a touch.  If I detect a touch, I assume it's at `point` and adjust my touch parameters accordingly.  You can send me this at any time.  If I'm in state `TouchDetectorState_AwaitingTouchCalibration` and I have enough calibration readings to map touches to points, I change to state `TouchDetectorState_DetectingTouches` and notify my delegate.
- (void)startCalibratingTouchAtPoint:(CGPoint)point;

// I add `observer` to my list of observers and schedule him to be notified of my current state.
- (void)addObserver:(id<TouchDetectorObserver>)observer;
- (void)removeObserver:(id<TouchDetectorObserver>)observer;

// Notify `observer` of my current state, right now.
- (void)notifyObserverOfCurrentState:(id<TouchDetectorObserver>)observer;

// For debugging.
- (void)getTouchThresholdDistancesWithBlock:(void (^)(Lidar2DDistance const *distances, NSUInteger count))block;

@end

@protocol TouchDetectorObserver <NSObject>

@optional

// State transitions.
- (void)touchDetectorIsAwaitingTouchThresholdCalibration:(TouchDetector *)detector;
- (void)touchDetectorIsCalibratingTouchThreshold:(TouchDetector *)detector;
- (void)touchDetectorDidFinishCalibratingTouchThreshold:(TouchDetector *)detector;
- (void)touchDetectorIsAwaitingTouchCalibration:(TouchDetector *)detector;
- (void)touchDetector:(TouchDetector *)detector isCalibratingTouchAtPoint:(CGPoint)point;
- (void)touchDetector:(TouchDetector *)detector didFinishCalibratingTouchAtPoint:(CGPoint)point withResult:(TouchCalibrationResult)result;
- (void)touchDetectorIsDetectingTouches:(TouchDetector *)detector;

// Touch detection.
- (void)touchDetector:(TouchDetector *)detector didDetectTouches:(NSUInteger)count atScreenPoints:(CGPoint const *)points;

@end
