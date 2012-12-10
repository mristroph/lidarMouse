//
//  main.m
//  mickeyMouse
//
//  Created by Rob Mayoff on 12/7/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Application.h"

#import "urg_sensor.h"
#import "urg_utils.h"
#import "open_urg_sensor.h"

int main(int argc, const char * argv[]) {
    (void)argc; (void)argv;

    @autoreleasepool {
        Application *application = [[Application alloc] init];
        (void)application;
        CFRunLoopRun();
        return 0;
    }
}

