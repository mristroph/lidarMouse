//  Copyright (c) 2012 Rob Mayoff. All rights reserved.

#import "DeviceControlWindow.h"

@implementation DeviceControlWindow

- (void)close {
    [super close];
    [[NSApplication sharedApplication]addWindowsItem:self title:self.title filename:NO];
}

@end
