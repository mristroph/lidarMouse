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

@synthesize untouchedDistances = _untouchedDistances;
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
    uint32_t const *untouchedDistances = (uint32_t const *)_untouchedDistances.bytes;
    CGFloat levelCount = _data.length / sizeof *levels;

    CGContextRef gc = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(gc); {
        NSRect bounds = self.bounds;
        CGContextTranslateCTM(gc, CGRectGetMidX(bounds), CGRectGetMidY(bounds));

        CGFloat const indexToDegrees= 239.77 / levelCount;
        CGFloat const baseDegrees = -30;
        CGFloat const degreesToRadians = M_PI / 180;
        NSColor *redColor = [NSColor redColor];
        NSColor *greenColor = [NSColor greenColor];
        NSColor *blueColor = [NSColor blueColor];
        __unsafe_unretained NSColor *currentColor = nil;
        
        for (CGFloat i = 0; i < levelCount; ++i) {
            CGFloat distance = levels[(int)i];
            if (distance < 20) {
                distance = UINT32_MAX;
            }

            CGFloat radius = distance / 4.0;

            __unsafe_unretained NSColor *desiredColor = nil;
            if (untouchedDistances && distance < untouchedDistances[(int)i]) {
                desiredColor = greenColor;
            } else if (distance == UINT32_MAX) {
                desiredColor = blueColor;
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

@end
