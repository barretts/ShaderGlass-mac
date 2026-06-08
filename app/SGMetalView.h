/*
ShaderGlass macOS port -- SGMetalView.h

NSView whose backing layer IS a CAMetalLayer. Hands its layer to LivePipeline and
keeps drawableSize + contentsScale in sync with the backing store on resize/move.
*/

#pragma once
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SGMetalViewDelegate <NSObject>
// Device-pixel size changed (resize or backing-scale change). Reconfigure the
// swap chain + re-render. Called on the main thread.
- (void)metalViewDidResizeToWidth:(uint32_t)width height:(uint32_t)height;
@end

@interface SGMetalView : NSView
@property(nonatomic, weak) id<SGMetalViewDelegate> sgDelegate;
@property(nonatomic, readonly) CAMetalLayer* metalLayer;
// Current backing (device-pixel) size of the view.
- (CGSize)backingPixelSize;
@end

NS_ASSUME_NONNULL_END
