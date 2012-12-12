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

        uint32_t const *pLevel = levels;
        CGFloat const indexToDegrees= 239.77 / levelCount;
        CGFloat const baseDegrees = -30;
        CGFloat const degreesToRadians = M_PI / 180;
        NSColor *redColor = [NSColor redColor];
        NSColor *blueColor = [NSColor blueColor];
        __unsafe_unretained NSColor *currentColor = nil;
        for (CGFloat i = 0; i < levelCount; ++i, ++pLevel) {
            CGFloat radius = *pLevel;
            __unsafe_unretained NSColor *desiredColor = nil;
            if (radius < 20) {
                radius = 1000;
                desiredColor = blueColor;
            } else {
                radius /= 5.0;
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

@end
