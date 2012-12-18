//
//  AppDelegate.h
//  MickeyMouseApp
//
//  Created by Rob Mayoff on 12/10/12.
//  Copyright (c) 2012 Rob Mayoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

+ (AppDelegate *)theDelegate;

@property (nonatomic, strong) IBOutlet NSMenuItem *pointerTracksTouchesMenuItem;

@end
