/*
ShaderGlass macOS port -- SGMetalView.mm
*/

#import "SGMetalView.h"

@implementation SGMetalView

// Make the view layer-hosting with a CAMetalLayer as its backing layer.
- (CALayer*)makeBackingLayer {
    CAMetalLayer* layer = [CAMetalLayer layer];
    // device/pixelFormat/colorspace/framebufferOnly are set by MetalBackend::Initialize.
    layer.needsDisplayOnBoundsChange = YES;
    layer.presentsWithTransaction = NO;
    return layer;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;               // triggers makeBackingLayer
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    }
    return self;
}

- (CAMetalLayer*)metalLayer { return (CAMetalLayer*)self.layer; }

- (CGSize)backingPixelSize {
    NSSize pts = self.bounds.size;
    NSSize px  = [self convertSizeToBacking:pts];
    return CGSizeMake(MAX(1.0, px.width), MAX(1.0, px.height));
}

- (void)syncDrawableSize {
    CGFloat scale = self.window ? self.window.backingScaleFactor : 1.0;
    CAMetalLayer* layer = self.metalLayer;
    layer.contentsScale = scale;             // HiDPI: keep both in sync (Critic M4)
    CGSize px = [self backingPixelSize];
    layer.drawableSize = px;
    if (self.sgDelegate)
        [self.sgDelegate metalViewDidResizeToWidth:(uint32_t)px.width height:(uint32_t)px.height];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self syncDrawableSize];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self syncDrawableSize];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) [self syncDrawableSize];
}

@end
