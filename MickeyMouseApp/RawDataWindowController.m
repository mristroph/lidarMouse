//
//  RawDataWindowController.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "RawDataWindowController.h"
#import "RawDataGraphView.h"
#import "MyWindow.h"
#import "Lidar2D.h"

// This should really be read from the Lidar2D object.  Hardcoding for convenience.  Fix later.  XXX
#define kRayCount (725U-44U+1U)

@interface RawDataWindowController ()

@end

@implementation RawDataWindowController {
    RawDataWindowController *myself_; // set to self while window is ordered in to avoid being deallocated
    id<Lidar2DProxy> proxy_;
    id windowWillOrderInObserver_;
    id windowWillCloseObserver_;
    IBOutlet NSTextField *statusField_;
    IBOutlet RawDataGraphView *graphView_;
    volatile BOOL wantsStreamingData_;

    uint32_t untouchedRayDistances[kRayCount];
}

#pragma mark - Public API

- (id)initWithLidar2DProxy:(id<Lidar2DProxy>)proxy {
    if (self = [super initWithWindowNibName:@"RawDataWindowController"]) {
        proxy_ = proxy;
    }
    return self;
}

- (void)dealloc {
    [self stopObservingWindowPresence];
    [self stopStreamingData];
}

#pragma mark - NSWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    __block NSString *serialNumber;
    [proxy_ performBlockAndWait:^(id<Lidar2D> device) {
        serialNumber = device.serialNumber;
    }];
    self.window.title = [NSString stringWithFormat:@"Lidar2D %@", serialNumber];
    statusField_.stringValue = @"Loading";
    [self startObservingWindowPresence];
}

#pragma mark - Implementation details

- (void)startObservingWindowPresence {
    __unsafe_unretained RawDataWindowController *me = self;
    windowWillOrderInObserver_ = [[NSNotificationCenter defaultCenter] addObserverForName:MyWindowWillOrderInNotification object:self.window queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        [me windowWillBecomePresent];
    }];
    windowWillCloseObserver_ = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:self.window queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        [me windowWillBecomeAbsent];
    }];
}

- (void)stopObservingWindowPresence {
    if (windowWillOrderInObserver_) {
        [[NSNotificationCenter defaultCenter] removeObserver:windowWillOrderInObserver_];
        windowWillOrderInObserver_ = nil;
    }
    if (windowWillCloseObserver_) {
        [[NSNotificationCenter defaultCenter] removeObserver:windowWillCloseObserver_];
        windowWillCloseObserver_ =nil;
    }
}

- (void)windowWillBecomePresent {
    myself_ = self;
    [self startStreamingData];
}

- (void)windowWillBecomeAbsent {
    myself_ = nil;
    [self stopStreamingData];
}

- (void)startStreamingData {
    wantsStreamingData_ = YES;

    [proxy_ performBlock:^(id<Lidar2D> device) {
        [self updateStatusLabelIfNecessaryAndClearErrorWithDevice:device];

        [self setStatusLabelText:@"Preparing to calibrate - REMOVE ALL OBSTRUCTIONS FROM SCREEN"];
        [self resetUntouchedRayDistancesWithDevice:device];
        sleep(1);
        [self setStatusLabelText:@"Calibrating - DO NOT OBSTRUCT SCREEN"];
        __block int calibrationFramesLeft = 20;
        [device forEachStreamingDataSnapshot:^(NSData *data, BOOL *stop) {
            [self setStatusLabelText:[NSString stringWithFormat:@"Calibrating %d - DO NOT OBSTRUCT SCREEN", calibrationFramesLeft]];
            [self updateUntouchedRayDistancesWithDevice:device data:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                graphView_.data = data;
            });
            *stop = (--calibrationFramesLeft < 1);
        }];

        [self finalizeUntouchedRayDistancesWithDevice:device];

        dispatch_async(dispatch_get_main_queue(), ^{
            graphView_.untouchedDistances = [NSData dataWithBytes:untouchedRayDistances length:sizeof untouchedRayDistances];
        });

        [self setStatusLabelText:@"Preparing to calibrate - REMOVE ALL OBSTRUCTIONS FROM SCREEN"];
        while (wantsStreamingData_) {
            dispatch_async(dispatch_get_main_queue(), ^{
                statusField_.stringValue = @"Requesting streaming data";
            });
            [device forEachStreamingDataSnapshot:^(NSData *data, BOOL *stop) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    statusField_.stringValue = @"Received streaming data";
                    graphView_.data = data;
                });
                *stop = !wantsStreamingData_;
            }];

            NSError *error = device.error;
            [self updateStatusLabelIfNecessaryAndClearErrorWithDevice:device];
            if (error) {
                if (wantsStreamingData_) {
                    sleep(1);
                }
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    statusField_.stringValue = @"Streaming data stopped";
                });
            }
        }
    }];
}

- (void)setStatusLabelText:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        statusField_.stringValue = text;
    });
}

- (void)updateStatusLabelIfNecessaryAndClearErrorWithDevice:(id<Lidar2D>) device {
    NSError *error = device.error;
    if (error) {
        [self setStatusLabelText:@"Device Error"];
        NSLog(@"device error: %@", device.error);
        device.error = nil;
    }
}

- (void)stopStreamingData {
    wantsStreamingData_ = NO;
}

- (void)resetUntouchedRayDistancesWithDevice:(id<Lidar2D>)device {
    (void)device; // only passed to ensure I'm run on the device's queue
    for (size_t i = 0; i < kRayCount; ++i) {
        untouchedRayDistances[i] = UINT32_MAX;
    }
}

- (void)updateUntouchedRayDistancesWithDevice:(id<Lidar2D>)device data:(NSData *)data {
    (void)device; // only passed to ensure I'm run on the device's queue
    uint32_t const *distances = (uint32_t const *)data.bytes;
    size_t count = MIN(data.length / sizeof *distances, kRayCount);
    for (size_t i = 0; i < count; ++i) {
        uint32_t distance = distances[i];
        if (distance >= 20 && distance < untouchedRayDistances[i]) {
            untouchedRayDistances[i] = distance;
        }
    }
}

- (void)finalizeUntouchedRayDistancesWithDevice:(id<Lidar2D>)device {
    (void)device; // only passed to ensure I'm run on the device's queue
    for (size_t i = 0; i < kRayCount; ++i) {
        untouchedRayDistances[i] *= 0.95;
    }
}

@end
