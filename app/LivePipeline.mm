/*
ShaderGlass macOS port -- LivePipeline.mm
*/

#import "LivePipeline.h"
#import <Metal/Metal.h>
#include "../backend/MetalBackend.h"
#include "../backend/sg_image.h"
#include "../capture/SCKCapture.h"
#include <atomic>
#include <string>
#include <vector>
#include <cstring>

using namespace sg;

// The engine's exact shader-pass vertex buffer (ShaderPass.cpp:23-35): 8 verts x
// (float4 pos + float2 uv); shader pass uses start-vertex 4. (4th local copy by
// design — sharing into sg_geometry.h is deferred to the M0b engine decouple.)
static const float kVertexBuffer[] = {
    -1,-1,0,1, 0,1,  -1,1,0,1, 0,0,  1,-1,0,1, 1,1,  1,1,0,1, 1,0,
     0, 0,0,1, 0,1,   0,1,0,1, 0,0,  1, 0,0,1, 1,1,  1,1,0,1, 1,0
};
struct UBO  { float MVP[16]; };
struct Push { float SourceSize[4]; float OriginalSize[4]; float OutputSize[4]; uint32_t FrameCount; };

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
    MetalBackend     _backend;
    SCKCapture*      _capture;            // C++ owned; created on first startCapture
    BackendShader*   _shaders[SGShaderCount];
    std::atomic<BackendShader*> _activeShader;  // hot-swapped by setShaderKind
    BackendBuffer*   _vtx;
    BackendBuffer*   _ubo;
    BackendBuffer*   _push;
    BackendSampler*  _sampler;

    // static-image source (L1/L2)
    BackendTexture*  _staticSrc;
    uint32_t         _srcW, _srcH;        // current source dimensions
    uint32_t         _dstW, _dstH;        // current drawable dimensions (render-thread-only once capturing)
    std::atomic<bool> _capturing;         // read across threads; gates the render-thread routing
    dispatch_queue_t  _renderQueue;       // == SCKCapture's serial queue while capturing; the sole render thread
}

- (nullable instancetype)initWithLayer:(CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                             shaderDir:(NSString*)shaderDir {
    self = [super init];
    if (!self) return nil;

    if (!_backend.Initialize((__bridge void*)layer, width, height, /*hdr*/false)) {
        NSLog(@"LivePipeline: backend Initialize failed (no Metal device?)");
        return nil;
    }
    _dstW = width; _dstH = height;

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
    for (NSInteger i = 0; i < SGShaderCount; ++i) {
        std::string src = readTextFile([shaderDir stringByAppendingPathComponent:shaderFiles[i]]);
        if (src.empty()) {
            NSLog(@"LivePipeline: cannot read shader %@ from %@", shaderFiles[i], shaderDir);
            return nil;
        }
        _shaders[i] = _backend.CreateShader(src.data(), src.size(), src.data(), src.size());
        if (!_shaders[i]) {
            NSLog(@"LivePipeline: shader compile failed for %@", shaderFiles[i]);
            return nil;
        }
    }
    _activeShader.store(_shaders[SGShaderPassthrough]);

    // once-created GPU resources
    _vtx     = _backend.CreateVertexBuffer(kVertexBuffer, sizeof(kVertexBuffer));
    _ubo     = _backend.CreateConstantBuffer(sizeof(UBO));
    _push    = _backend.CreateConstantBuffer(sizeof(Push));
    // Nearest (point) matches the Windows engine default (ShaderPass.cpp:64 /
    // IRenderBackend.h); the engine upgrades to Linear only when a preset's
    // filter_linear says so. Linear here made passthrough blurrier than Windows (D1).
    _sampler = _backend.CreateSampler(SamplerDesc{Filter::Nearest, Wrap::Border});
    _capturing.store(false);
    return self;
}

- (BOOL)setStaticImagePath:(NSString*)pngPath {
    uint32_t w=0, h=0; std::vector<uint8_t> px;
    if (!DecodeImageFileBGRA(pngPath.UTF8String, w, h, px)) {
        NSLog(@"LivePipeline: decode failed for %@", pngPath);
        return NO;
    }
    if (_staticSrc) { _backend.DestroyTexture(_staticSrc); _staticSrc = nullptr; }
    _staticSrc = _backend.CreateTexture(TextureDesc{w, h, PixFmt::BGRA8_UNORM, false, false}, px.data(), w*4);
    _srcW = w; _srcH = h;
    return _staticSrc != nullptr;
}

// FIT (aspect-preserving) MVP in the engine's row-major layout. m[0]=2*fillX,
// m[12]=-fillX, m[5]=2*fillY, m[13]=-fillY maps the [0,1] quad to a centered NDC
// rect; black bars come from the pass clear. FILL would set fillX=fillY=1.
- (void)fillUniformsForSrcW:(uint32_t)sw srcH:(uint32_t)sh dstW:(uint32_t)dw dstH:(uint32_t)dh
                        ubo:(UBO*)u push:(Push*)pu {
    float fillX = 1.0f, fillY = 1.0f;
    if (sw && sh && dw && dh) {
        float s = fminf((float)dw / sw, (float)dh / sh);
        fillX = (s * sw) / dw;   // fraction of the drawable width the image occupies
        fillY = (s * sh) / dh;
    }
    memset(u->MVP, 0, sizeof(u->MVP));
    u->MVP[0]  = 2.0f * fillX;  u->MVP[12] = -fillX;
    u->MVP[5]  = 2.0f * fillY;  u->MVP[13] = -fillY;
    u->MVP[15] = 1.0f;

    memset(pu, 0, sizeof(*pu));
    pu->SourceSize[0]=sw; pu->SourceSize[1]=sh;
    pu->SourceSize[2]= sw?1.0f/sw:0; pu->SourceSize[3]= sh?1.0f/sh:0;
    pu->OriginalSize[0]=sw; pu->OriginalSize[1]=sh;
    pu->OriginalSize[2]=pu->SourceSize[2]; pu->OriginalSize[3]=pu->SourceSize[3];
    pu->OutputSize[0]=dw; pu->OutputSize[1]=dh;
    pu->OutputSize[2]= dw?1.0f/dw:0; pu->OutputSize[3]= dh?1.0f/dh:0;
    pu->FrameCount = 0;
}

// Core single-pass draw into a given target, sampling `src`. Caller owns Begin/End/
// Present framing for the drawable; this fills uniforms, binds, and draws.
- (void)drawSrc:(BackendTexture*)src toTarget:(BackendTexture*)target
           srcW:(uint32_t)sw srcH:(uint32_t)sh dstW:(uint32_t)dw dstH:(uint32_t)dh
      frameCount:(uint32_t)frameCount {
    UBO u; Push pu;
    [self fillUniformsForSrcW:sw srcH:sh dstW:dw dstH:dh ubo:&u push:&pu];
    pu.FrameCount = frameCount;
    _backend.UpdateConstantBuffer(_ubo, &u, sizeof(u));
    _backend.UpdateConstantBuffer(_push, &pu, sizeof(pu));

    BackendShader* shader = _activeShader.load();
    float clear[4] = {0,0,0,1};
    _backend.BeginRenderPass(target, true, clear);
    _backend.SetViewport(0, 0, (float)dw, (float)dh);
    _backend.BindShader(shader);
    _backend.SetVertexBuffer(_vtx, 24, 0);
    _backend.BindConstantBuffer(kUboBufferIndex, _ubo);
    _backend.BindConstantBuffer(kPushBufferIndex, _push);
    _backend.BindTexture(2, src);
    _backend.BindSampler(2, _sampler);
    _backend.SetBlend(BlendMode::Disabled);
    _backend.Draw(4, 4);
    _backend.EndRenderPass();
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
        BackendTexture* drawable = _backend.BeginFrame();
        if (!drawable) return;       // pool starved / no layer -> skip
        [self drawSrc:_staticSrc toTarget:drawable
                 srcW:_srcW srcH:_srcH dstW:_dstW dstH:_dstH frameCount:0];
        _backend.Present();
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
        _backend.ResizeSwapChain(width, height);
        if (!_capturing.load()) [self renderFrameLocked]; // capture path repaints next frame
    }];
}

- (void)setShaderKind:(SGShaderKind)kind {
    if (kind < 0 || kind >= SGShaderCount) kind = SGShaderPassthrough;
    _activeShader.store(_shaders[kind]); // atomic; safe from any thread
    [self runOnRenderThread:^{ if (!_capturing.load()) [self renderFrameLocked]; }];
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
        _capture = new SCKCapture(&_backend, sink, _backend.NativeDevice(), events);
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
        BackendTexture* drawable = _backend.BeginFrame();
        if (!drawable) return;       // nextDrawable nil -> drop this frame
        [self drawSrc:tex toTarget:drawable srcW:w srcH:h dstW:_dstW dstH:_dstH frameCount:frameCount];
        _backend.Present();
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
    BackendTexture* out = _backend.CreateTexture(TextureDesc{w, h, PixFmt::BGRA8_UNORM, true, true});
    [self drawSrc:_staticSrc toTarget:out srcW:w srcH:h dstW:w dstH:h frameCount:0];
    std::vector<uint8_t> px((size_t)w*h*4);
    _backend.ReadbackTexture(out, px.data(), w*4);
    bool ok = EncodePNGFromBGRA(outPath.UTF8String, px.data(), w, h, w*4);
    _backend.DestroyTexture(out);
    return ok;
}

- (void)shutdown {
    [self stopCapture];
    if (_capture) { delete _capture; _capture = nullptr; }
    if (_staticSrc) { _backend.DestroyTexture(_staticSrc); _staticSrc = nullptr; }
    if (_vtx) { _backend.DestroyBuffer(_vtx); _vtx = nullptr; }
    if (_ubo) { _backend.DestroyBuffer(_ubo); _ubo = nullptr; }
    if (_push) { _backend.DestroyBuffer(_push); _push = nullptr; }
    if (_sampler) { _backend.DestroySampler(_sampler); _sampler = nullptr; }
    for (NSInteger i = 0; i < SGShaderCount; ++i) {
        if (_shaders[i]) { _backend.DestroyShader(_shaders[i]); _shaders[i] = nullptr; }
    }
}

- (void)dealloc { [self shutdown]; }

@end
