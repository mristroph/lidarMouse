//
//  DeviceController.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "DeviceController.h"
#import "Lidar2D.h"
#import "MyWindow.h"
#import "RawDataGraphView.h"
#import "TouchDetector.h"

@interface DeviceController () <Lidar2DObserver, TouchDetectorObserver>
@end

@implementation DeviceController {
    DeviceController *myself_; // set to self while device is physically connected to keep me from being deallocated
    Lidar2D *device_;
    TouchDetector *touchDetector_;
    IBOutlet NSWindow *window_;
    IBOutlet RawDataGraphView *graphView_;
    IBOutlet NSTextView *logView_;
    IBOutlet NSButton *connectButton_;
    IBOutlet NSButton *calibrateUntouchedFieldButton_;
    IBOutlet NSButton *calibrateTouchButton_;
    IBOutlet NSButton *disconnectButton_;
    NSString *serialNumber_;
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
        if (![[NSBundle mainBundle] loadNibNamed:@"DeviceController" owner:self topLevelObjects:nil]) {
            [NSException raise:NSNibLoadingException format:@"%@ failed to load nib", self];
        }
        [self enableAppropriateButtons];
        [self updateWindowTitle];
        [window_ makeKeyAndOrderFront:self];
        NSLog(@"window_=%@", window_);
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
    NSLog(@"debug: %s %@", __func__, sender);
}

- (IBAction)calibrateUntouchedFieldButtonWasPressed:(id)sender {
    (void)sender;
    NSLog(@"debug: %s %@", __func__, sender);
}

- (IBAction)calibrateTouchButtonWasPressed:(id)sender {
    (void)sender;
    NSLog(@"debug: %s %@", __func__, sender);
}

- (IBAction)disconnectButtonWasPressed:(id)sender {
    (void)sender;
    NSLog(@"debug: %s %@", __func__, sender);
}

#pragma mark - Lidar2DObserver protocol

- (void)lidar2DDidTerminate:(Lidar2D *)device {
    (void)device;
    myself_ = nil;
}

- (void)lidar2dDidConnect:(Lidar2D *)device {
    (void)device;
    serialNumber_ = [device_.serialNumber copy];
    [self updateWindowTitle];
    [self enableAppropriateButtons];
}

- (void)lidar2dDidDisconnect:(Lidar2D *)device {
    (void)device;
    [self enableAppropriateButtons];
}

#pragma mark - TouchDetectorObserver protocol

- (void)touchDetectorIsAwaitingUntouchedFieldCalibration:(TouchDetector *)detector {
    (void)detector;
    [self enableAppropriateButtons];
}

- (void)touchDetectorIsCalibratingUntouchedField:(TouchDetector *)detector {
    (void)detector;
    [self enableAppropriateButtons];
}

- (void)touchDetectorIsAwaitingTouchCalibration:(TouchDetector *)detector {
    (void)detector;
    [self enableAppropriateButtons];
}

- (void)touchDetector:(TouchDetector *)detector isCalibratingTouchAtPoint:(CGPoint)point {
    (void)detector; (void)point;
    [self enableAppropriateButtons];
}

- (void)touchDetectorIsDetectingTouches:(TouchDetector *)detector {
    (void)detector;
    [self enableAppropriateButtons];
}

#pragma mark - Button enabling details

- (void)enableAppropriateButtons {
    [self enableConnectButtonIfAppropriate];
    [self enableDisconnectButtonIfAppropriate];
    [self enableCalibrateUntouchedFieldButtonIfAppropriate];
    [self enableCalibrateTouchButtonIfAppropriate];
}

- (void)enableConnectButtonIfAppropriate {
    connectButton_.enabled = !device_.isConnected;
}

- (void)enableDisconnectButtonIfAppropriate {
    disconnectButton_.enabled = device_.isConnected;
}

- (void)enableCalibrateUntouchedFieldButtonIfAppropriate {
    calibrateUntouchedFieldButton_.enabled = touchDetector_.canStartCalibratingUntouchedField;
}

- (void)enableCalibrateTouchButtonIfAppropriate {
    calibrateTouchButton_.enabled = touchDetector_.canStartCalibratingTouchAtPoint;
}

#pragma mark - Window title details

- (void)updateWindowTitle {
    window_.title = serialNumber_ ? [NSString stringWithFormat:@"Lidar2D - Serial Number %@", serialNumber_] : [NSString stringWithFormat:@"Lidar2D - Device Path %@", device_.devicePath];
}

@end
