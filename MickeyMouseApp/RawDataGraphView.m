//
//  RawDataGraphView.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "RawDataGraphView.h"

@implementation RawDataGraphView

#pragma mark - Public API

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

    uint32_t const *levels = (uint32_t const *)_data.bytes;
    NSUInteger levelCount = _data.length / sizeof *levels;
    NSUInteger maxLevel = 0;
    for (NSUInteger i = 0; i < levelCount; ++i)  {
        maxLevel = MAX(maxLevel, levels[i]);
    }
    maxLevel = MIN(maxLevel, 1000U);

    CGContextRef gc = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(gc); {
        NSRect bounds = self.bounds;
        CGContextTranslateCTM(gc, bounds.origin.x, bounds.origin.y);
        CGContextScaleCTM(gc, bounds.size.width / levelCount, bounds.size.height / maxLevel);

        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:CGPointZero];
        for (NSUInteger i = 0; i < levelCount; ++i) {
            [path lineToPoint:CGPointMake(i, levels[i])];
            [path lineToPoint:CGPointMake(i+1, levels[i])];
        }
        [path lineToPoint:CGPointMake(levelCount, 0)];
        [path closePath];
        [[NSColor colorWithDeviceHue:0 saturation:0.7 brightness:0.95 alpha:1] setFill];
        [path fill];
        [[NSColor colorWithDeviceHue:0 saturation:0.9 brightness:0.8 alpha:1] setStroke];
        path.lineJoinStyle = NSMiterLineJoinStyle;
        path.lineWidth = 2;
        [path stroke];
    } CGContextRestoreGState(gc);
}

@end
