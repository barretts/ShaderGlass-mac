/*
ShaderGlass macOS port -- SGAppDelegate.h
*/

#pragma once
#import <Cocoa/Cocoa.h>

@interface SGAppDelegate : NSObject <NSApplicationDelegate>
- (void)exportMoment:(id)sender;
- (void)beginBypassCompare:(id)sender;
- (void)endBypassCompare:(id)sender;
- (void)toggleSplitCompare:(id)sender;
@end
