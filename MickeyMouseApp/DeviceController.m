//
//  DeviceController.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "DeviceController.h"
#import "Lidar2D.h"
#import "DeviceControlWindow.h"
#import "RawDataGraphView.h"
#import "TouchDetector.h"

@interface DeviceController () <Lidar2DObserver, TouchDetectorObserver>
@end

@implementation DeviceController {
    DeviceController *myself_; // set to self while device is physically connected to keep me from being deallocated
    Lidar2D *device_;
    TouchDetector *touchDetector_;
    IBOutlet DeviceControlWindow *window_;
    IBOutlet RawDataGraphView *graphView_;
    IBOutlet NSTextView *logView_;
    IBOutlet NSToolbarItem *connectItem_;
    IBOutlet NSToolbarItem *calibrateUntouchedFieldItem_;
    IBOutlet NSToolbarItem *calibrateTouchItem_;
    IBOutlet NSToolbarItem *disconnectItem_;
    NSDictionary *toolbarValidators_;
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
        [touchDetector_ addObserver:self];
        [self initToolbarValidators];
        if (![[NSBundle mainBundle] loadNibNamed:@"DeviceController" owner:self topLevelObjects:nil]) {
            [NSException raise:NSNibLoadingException format:@"%@ failed to load nib", self];
        }
        graphView_.device = device_;
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
    [self logText:@"connecting"];
    [device_ connect];
    [window_.toolbar validateVisibleItems];
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
    [self logText:@"disconnecting"];
    [device_ disconnect];
    [window_.toolbar validateVisibleItems];
}

#pragma mark - Toolbar item validation

- (void)initToolbarValidators {
    toolbarValidators_ = @{
        @"connect": ^{ return !device_.isConnected; },
        @"calibrateUntouchedField": ^{ return touchDetector_.canStartCalibratingUntouchedField; },
        @"calibrateTouch": ^{ return touchDetector_.canStartCalibratingTouchAtPoint; },
        @"disconnect": ^{ return device_.isConnected; }
    };
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem {
    BOOL (^validator)(void) = toolbarValidators_[theItem.itemIdentifier];
    if (!validator) {
        [NSException raise:NSInternalInconsistencyException format:@"%@ doesn't have a validator for %@", self, theItem];
    }
    return validator();
}

#pragma mark - Lidar2DObserver protocol

- (void)lidar2DDidTerminate:(Lidar2D *)device {
    (void)device;
    myself_ = nil;
}

- (void)lidar2dDidConnect:(Lidar2D *)device {
    (void)device;
    [self logText:@"connected"];
    serialNumber_ = [device_.serialNumber copy];
    [self updateWindowTitle];
    [window_.toolbar validateVisibleItems];
}

- (void)lidar2dDidDisconnect:(Lidar2D *)device {
    (void)device;
    [self logText:@"disconnected"];
    [window_.toolbar validateVisibleItems];
}

- (void)lidar2d:(Lidar2D *)device didFailWithError:(NSError *)error {
    (void)device;
    [self logText:error.description];
}

#pragma mark - TouchDetectorObserver protocol

#pragma mark - Window title details

- (void)updateWindowTitle {
    window_.title = serialNumber_ ? [NSString stringWithFormat:@"Lidar2D - Serial Number %@", serialNumber_] : [NSString stringWithFormat:@"Lidar2D - Device Path %@", device_.devicePath];
}

#pragma mark - Implementation details

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
