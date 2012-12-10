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

int main(int argc, const char * argv[])
{
    @autoreleasepool {

        Application *application = [[Application alloc] init];
        (void)application;
        CFRunLoopRun();
        return 0;

        urg_t urg;

        if (open_urg_sensor(&urg, 0, NULL) < 0) {
            fprintf(stderr, "error: open_urg_sensor failed: %s (%d)", strerror(errno), errno);
            return 1;
        }

        long data[urg_max_data_size(&urg)];
        urg_start_measurement(&urg, URG_DISTANCE, 1, 0);

        long timestamp;
        int n = urg_get_distance(&urg, data, &timestamp);

        for (int i = 0; i < n; ++i) {
            printf("%d: %ld\n", i, data[i]);
        }

        urg_close(&urg);
        return 0;
    }
}

