/*
ShaderGlass macOS port -- LivePipeline.mm
*/

#import "LivePipeline.h"
#import "EngineBridge.h"
#import <Metal/Metal.h>
#include "../backend/sg_image.h"
#include "../capture/SCKCapture.h"
#include <atomic>
#include <string>
#include <vector>
#include <cstring>

using namespace sg;

static std::string readTextFile(NSString* path) {
    NSError* e = nil;
    NSString* s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];
    return s ? std::string(s.UTF8String) : std::string();
}

// Private methods used before their definition (FrameSink lambda, render-thread routing).
@interface LivePipeline ()
- (void)onCaptureFrameTex:(BackendTexture*)tex w:(uint32_t)w h:(uint32_t)h frame:(uint32_t)frameCount;
- (void)drawSrc:(BackendTexture*)src toTarget:(BackendTexture*)target
           srcW:(uint32_t)sw srcH:(uint32_t)sh dstW:(uint32_t)dw dstH:(uint32_t)dh
      frameCount:(uint32_t)frameCount;
- (void)renderFrameLocked;
@end

@implementation LivePipeline {
    EngineBridge*    _bridge;
    SCKCapture*      _capture;            // C++ owned; created on first startCapture
    std::vector<std::string> _shaderSources;
    SGShaderKind     _activeShaderKind;

    // static-image source (L1/L2)
    BackendTexture*  _staticSrc;
    uint32_t         _srcW, _srcH;        // current source dimensions
    uint32_t         _dstW, _dstH;        // current drawable dimensions (render-thread-only once capturing)
    std::atomic<bool> _capturing;         // read across threads; gates the render-thread routing
    dispatch_queue_t  _renderQueue;       // == SCKCapture's serial queue while capturing; the sole render thread
}

- (nullable instancetype)initWithLayer:(nullable CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                             shaderDir:(NSString*)shaderDir {
    self = [super init];
    if (!self) return nil;

    NSArray<NSString*>* shaderFiles = @[
        @"passthrough.metal",
        @"crt_demo.metal",
        @"crt_pro.metal",
        @"lcd_grid.metal",
        @"amber_mono.metal",
        @"vhs_soft.metal",
        @"green_mono.metal",
        @"pixel_grid.metal",
        @"bloom_soft.metal",
        @"pvm_slots.metal",
    ];
    _shaderSources.resize(SGShaderCount);
    for (NSInteger i = 0; i < SGShaderCount; ++i) {
        std::string src = readTextFile([shaderDir stringByAppendingPathComponent:shaderFiles[i]]);
        if (src.empty()) {
            NSLog(@"LivePipeline: cannot read shader %@ from %@", shaderFiles[i], shaderDir);
            return nil;
        }
        _shaderSources[i] = std::move(src);
    }
    _activeShaderKind = SGShaderPassthrough;
    _bridge = [[EngineBridge alloc] initWithLayer:layer
                                            width:width
                                           height:height
                                preprocessSource:_shaderSources[SGShaderPassthrough]
                                    shaderSource:_shaderSources[_activeShaderKind]];
    if (!_bridge) {
        NSLog(@"LivePipeline: EngineBridge init failed (no Metal device or shader compile error)");
        return nil;
    }
    __weak LivePipeline* weakSelf = self;
    _bridge.engineEventHandler = ^(SGEngineEvent event) {
        LivePipeline* s = weakSelf;
        if (!s || !s.engineEventHandler) return;
        s.engineEventHandler((NSInteger)event);
    };
    _dstW = width; _dstH = height;
    _capturing.store(false);
    return self;
}

- (BOOL)setStaticImagePath:(NSString*)pngPath {
    uint32_t w=0, h=0; std::vector<uint8_t> px;
    if (!DecodeImageFileBGRA(pngPath.UTF8String, w, h, px)) {
        NSLog(@"LivePipeline: decode failed for %@", pngPath);
        return NO;
    }
    if (_staticSrc) { [_bridge destroyTexture:_staticSrc]; _staticSrc = nullptr; }
    _staticSrc = [_bridge createTexture:TextureDesc{w, h, PixFmt::BGRA8_UNORM, false, false} initialData:px.data() rowPitch:w*4];
    _srcW = w; _srcH = h;
    return _staticSrc != nullptr;
}

- (void)drawSrc:(BackendTexture*)src toTarget:(BackendTexture*)target
           srcW:(uint32_t)sw srcH:(uint32_t)sh dstW:(uint32_t)dw dstH:(uint32_t)dh
      frameCount:(uint32_t)frameCount {
    [_bridge renderSource:src sourceWidth:sw sourceHeight:sh toTarget:target targetWidth:dw targetHeight:dh frameCount:frameCount];
}

// THREADING MODEL (REVIEW C1): the MetalBackend is touched from exactly one thread.
// While capturing, that thread is SCKCapture's serial render queue (_renderQueue);
// the FrameSink runs there and all other backend-touching work (resize, shader
// repaint) is marshaled onto it. While NOT capturing, the main thread owns the
// backend (the 30fps tick drives static redraws). runOnRenderThread routes accordingly.
- (void)runOnRenderThread:(dispatch_block_t)block {
    if (_capturing.load() && _renderQueue) dispatch_async(_renderQueue, block);
    else block();   // not capturing: caller is the main thread, which owns the backend
}

// Does the actual single-pass render+present. MUST run on the current render thread.
- (void)renderFrameLocked {
    if (!_staticSrc) return;
    @autoreleasepool {
        [self drawSrc:_staticSrc toTarget:nullptr
                 srcW:_srcW srcH:_srcH dstW:_dstW dstH:_dstH frameCount:0];
    }
}

// Public: the static-image repaint (timer / explicit). No-op while capturing (the
// capture queue drives frames). The atomic gate makes the cross-thread read safe.
- (void)renderFrame {
    if (_capturing.load()) return;   // capture path drives its own frames
    [self renderFrameLocked];
}

- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height {
    [self runOnRenderThread:^{
        _dstW = width; _dstH = height;          // render-thread-only once capturing
        [_bridge resizeToWidth:width height:height];
        if (!_capturing.load()) [self renderFrameLocked]; // capture path repaints next frame
    }];
}

- (void)setShaderKind:(SGShaderKind)kind {
    if (kind < 0 || kind >= SGShaderCount) kind = SGShaderPassthrough;
    [self runOnRenderThread:^{
        _activeShaderKind = kind;
        [_bridge setPreprocessSource:_shaderSources[SGShaderPassthrough] shaderSource:_shaderSources[_activeShaderKind]];
        if (!_capturing.load()) [self renderFrameLocked];
    }];
}

- (BOOL)startCaptureKind:(SGTargetKind)kind targetID:(uint32_t)targetID {
    return [self startCaptureKind:kind targetID:targetID excludingWindowIDs:nil];
}

- (BOOL)startCaptureKind:(SGTargetKind)kind
                targetID:(uint32_t)targetID
      excludingWindowIDs:(nullable NSArray<NSNumber*>*)excludedWindowIDs {
    if (!_capture) {
        __weak LivePipeline* weakSelf = self;
        // FrameSink runs on the capture serial queue (the render thread).
        FrameSink sink = [weakSelf](const CaptureFrame& f) {
            LivePipeline* s = weakSelf;
            if (!s) return;
            [s onCaptureFrameTex:f.texture w:f.width h:f.height frame:(uint32_t)f.inputFrameNo];
        };
        CaptureEventSink events = [weakSelf](const CaptureEvent& e) {
            LivePipeline* s = weakSelf;
            if (!s || !s.captureEventHandler) return;
            NSString* msg = [NSString stringWithUTF8String:e.message.c_str()];
            s.captureEventHandler(e.kind == CaptureEventKind::Started, msg);
        };
        // Share the backend's MTLDevice (J7) so the captured texture is sampleable.
        _capture = new SCKCapture([_bridge renderBackend], sink, [_bridge nativeDevice], events);
        _renderQueue = (__bridge dispatch_queue_t)_capture->RenderQueue();
    }
    _capturing.store(true);          // set BEFORE Start so routing engages immediately
    CaptureTarget t;
    t.kind = (kind == SGTargetWindow) ? CaptureTargetKind::Window : CaptureTargetKind::Display;
    t.id   = targetID;
    for (NSNumber* n in excludedWindowIDs)
        t.excludedWindowIDs.push_back((uint32_t)n.unsignedIntValue);
    return _capture->Start(t, /*maxRate*/false, /*cursor*/false);
}

// Called from the capture serial queue (the render thread).
- (void)onCaptureFrameTex:(BackendTexture*)tex w:(uint32_t)w h:(uint32_t)h frame:(uint32_t)frameCount {
    @autoreleasepool {
        [self drawSrc:tex toTarget:nullptr srcW:w srcH:h dstW:_dstW dstH:_dstH frameCount:frameCount];
    }
}

// MUST be called from the main thread (SCKCapture::Stop does a dispatch_sync onto the
// render queue; calling from that queue would deadlock).
- (void)stopCapture {
    _capturing.store(false);          // stop routing new work onto the render queue
    if (_capture) _capture->Stop();   // drains the render queue synchronously before returning
}

- (BOOL)renderOffscreenToPNG:(NSString*)outPath {
    if (!_staticSrc) return NO;
    uint32_t w = _srcW, h = _srcH;   // 1:1 offscreen render for a clean golden diff
    [self drawSrc:_staticSrc toTarget:nullptr srcW:w srcH:h dstW:w dstH:h frameCount:0];
    return [self writeLastOutputToPNG:outPath];
}

- (BOOL)writeLastOutputToPNG:(NSString*)outPath {
    uint32_t w = _dstW, h = _dstH;
    if (!w || !h) {
        w = _srcW; h = _srcH;
    }
    if (!w || !h) return NO;
    std::vector<uint8_t> px((size_t)w*h*4);
    BOOL readbackOK = [_bridge readbackLastOutput:px.data() rowPitch:w*4];
    bool ok = EncodePNGFromBGRA(outPath.UTF8String, px.data(), w, h, w*4);
    return readbackOK && ok;
}

- (void)shutdown {
    [self stopCapture];
    if (_capture) { delete _capture; _capture = nullptr; }
    if (_staticSrc) { [_bridge destroyTexture:_staticSrc]; _staticSrc = nullptr; }
    [_bridge shutdown];
    _bridge = nil;
}

- (void)dealloc { [self shutdown]; }

@end
