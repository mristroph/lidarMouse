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
    CGFloat levelCount = _data.length / sizeof *levels;

    CGContextRef gc = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(gc); {
        NSRect bounds = self.bounds;
        CGContextTranslateCTM(gc, CGRectGetMidX(bounds), CGRectGetMidY(bounds));

        NSBezierPath *path = [NSBezierPath bezierPath];
        uint32_t const *pLevel = levels;
        CGFloat const indexToDegrees= 239.77 / levelCount;
        CGFloat const baseDegrees = 30;
        for (CGFloat i = 0; i < levelCount; ++i, ++pLevel) {
            [path moveToPoint:CGPointZero];
            [path appendBezierPathWithArcWithCenter:CGPointZero radius:*pLevel / 10.0 startAngle:baseDegrees + i * indexToDegrees endAngle:baseDegrees + (i + 1) * indexToDegrees clockwise:NO];
            [path closePath];
        }
        [[NSColor colorWithDeviceHue:0 saturation:0.7 brightness:0.95 alpha:1] setFill];
        [path fill];
    } CGContextRestoreGState(gc);
}

@end
