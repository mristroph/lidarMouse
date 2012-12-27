//
//  RawDataGraphView.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "Lidar2D.h"
#import "NSData+Lidar2D.h"
#import "RawDataGraphView.h"

@interface RawDataGraphView () <Lidar2DObserver>
@end

@implementation RawDataGraphView

#pragma mark - Public API

@synthesize device = _device;

- (void)setDevice:(Lidar2D *)device {
    [self disconnect];
    _device = device;
    [self connect];
}

@synthesize thresholdDistances = _thresholdDistances;
@synthesize data = _data;

- (void)setData:(NSData *)data {
    _data = [data copy];
    [self setNeedsDisplay:YES];
}

#pragma mark - NSView overrides

- (BOOL)isOpaque {
    return YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor whiteColor] setFill];
    NSRectFill(dirtyRect);

    if (_data.length == 0)
        return;

    Lidar2DDistance const *distances = _data.lidar2D_distances;
    CGFloat distanceCount = _data.lidar2D_distanceCount;
    Lidar2DDistance const *thresholdDistances = _thresholdDistances.lidar2D_distances;

    CGContextRef gc = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(gc); {
        NSRect bounds = self.bounds;
        CGContextTranslateCTM(gc, CGRectGetMidX(bounds), CGRectGetMidY(bounds));

        CGFloat const indexToDegrees= _device.coverageDegrees / distanceCount;
        CGFloat const baseDegrees = _device.firstRayOffsetDegrees;
        CGFloat const degreesToRadians = M_PI / 180;
        NSColor *redColor = [NSColor redColor];
        NSColor *greenColor = [NSColor greenColor];
        NSColor *blueColor = [NSColor blueColor];
        __unsafe_unretained NSColor *currentColor = nil;
        
        for (CGFloat i = 0; i < distanceCount; ++i) {
            CGFloat distance = distances[(int)i];
            CGFloat radius = distance / 4.0;

            __unsafe_unretained NSColor *desiredColor = nil;
            if (thresholdDistances && distance < thresholdDistances[(int)i]) {
                desiredColor = greenColor;
            } else if (distance == Lidar2DDistance_Invalid) {
                desiredColor = blueColor;
                radius = 2000;
            } else {
                desiredColor = redColor;
            }

            if (currentColor != desiredColor) {
                [desiredColor setStroke];
                currentColor = desiredColor;
            }
            
            CGFloat x = -cos((baseDegrees + i * indexToDegrees) * degreesToRadians) * radius;
            CGFloat y = sin((baseDegrees + i * indexToDegrees) * degreesToRadians) * radius;
            CGContextMoveToPoint(gc, 0, 0);
            CGContextAddLineToPoint(gc, x, y);
            CGContextStrokePath(gc);
        }
    } CGContextRestoreGState(gc);
}

#pragma mark - Lidar2DObserver protocol

- (void)lidar2DDidTerminate:(Lidar2D *)device {
    (void)device;
}

- (void)lidar2d:(Lidar2D *)device didReceiveDistanceData:(NSData *)distanceData {
    (void)device;
    self.data = distanceData;
}

#pragma mark - Device connection details

- (void)disconnect {
    [_device removeObserver:self];
}

- (void)connect {
    [_device addObserver:self];
}

@end
