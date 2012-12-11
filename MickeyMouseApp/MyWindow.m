//
//  MyWindow.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import "MyWindow.h"

NSString *const MyWindowWillOrderInNotification = @"MyWindowWillOrderInNotification";

@implementation MyWindow

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin {
    if (place != NSWindowOut) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MyWindowWillOrderInNotification object:self];
    }
    [super orderWindow:place relativeTo:otherWin];
}

@end
