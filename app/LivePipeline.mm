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

// Private methods used by the FrameSink lambda before their definition.
@interface LivePipeline ()
- (void)onCaptureFrameTex:(BackendTexture*)tex w:(uint32_t)w h:(uint32_t)h frame:(uint32_t)frameCount;
- (void)drawSrc:(BackendTexture*)src toTarget:(BackendTexture*)target
           srcW:(uint32_t)sw srcH:(uint32_t)sh dstW:(uint32_t)dw dstH:(uint32_t)dh
      frameCount:(uint32_t)frameCount;
@end

@implementation LivePipeline {
    MetalBackend     _backend;
    SCKCapture*      _capture;            // C++ owned; created on first startCapture
    BackendShader*   _shaderPassthrough;
    BackendShader*   _shaderCRT;
    std::atomic<BackendShader*> _activeShader;  // hot-swapped by setShaderKind
    BackendBuffer*   _vtx;
    BackendBuffer*   _ubo;
    BackendBuffer*   _push;
    BackendSampler*  _sampler;

    // static-image source (L1/L2)
    BackendTexture*  _staticSrc;
    uint32_t         _srcW, _srcH;        // current source dimensions
    uint32_t         _dstW, _dstH;        // current drawable dimensions
    bool             _capturing;
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

    // compile both shaders once
    std::string pt = readTextFile([shaderDir stringByAppendingPathComponent:@"passthrough.metal"]);
    std::string crt = readTextFile([shaderDir stringByAppendingPathComponent:@"crt_demo.metal"]);
    if (pt.empty() || crt.empty()) {
        NSLog(@"LivePipeline: cannot read shaders from %@", shaderDir);
        return nil;
    }
    _shaderPassthrough = _backend.CreateShader(pt.data(), pt.size(), pt.data(), pt.size());
    _shaderCRT         = _backend.CreateShader(crt.data(), crt.size(), crt.data(), crt.size());
    if (!_shaderPassthrough || !_shaderCRT) {
        NSLog(@"LivePipeline: shader compile failed");
        return nil;
    }
    _activeShader.store(_shaderPassthrough);

    // once-created GPU resources
    _vtx     = _backend.CreateVertexBuffer(kVertexBuffer, sizeof(kVertexBuffer));
    _ubo     = _backend.CreateConstantBuffer(sizeof(UBO));
    _push    = _backend.CreateConstantBuffer(sizeof(Push));
    _sampler = _backend.CreateSampler(SamplerDesc{Filter::Linear, Wrap::Border});
    _capturing = false;
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

- (void)renderFrame {
    if (_capturing) return;          // capture path drives its own frames
    if (!_staticSrc) return;
    @autoreleasepool {
        BackendTexture* drawable = _backend.BeginFrame();
        if (!drawable) return;       // pool starved / no layer -> skip
        [self drawSrc:_staticSrc toTarget:drawable
                 srcW:_srcW srcH:_srcH dstW:_dstW dstH:_dstH frameCount:0];
        _backend.Present();
    }
}

- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height {
    _dstW = width; _dstH = height;
    _backend.ResizeSwapChain(width, height);
    [self renderFrame];              // re-render static source at the new size
}

- (void)setShaderKind:(SGShaderKind)kind {
    _activeShader.store(kind == SGShaderCRT ? _shaderCRT : _shaderPassthrough);
    [self renderFrame];              // immediate repaint for the static path
}

- (void)startCaptureKind:(SGTargetKind)kind targetID:(uint32_t)targetID {
    if (!_capture) {
        __weak LivePipeline* weakSelf = self;
        // FrameSink: render the captured texture into the drawable, on the capture
        // serial queue (the designated render thread). @autoreleasepool is mandatory.
        FrameSink sink = [weakSelf](const CaptureFrame& f) {
            LivePipeline* s = weakSelf;
            if (!s) return;
            [s onCaptureFrameTex:f.texture w:f.width h:f.height frame:(uint32_t)f.inputFrameNo];
        };
        _capture = new SCKCapture(&_backend, sink);
    }
    _capturing = true;
    CaptureTarget t;
    t.kind = (kind == SGTargetWindow) ? CaptureTargetKind::Window : CaptureTargetKind::Display;
    t.id   = targetID;
    _capture->Start(t, /*maxRate*/false, /*cursor*/false);
}

// Called from the capture serial queue.
- (void)onCaptureFrameTex:(BackendTexture*)tex w:(uint32_t)w h:(uint32_t)h frame:(uint32_t)frameCount {
    @autoreleasepool {
        BackendTexture* drawable = _backend.BeginFrame();
        if (!drawable) return;       // nextDrawable nil -> drop this frame
        [self drawSrc:tex toTarget:drawable srcW:w srcH:h dstW:_dstW dstH:_dstH frameCount:frameCount];
        _backend.Present();
    }
}

- (void)stopCapture {
    _capturing = false;
    if (_capture) _capture->Stop();
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
    if (_shaderPassthrough) { _backend.DestroyShader(_shaderPassthrough); _shaderPassthrough = nullptr; }
    if (_shaderCRT) { _backend.DestroyShader(_shaderCRT); _shaderCRT = nullptr; }
}

- (void)dealloc { [self shutdown]; }

@end
