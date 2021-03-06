//
//  DeviceController.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "AppDelegate.h"
#import "DeviceControlWindow.h"
#import "DeviceController.h"
#import "Lidar2D.h"
#import "RawDataGraphView.h"
#import "TouchDetector.h"

static NSString *const kPointerTracksTouchesItemIdentifier = @"pointerTracksTouches";

@interface DeviceController () <Lidar2DObserver, TouchDetectorObserver, NSWindowDelegate>
@end

@implementation DeviceController {
    DeviceController *myself_; // set to self while device is physically connected to keep me from being deallocated
    Lidar2D *device_;
    TouchDetector *touchDetector_;
    IBOutlet DeviceControlWindow *controlWindow_;
    IBOutlet RawDataGraphView *graphView_;
    IBOutlet NSPanel *touchCalibrationPanel_;
    IBOutlet NSView *touchCalibrationTargetView_;
    IBOutlet NSTextView *logView_;
    NSDictionary *userInterfaceItemValidators_;
    NSString *serialNumber_;

    CGPoint touchPoint_; // in CG screen coordinates
    BOOL shouldPointerTrackTouches_ : 1;
    BOOL touchWasDown_ : 1;
}

#pragma mark - Public API

+ (void)runWithLidar2D:(Lidar2D *)device {
    (void)[[DeviceController alloc] initWithLidar2D:device];
}

- (id)initWithLidar2D:(Lidar2D *)device {
    if (self = [super init]) {
        myself_ = self;
        device_ = device;
        [device_ addObserver:self];
        touchDetector_ = [[TouchDetector alloc] initWithDevice:device_];
        [touchDetector_ addObserver:self];
        [self initUserInterfaceItemValidators];
        if (![[NSBundle mainBundle] loadNibNamed:@"DeviceController" owner:self topLevelObjects:nil]) {
            [NSException raise:NSNibLoadingException format:@"%@ failed to load nib", self];
        }
        graphView_.device = device_;
        [self updateWindowTitle];
        [touchDetector_ notifyObserverOfCurrentState:self];
        [controlWindow_ makeKeyAndOrderFront:self];
    }
    return self;
}

- (void)dealloc {
    [device_ removeObserver:self];
    [touchDetector_ removeObserver:self];
}

#pragma mark - Nib actions

- (IBAction)connectButtonWasPressed:(id)sender {
    (void)sender;
    [self logText:@"connecting"];
    [device_ connect];
    [self updateInterfaceForCurrentState];
}

- (IBAction)calibrateTouchThresholdButtonWasPressed:(id)sender {
    (void)sender;
    [touchDetector_ startCalibratingTouchThreshold];
}

- (IBAction)calibrateTouchButtonWasPressed:(id)sender {
    (void)sender;
    CGRect rect = [touchCalibrationTargetView_ convertRect:touchCalibrationTargetView_.bounds toView:nil];
    rect = [touchCalibrationPanel_ convertRectToScreen:rect];
    CGPoint screenPoint = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    [touchDetector_ startCalibratingTouchAtPoint:screenPoint];
}

- (IBAction)disconnectButtonWasPressed:(id)sender {
    (void)sender;
    [self logText:@"disconnecting"];
    [device_ disconnect];
    [self updateInterfaceForCurrentState];
}

- (IBAction)pointerTracksTouchesButtonWasPressed:(id)sender {
    (void)sender;
    shouldPointerTrackTouches_ = !shouldPointerTrackTouches_;
    [self updateInterfaceForCurrentState];
}

- (IBAction)resetCalibration:(id)sender {
    (void)sender;
    [touchDetector_ reset];
    [self updateInterfaceForCurrentState];
}

#pragma mark - Toolbar and menu item validation

- (void)initUserInterfaceItemValidators {
    // Localize these so the validators don't make retain cycles with me.
    Lidar2D *device = device_;
    TouchDetector *detector = touchDetector_;

    userInterfaceItemValidators_ = @{
    NSStringFromSelector(@selector(connectButtonWasPressed:)): ^{ return !device.isBusy && !device.isConnected; },
    NSStringFromSelector(@selector(calibrateTouchThresholdButtonWasPressed:)): ^{ return detector.canStartCalibratingTouchThreshold; },
    NSStringFromSelector(@selector(calibrateTouchButtonWasPressed:)): ^{ return detector.canStartCalibratingTouchAtPoint; },
    NSStringFromSelector(@selector(disconnectButtonWasPressed:)): ^{ return !device.isBusy && device.isConnected; },
    NSStringFromSelector(@selector(pointerTracksTouchesButtonWasPressed:)): ^{ return YES; },
    NSStringFromSelector(@selector(resetCalibration:)): ^{ return !device.isConnected || detector.canStartCalibratingTouchAtPoint || detector.canStartCalibratingTouchThreshold; }
    };
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    BOOL (^validator)(void) = userInterfaceItemValidators_[NSStringFromSelector(item.action)];
    if (!validator) {
        [NSException raise:NSInternalInconsistencyException format:@"%@ doesn't have a validator for %@", self, item];
    }
    return validator();
}

#pragma mark - Lidar2DObserver protocol

- (void)lidar2DDidTerminate:(Lidar2D *)device {
    (void)device;
    [self logText:@"terminated"];
    myself_ = nil;
}

- (void)lidar2dDidConnect:(Lidar2D *)device {
    (void)device;
    [self logText:@"connected"];
    serialNumber_ = [device_.serialNumber copy];
    [self updateWindowTitle];
    [self updateInterfaceForCurrentState];
}

- (void)lidar2dDidDisconnect:(Lidar2D *)device {
    (void)device;
    [self logText:@"disconnected"];
    [self updateInterfaceForCurrentState];
}

- (void)lidar2d:(Lidar2D *)device didFailWithError:(NSError *)error {
    (void)device;
    [self logText:error.description];
}

#pragma mark - TouchDetectorObserver protocol

- (void)touchDetectorIsAwaitingTouchThresholdCalibration:(TouchDetector *)detector {
    (void)detector;
    [self logText:@"Touch detector needs to calibrate touch thresholds; remove all obstructions from the sensitive area then click Calibrate Touch Thresholds"];
    [self updateInterfaceForCurrentState];
}

- (void)touchDetectorIsCalibratingTouchThreshold:(TouchDetector *)detector {
    (void)detector;
    [self logText:@"Calibrating touch thresholds; do not obstruct the sensitive area"];
    [self updateInterfaceForCurrentState];
}

- (void)touchDetectorDidFinishCalibratingTouchThreshold:(TouchDetector *)detector {
    (void)detector;
    [self logText:@"Finished calibrating touch thresholds"];
    [self updateInterfaceForCurrentState];
}

- (void)touchDetectorIsAwaitingTouchCalibration:(TouchDetector *)detector {
    (void)detector;
    [self logText:@"Touch detector needs to calibrate touches"];
    [self updateInterfaceForCurrentState];
}

- (void)touchDetector:(TouchDetector *)detector isCalibratingTouchAtPoint:(CGPoint)point {
    (void)detector; (void)point;
    [self logText:@"Touch detector is calibrating a touch"];
    [self updateInterfaceForCurrentState];
}

- (void)touchDetector:(TouchDetector *)detector didFinishCalibratingTouchAtPoint:(CGPoint)point withResult:(TouchCalibrationResult)result {
    (void)detector; (void)point;
    switch (result) {
        case TouchCalibrationResult_Success: [self logText:@"Calibrated a touch successfully"]; break;
        case TouchCalibrationResult_MultipleTouchesDetected: [self logText:@"Failed to calibrate a touch because I detected multiple touches"]; break;
        case TouchCalibrationResult_NoTouchDetected: [self logText:@"Failed to calibrate a touch because I didn't detect a touch"]; break;
    }
}

- (void)touchDetectorIsDetectingTouches:(TouchDetector *)detector {
    (void)detector;
    [self logText:@"Ready to detect touches"];
    [self updateInterfaceForCurrentState];
}

- (void)touchDetector:(TouchDetector *)detector didDetectTouches:(NSUInteger)count atScreenPoints:(const CGPoint *)points {
    (void)detector;
    if (!shouldPointerTrackTouches_)
        return;

    if (count > 1) {
        NSLog(@"%lu touches detected; ignoring all", count);
    } else if (count == 1) {
        touchPoint_ = CGPointMake(points[0].x, [NSScreen mainScreen].frame.size.height - points[0].y);
        if (touchWasDown_) {
            [self sendMouseEventWithType:kCGEventLeftMouseDragged];
        } else {
            [self sendMouseEventWithType:kCGEventLeftMouseDown];
            touchWasDown_ = YES;
        }
    } else if (touchWasDown_) {
        [self sendMouseEventWithType:kCGEventLeftMouseUp];
        touchWasDown_ = NO;
    }
}

- (void)touchDetector:(TouchDetector *)detector didUpdateTouchThresholds:(const Lidar2DDistance *)thresholds count:(NSUInteger)count {
    (void)detector;
    graphView_.thresholdDistances = (count > 0) ? [NSData dataWithBytes:thresholds length:count * sizeof *thresholds] : nil;
}

#pragma mark - Window title details

- (void)updateWindowTitle {
    controlWindow_.title = serialNumber_ ? [NSString stringWithFormat:@"Lidar2D - Serial Number %@", serialNumber_] : [NSString stringWithFormat:@"Lidar2D - Device Path %@", device_.devicePath];
}

#pragma mark - Implementation details

- (void)sendMouseEventWithType:(CGEventType)type {
    CGEventRef event = CGEventCreateMouseEvent(NULL, type, touchPoint_, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

- (void)updateInterfaceForCurrentState {
    [controlWindow_.toolbar validateVisibleItems];
    controlWindow_.toolbar.selectedItemIdentifier = shouldPointerTrackTouches_ ? kPointerTracksTouchesItemIdentifier : nil;
    [self updateTouchCalibrationPanelVisibility];
    if (controlWindow_.isMainWindow) {
        [AppDelegate theDelegate].pointerTracksTouchesMenuItem.state = shouldPointerTrackTouches_ ? NSOnState : NSOffState;
    }
}

- (void)updateTouchCalibrationPanelVisibility {
    BOOL shouldBeVisible = [touchDetector_ canStartCalibratingTouchAtPoint] || touchDetector_.state == TouchDetectorState_CalibratingTouch;
    if (shouldBeVisible) {
        if (!touchCalibrationPanel_.isVisible) {
            [touchCalibrationPanel_ orderFront:self];
        }
    } else {
        if (touchCalibrationPanel_.isVisible) {
            [touchCalibrationPanel_ orderOut:self];
        }
    }
}

- (void)logText:(NSString *)text {
    char const *newline = [text hasSuffix:@"\n"] ? "" : "\n";
    text = [NSString stringWithFormat:@"%.6f %@%s", CFAbsoluteTimeGetCurrent(), text, newline];

    BOOL wasAtBottom = logView_.enclosingScrollView.verticalScroller.doubleValue == 1.0;
    [logView_.textStorage replaceCharactersInRange:NSMakeRange(logView_.textStorage.length, 0) withString:text];
    if (wasAtBottom) {
        [logView_ scrollPoint:NSMakePoint(0, logView_.bounds.size.height)];
    }
}

@end
