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

@interface RawDataWindowController ()

@end

@implementation RawDataWindowController {
    RawDataWindowController *myself_; // set to self while window is ordered in to avoid being deallocated
    id<Lidar2DProxy> proxy_;
    id windowWillOrderInObserver_;
    id windowWillCloseObserver_;
    IBOutlet RawDataGraphView *graphView_;
    volatile BOOL wantsStreamingData_;
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
        while (wantsStreamingData_) {
            [device forEachStreamingDataSnapshot:^(NSData *data, BOOL *stop) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    graphView_.data = data;
                });
                *stop = !wantsStreamingData_;
            }];
        }
    }];
}

- (void)stopStreamingData {
    wantsStreamingData_ = NO;
}

@end
