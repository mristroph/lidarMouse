//
//  AppDelegate.m
//  MickeyMouseApp
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "AppDelegate.h"
#import "Lidar2DManager.h"
#import "DeviceController.h"

@interface AppDelegate () <Lidar2DManagerDelegate>
@end

@implementation AppDelegate {
    Lidar2DManager *lidar2DManager_;
}

#pragma mark - Public API

+ (AppDelegate *)theDelegate {
    return (AppDelegate *)[NSApplication sharedApplication].delegate;
}

@synthesize pointerTracksTouchesMenuItem = _pointerTracksTouchesMenuItem;

#pragma mark - NSApplicationDelegate protocol

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    lidar2DManager_ = [[Lidar2DManager alloc] init];
    lidar2DManager_.delegate = self;
    [lidar2DManager_ start];
}

#pragma mark - Lidar2DManager protocol

- (void)lidar2DManager:(Lidar2DManager *)manager didReceiveError:(NSError *)error {
    (void)manager;
    NSLog(@"error: %@", error);
    NSAlert *alert = [NSAlert alertWithError:error];
    [alert runModal];
}

- (void)lidar2DManager:(Lidar2DManager *)manager didConnectToDevice:(Lidar2D *)device {
    (void)manager;
    [DeviceController runWithLidar2D:device];
}

@end
