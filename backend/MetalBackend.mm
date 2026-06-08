/*
ShaderGlass macOS port -- MetalBackend.mm

Concrete Metal implementation of IRenderBackend. The binding conventions here
(buffer indices, sampler mapping, MVP-no-transpose, triangle-strip start vertex)
are the ones VERIFIED pixel-perfect by mac/spike. This file lifts that proven
mapping behind the interface.
*/

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>   // CAMetalLayer / CAMetalDrawable (windowed present path)
#import <CoreGraphics/CoreGraphics.h>
#include "MetalBackend.h"
#include <cstdio>

namespace sg {

// ---- internal handle types (opaque to the engine) ----
namespace {
struct MTexture { id<MTLTexture> tex; bool owned; };
// Shader is render-target-FORMAT-AGNOSTIC: it holds the compiled functions + the
// shared vertex descriptor, and lazily builds/caches one PSO per
// (colorAttachment pixelFormat, blend mode). See IRenderBackend::CreateShader.
struct MShader {
    id<MTLFunction>      vs;
    id<MTLFunction>      fs;
    MTLVertexDescriptor* vdesc;
    NSMutableDictionary<NSNumber*, id<MTLRenderPipelineState>>* psoCache; // key: fmt<<1 | blend
};
// A constant/vertex buffer. For dynamic constant buffers we allocate kFramesInFlight
// ring slots in one MTLBuffer (slotStride bytes each, 256-aligned for constant-buffer
// offset rules) so the no-wait present path never overwrites a slot the GPU is still
// reading from an in-flight frame. Vertex buffers use slot 0 only (slotStride==0).
struct MBuffer  { id<MTLBuffer> buf; uint32_t slotStride; };
struct MSampler { id<MTLSamplerState> samp; };

// Frames the present path may keep in flight; must match layer.maximumDrawableCount.
static constexpr uint32_t kFramesInFlight = 3;

MTLPixelFormat toMTL(PixFmt f) {
    switch (f) {
        case PixFmt::R8_UNORM:      return MTLPixelFormatR8Unorm;
        case PixFmt::R8_UINT:       return MTLPixelFormatR8Uint;
        case PixFmt::R8_SINT:       return MTLPixelFormatR8Sint;
        case PixFmt::RG8_UNORM:     return MTLPixelFormatRG8Unorm;
        case PixFmt::RG8_UINT:      return MTLPixelFormatRG8Uint;
        case PixFmt::RG8_SINT:      return MTLPixelFormatRG8Sint;
        case PixFmt::BGRA8_UNORM:   return MTLPixelFormatBGRA8Unorm;
        case PixFmt::RGBA8_UINT:    return MTLPixelFormatRGBA8Uint;
        case PixFmt::RGBA8_SINT:    return MTLPixelFormatRGBA8Sint;
        case PixFmt::BGRA8_SRGB:    return MTLPixelFormatBGRA8Unorm_sRGB;
        case PixFmt::RGB10A2_UNORM: return MTLPixelFormatRGB10A2Unorm;
        case PixFmt::RGB10A2_UINT:  return MTLPixelFormatRGB10A2Uint;
        case PixFmt::R16_UINT:      return MTLPixelFormatR16Uint;
        case PixFmt::R16_SINT:      return MTLPixelFormatR16Sint;
        case PixFmt::R16_SFLOAT:    return MTLPixelFormatR16Float;
        case PixFmt::RG16_UINT:     return MTLPixelFormatRG16Uint;
        case PixFmt::RG16_SINT:     return MTLPixelFormatRG16Sint;
        case PixFmt::RG16_SFLOAT:   return MTLPixelFormatRG16Float;
        case PixFmt::RGBA16_UINT:   return MTLPixelFormatRGBA16Uint;
        case PixFmt::RGBA16_SINT:   return MTLPixelFormatRGBA16Sint;
        case PixFmt::RGBA16_SFLOAT: return MTLPixelFormatRGBA16Float;
        case PixFmt::R32_UINT:      return MTLPixelFormatR32Uint;
        case PixFmt::R32_SINT:      return MTLPixelFormatR32Sint;
        case PixFmt::R32_SFLOAT:    return MTLPixelFormatR32Float;
        case PixFmt::RG32_UINT:     return MTLPixelFormatRG32Uint;
        case PixFmt::RG32_SINT:     return MTLPixelFormatRG32Sint;
        case PixFmt::RG32_SFLOAT:   return MTLPixelFormatRG32Float;
        case PixFmt::RGBA32_UINT:   return MTLPixelFormatRGBA32Uint;
        case PixFmt::RGBA32_SINT:   return MTLPixelFormatRGBA32Sint;
        case PixFmt::RGBA32_SFLOAT: return MTLPixelFormatRGBA32Float;
        default:                    return MTLPixelFormatBGRA8Unorm;
    }
}
} // namespace

struct MetalBackend::Impl {
    id<MTLDevice>               device = nil;
    id<MTLCommandQueue>         queue  = nil;
    // current render pass state
    id<MTLCommandBuffer>        cb  = nil;
    id<MTLRenderCommandEncoder> enc = nil;
    MTLVertexDescriptor*        vdesc = nil; // shared: pos float4@0, uv float2@16, stride 24, idx 30
    MTLPixelFormat              curTargetFmt = MTLPixelFormatBGRA8Unorm; // format of the BeginRenderPass target
    BlendMode                   curBlend = BlendMode::Disabled;          // active blend (PSO selector)
    void*                       boundShader = nullptr;                   // MShader* resolved to a PSO at Draw
    // --- windowed present path (CAMetalLayer) ---
    CAMetalLayer*               layer = nil;            // owned by the AppKit view, not us
    id<CAMetalDrawable>         curDrawable = nil;      // acquired in BeginFrame, presented in Present
    MTexture*                   curFrameTarget = nullptr; // heap wrapper for curDrawable.texture (freed in Present)
    bool                        curTargetIsDrawable = false; // set in BeginRenderPass; gates the no-wait present
    CGColorSpaceRef             colorSpace = nullptr;
    uint32_t                    frameRing = 0;          // advances per BeginFrame; selects the constant-buffer slot
};

MetalBackend::MetalBackend() : p(new Impl) {}
MetalBackend::~MetalBackend() {
    if (p) {
        p->enc = nil; p->cb = nil;
        p->curDrawable = nil;
        if (p->curFrameTarget) { delete p->curFrameTarget; p->curFrameTarget = nullptr; }
        p->layer = nil; // owned by the view; do not destroy
        if (p->colorSpace) { CGColorSpaceRelease(p->colorSpace); p->colorSpace = nullptr; }
        p->queue = nil; p->device = nil;
        delete p; p = nullptr;
    }
}

// Concrete accessor (NOT on the neutral IRenderBackend) so SCKCapture can share the
// one device instead of creating a second via MTLCreateSystemDefaultDevice.
void* MetalBackend::NativeDevice() { return (__bridge void*)p->device; }

bool MetalBackend::InitializeHeadless() {
    p->device = MTLCreateSystemDefaultDevice();
    if (!p->device) return false;
    p->queue = [p->device newCommandQueue];

    p->vdesc = [[MTLVertexDescriptor alloc] init];
    p->vdesc.attributes[0].format = MTLVertexFormatFloat4;
    p->vdesc.attributes[0].offset = 0;
    p->vdesc.attributes[0].bufferIndex = kGeometryBufferIndex;
    p->vdesc.attributes[1].format = MTLVertexFormatFloat2;
    p->vdesc.attributes[1].offset = 16;
    p->vdesc.attributes[1].bufferIndex = kGeometryBufferIndex;
    p->vdesc.layouts[kGeometryBufferIndex].stride = 24;
    p->vdesc.layouts[kGeometryBufferIndex].stepFunction = MTLVertexStepFunctionPerVertex;
    return true;
}

// Windowed present path. nativeLayer is a CAMetalLayer* created + owned by the
// AppKit view; we configure it (device/format/colorspace) but never destroy it.
bool MetalBackend::Initialize(void* nativeLayer, uint32_t w, uint32_t h, bool hdr) {
    if (!InitializeHeadless()) return false; // device + queue + shared vdesc
    if (!nativeLayer) return true;           // headless caller (tests/demo) passes null
    p->layer = (__bridge CAMetalLayer*)nativeLayer;
    p->layer.device = p->device;
    // SDR path: BGRA8 (NON-sRGB, matches the verified raw-UNORM chain) tagged sRGB so
    // the compositor does not misread the bytes as the display's wide-gamut space.
    // HDR/EDR is deferred -- but don't silently honor hdr=true and return an SDR
    // surface contrary to the interface contract; make the gap loud (REVIEW J4).
    if (hdr)
        fprintf(stderr, "MetalBackend: HDR requested but not implemented; using SDR BGRA8.\n");
    p->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    if (!p->colorSpace) p->colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    p->layer.colorspace = p->colorSpace;
    p->layer.framebufferOnly = YES;          // drawable is only ever a color attachment; never read back
    p->layer.maximumDrawableCount = 3;       // bound capture/present coupling; do not raise to mask stalls
    if (w && h) ResizeSwapChain(w, h);
    return true;
}

void MetalBackend::ResizeSwapChain(uint32_t w, uint32_t h) {
    if (!p->layer || !w || !h) return;
    p->layer.drawableSize = CGSizeMake((CGFloat)w, (CGFloat)h); // device pixels
    if (p->colorSpace) p->layer.colorspace = p->colorSpace;     // re-assert after size change
}

BackendTexture* MetalBackend::BeginFrame() {
    if (!p->layer) return nullptr;                              // headless: no swap chain
    // Self-clean: if a prior frame was abandoned between BeginFrame and Present
    // (early return / loop-back), tear it down here so we never leak the wrapper or
    // strand a drawable in the pool (J2). cb here is an uncommitted drawable cb -> drop it.
    if (p->curFrameTarget) { delete p->curFrameTarget; p->curFrameTarget = nullptr; }
    p->cb = nil;
    p->curDrawable = nil;
    p->curTargetIsDrawable = false;

    p->curDrawable = [p->layer nextDrawable];
    if (!p->curDrawable) return nullptr;                        // pool starved / 1s timeout -> caller skips frame
    p->frameRing = (p->frameRing + 1) % kFramesInFlight;        // advance constant-buffer ring slot for this frame
    // Heap-allocate the wrapper so DestroyTexture's `delete` is always safe (the
    // borrowed-target no-op contract). Freed in Present(). NOT an interior Impl pointer.
    p->curFrameTarget = new MTexture{ p->curDrawable.texture, false };
    return reinterpret_cast<BackendTexture*>(p->curFrameTarget);
}

void MetalBackend::Present() {
    if (!p->cb || !p->curDrawable) {                            // nothing to present (skipped frame / partial)
        if (p->curFrameTarget) { delete p->curFrameTarget; p->curFrameTarget = nullptr; }
        p->curDrawable = nil; p->curTargetIsDrawable = false;
        return;
    }
    if (p->enc) { [p->enc endEncoding]; p->enc = nil; }         // abort-safety if the pass was left open
    [p->cb presentDrawable:p->curDrawable];
    [p->cb commit];                                            // NO waitUntilCompleted on the present path
    p->cb = nil;
    if (p->curFrameTarget) { delete p->curFrameTarget; p->curFrameTarget = nullptr; }
    p->curDrawable = nil;
    p->curTargetIsDrawable = false;
}

BackendTexture* MetalBackend::CreateTexture(const TextureDesc& d, const void* initialData, size_t rowPitch) {
    MTLTextureDescriptor* td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:toMTL(d.format)
                                                           width:d.width height:d.height mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead | (d.renderTarget ? MTLTextureUsageRenderTarget : 0);
    td.storageMode = MTLStorageModeShared; // pin host-visible (Readback/Upload depend on it; portable across GPUs)
    id<MTLTexture> tex = [p->device newTextureWithDescriptor:td];
    if (initialData && rowPitch) // CPU pixel upload (preset LUT/image; Texture.cpp path)
        [tex replaceRegion:MTLRegionMake2D(0, 0, d.width, d.height) mipmapLevel:0
                 withBytes:initialData bytesPerRow:rowPitch];
    auto* t = new MTexture{ tex, true };
    return reinterpret_cast<BackendTexture*>(t);
}

BackendTexture* MetalBackend::WrapNativeFrame(void* nativeFrame, const TextureDesc&) {
    // nativeFrame is an id<MTLTexture> (the SCK/IOSurface import happens in capture).
    auto* t = new MTexture{ (__bridge id<MTLTexture>)nativeFrame, false };
    return reinterpret_cast<BackendTexture*>(t);
}

void MetalBackend::DestroyTexture(BackendTexture* h) {
    if (!h) return;
    auto* t = reinterpret_cast<MTexture*>(h);
    t->tex = nil; delete t;
}

BackendShader* MetalBackend::CreateShader(const void* vertexCode, size_t vLen,
                                          const void* fragmentCode, size_t fLen) {
    NSError* err = nil;
    // vertexCode/fragmentCode are MSL source. Hand-ported shaders carry both
    // vs_main and fs_main in one source (callers pass the same pointer for both);
    // SPIRV-Cross output (M4) will too. We compile each blob and pull the matching
    // entry point. The PSO is NOT built here -- it is render-target-format-agnostic
    // and built lazily per (target format, blend mode) at draw time (see psoFor).
    NSString* vsrc = [[NSString alloc] initWithBytes:vertexCode length:vLen encoding:NSUTF8StringEncoding];
    id<MTLLibrary> vlib = [p->device newLibraryWithSource:vsrc options:nil error:&err];
    if (!vlib) { fprintf(stderr, "MetalBackend: vertex MSL compile failed: %s\n", err.localizedDescription.UTF8String); return nullptr; }
    id<MTLLibrary> flib;
    if (fragmentCode == vertexCode) { // single combined-source blob (documented fast path)
        flib = vlib;
    } else {
        NSString* fsrc = [[NSString alloc] initWithBytes:fragmentCode length:fLen encoding:NSUTF8StringEncoding];
        flib = [p->device newLibraryWithSource:fsrc options:nil error:&err];
    }
    if (!flib) { fprintf(stderr, "MetalBackend: fragment MSL compile failed: %s\n", err.localizedDescription.UTF8String); return nullptr; }

    id<MTLFunction> vs = [vlib newFunctionWithName:@"vs_main"];
    id<MTLFunction> fs = [flib newFunctionWithName:@"fs_main"];
    if (!vs || !fs) { fprintf(stderr, "MetalBackend: missing vs_main/fs_main\n"); return nullptr; }

    auto* s = new MShader{ vs, fs, p->vdesc, [NSMutableDictionary dictionary] };
    return reinterpret_cast<BackendShader*>(s);
}

// Resolve (build + cache) the PSO for a shader at the given color-attachment
// format and blend mode. Key packs (format << 1 | blend-bit). Returns the PSO as
// an opaque void* (the header stays Metal-type-free); callers __bridge back.
void* MetalBackend::psoFor(void* shaderHandle, uint32_t mtlFmt, BlendMode blend) {
    if (!shaderHandle) return nullptr;          // BindShader never called for this pass -> no draw
    auto* s = reinterpret_cast<MShader*>(shaderHandle);
    uint64_t key = ((uint64_t)mtlFmt << 1) | (blend == BlendMode::AlphaOver ? 1u : 0u);
    NSNumber* k = @(key);
    id<MTLRenderPipelineState> cached = s->psoCache[k];
    if (cached) return (__bridge void*)cached;

    MTLRenderPipelineDescriptor* pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction = s->vs;
    pd.fragmentFunction = s->fs;
    pd.vertexDescriptor = s->vdesc;
    MTLRenderPipelineColorAttachmentDescriptor* ca = pd.colorAttachments[0];
    ca.pixelFormat = (MTLPixelFormat)mtlFmt;
    if (blend == BlendMode::AlphaOver) {
        // mirrors the engine cursor blend (ShaderPass.cpp:192-199):
        // SrcBlend=SRC_ALPHA, DestBlend=INV_SRC_ALPHA, op ADD;
        // SrcBlendAlpha=ONE, DestBlendAlpha=ZERO, opAlpha ADD.
        ca.blendingEnabled = YES;
        ca.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        ca.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        ca.rgbBlendOperation = MTLBlendOperationAdd;
        ca.sourceAlphaBlendFactor = MTLBlendFactorOne;
        ca.destinationAlphaBlendFactor = MTLBlendFactorZero;
        ca.alphaBlendOperation = MTLBlendOperationAdd;
    }
    NSError* err = nil;
    id<MTLRenderPipelineState> pso = [p->device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!pso) { fprintf(stderr, "MetalBackend: PSO build failed (fmt=%u blend=%d): %s\n",
                        mtlFmt, (int)blend, err.localizedDescription.UTF8String); return nullptr; }
    s->psoCache[k] = pso;
    return (__bridge void*)pso;
}

void MetalBackend::DestroyShader(BackendShader* h) {
    if (!h) return; auto* s = reinterpret_cast<MShader*>(h);
    s->vs = nil; s->fs = nil; s->vdesc = nil; [s->psoCache removeAllObjects]; s->psoCache = nil;
    delete s;
}

BackendBuffer* MetalBackend::CreateVertexBuffer(const void* data, size_t size) {
    id<MTLBuffer> b = [p->device newBufferWithBytes:data length:size options:MTLResourceStorageModeShared];
    return reinterpret_cast<BackendBuffer*>(new MBuffer{ b, /*slotStride*/0 });
}
BackendBuffer* MetalBackend::CreateConstantBuffer(size_t size) {
    // Round each slot up to 256B (Apple GPU constant-buffer offset alignment), then
    // allocate kFramesInFlight slots so frame N+1's UpdateConstantBuffer never clobbers
    // a slot frame N's GPU work is still reading (the no-wait present hazard, J1).
    size_t slot = (size + 0xffu) & ~size_t(0xffu);
    if (slot == 0) slot = 256;
    id<MTLBuffer> b = [p->device newBufferWithLength:slot * kFramesInFlight options:MTLResourceStorageModeShared];
    return reinterpret_cast<BackendBuffer*>(new MBuffer{ b, (uint32_t)slot });
}
void MetalBackend::DestroyBuffer(BackendBuffer* h) {
    if (!h) return; auto* b = reinterpret_cast<MBuffer*>(h); b->buf = nil; delete b;
}

BackendSampler* MetalBackend::CreateSampler(const SamplerDesc& d) {
    MTLSamplerDescriptor* sd = [[MTLSamplerDescriptor alloc] init];
    MTLSamplerMinMagFilter f = (d.filter == Filter::Linear) ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
    sd.minFilter = f; sd.magFilter = f;
    MTLSamplerAddressMode a;
    switch (d.wrap) {
        case Wrap::Clamp:  a = MTLSamplerAddressModeClampToEdge; break;
        case Wrap::Repeat: a = MTLSamplerAddressModeRepeat; break;
        case Wrap::Mirror: a = MTLSamplerAddressModeMirrorRepeat; break;
        case Wrap::Border: default: a = MTLSamplerAddressModeClampToBorderColor; break;
    }
    sd.sAddressMode = a; sd.tAddressMode = a; sd.rAddressMode = a;
    sd.borderColor = MTLSamplerBorderColorTransparentBlack;
    return reinterpret_cast<BackendSampler*>(new MSampler{ [p->device newSamplerStateWithDescriptor:sd] });
}
void MetalBackend::DestroySampler(BackendSampler* h) {
    if (!h) return; auto* s = reinterpret_cast<MSampler*>(h); s->samp = nil; delete s;
}

// Offset of the current frame's ring slot for a constant buffer.
static inline NSUInteger frameSlotOffset(MBuffer* b, uint32_t frameRing) {
    return b->slotStride ? (NSUInteger)b->slotStride * (frameRing % kFramesInFlight) : 0;
}

void MetalBackend::UpdateConstantBuffer(BackendBuffer* h, const void* data, size_t size) {
    auto* b = reinterpret_cast<MBuffer*>(h);
    NSUInteger off = frameSlotOffset(b, p->frameRing);
    if (off + size > (size_t)b->buf.length) { // guard against silent heap corruption
        fprintf(stderr, "MetalBackend: UpdateConstantBuffer size %zu (off %lu) exceeds buffer length %lu\n",
                size, (unsigned long)off, (unsigned long)b->buf.length);
        return;
    }
    // Write into THIS frame's ring slot; storageShared -> CPU-visible; MVP bytes verbatim.
    memcpy((char*)b->buf.contents + off, data, size);
}

void MetalBackend::BeginRenderPass(BackendTexture* target, bool clear, const float clearColor[4]) {
    auto* t = reinterpret_cast<MTexture*>(target);
    if (!t) { // BeginFrame can legitimately return nullptr (starved drawable); don't deref/crash (J3)
        p->enc = nil; p->cb = nil; p->curTargetIsDrawable = false;
        fprintf(stderr, "MetalBackend: BeginRenderPass on null target -- pass skipped\n");
        return;
    }
    // Order-fragility guard: a live drawable cb means a prior drawable pass was never
    // presented; entering a new pass would drop it uncommitted (REVIEW finding 7).
    if (p->cb && p->curTargetIsDrawable)
        fprintf(stderr, "MetalBackend: BeginRenderPass entered with a live drawable command buffer\n");
    // Drawable target => present path (no blocking commit in EndRenderPass).
    p->curTargetIsDrawable = (p->curFrameTarget != nullptr && t == p->curFrameTarget);
    p->curTargetFmt = t->tex.pixelFormat; // PSO color-attachment format follows the bound target
    MTLRenderPassDescriptor* rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = t->tex;
    rp.colorAttachments[0].loadAction = clear ? MTLLoadActionClear : MTLLoadActionLoad;
    if (clear)
        rp.colorAttachments[0].clearColor =
            MTLClearColorMake(clearColor ? clearColor[0] : 0, clearColor ? clearColor[1] : 0,
                              clearColor ? clearColor[2] : 0, clearColor ? clearColor[3] : 1);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    p->cb = [p->queue commandBuffer];
    p->enc = [p->cb renderCommandEncoderWithDescriptor:rp];
}

void MetalBackend::EndRenderPass() {
    [p->enc endEncoding];
    p->enc = nil;
    p->boundShader = nullptr;
    p->curBlend = BlendMode::Disabled; // reset per-pass blend (engine restores Disabled after cursor)
    if (p->curTargetIsDrawable) {
        // Present path: leave p->cb live; Present() does presentDrawable + commit (no wait).
        return;
    }
    // Offscreen/headless path: commit + wait so output is immediately readable (tests/demo).
    [p->cb commit];
    [p->cb waitUntilCompleted];
    p->cb = nil;
}

void MetalBackend::SetViewport(float x, float y, float w, float h) {
    [p->enc setViewport:(MTLViewport){ x, y, w, h, 0, 1 }];
}
void MetalBackend::BindShader(BackendShader* h) {
    // Defer PSO selection to Draw: the correct color-attachment format
    // (curTargetFmt, set in BeginRenderPass) and blend (curBlend, set by SetBlend)
    // may both be established around BindShader, so we resolve once at the draw.
    p->boundShader = h;
}
void MetalBackend::SetVertexBuffer(BackendBuffer* h, uint32_t stride, uint32_t offset) {
    // stride is fixed (24B) by the shared MTLVertexDescriptor; assert coordinated edits.
    (void)stride; // NSCAssert avoided in this no-exceptions backend
    if (stride != 24) fprintf(stderr, "MetalBackend: unexpected vertex stride %u (descriptor pins 24)\n", stride);
    [p->enc setVertexBuffer:reinterpret_cast<MBuffer*>(h)->buf offset:offset atIndex:kGeometryBufferIndex];
}
void MetalBackend::BindTexture(uint32_t slot, BackendTexture* h) {
    [p->enc setFragmentTexture:(h ? reinterpret_cast<MTexture*>(h)->tex : nil) atIndex:slot];
}
void MetalBackend::BindSampler(uint32_t slot, BackendSampler* h) {
    [p->enc setFragmentSamplerState:reinterpret_cast<MSampler*>(h)->samp atIndex:slot];
}
void MetalBackend::BindConstantBuffer(uint32_t index, BackendBuffer* h) {
    auto* mb = reinterpret_cast<MBuffer*>(h);
    NSUInteger off = frameSlotOffset(mb, p->frameRing); // bind THIS frame's ring slot (must match Update)
    [p->enc setVertexBuffer:mb->buf offset:off atIndex:index];   // both stages, matching VS+PSSetConstantBuffers
    [p->enc setFragmentBuffer:mb->buf offset:off atIndex:index];
}
void MetalBackend::SetBlend(BlendMode mode) {
    // Blend is baked into the PSO; record it so Draw selects the matching variant
    // (Disabled for shader passes, AlphaOver for the cursor overlay -- RenderCursor).
    p->curBlend = mode;
}
void MetalBackend::Draw(uint32_t vertexCount, uint32_t startVertex) {
    if (!p->enc) return;                       // skipped/abandoned pass (e.g. null BeginRenderPass target)
    // Resolve the PSO now: format from the bound target, blend from SetBlend.
    void* pso = psoFor(p->boundShader, (uint32_t)p->curTargetFmt, p->curBlend);
    if (!pso) return;                          // PSO compile failed (logged in psoFor); don't draw with stale/no pipeline (J5)
    [p->enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso];
    [p->enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:startVertex vertexCount:vertexCount];
}

void MetalBackend::CopyTexture(BackendTexture* dest, BackendTexture* source,
                               const CopyOrigin* so, const CopyExtent* ss, const CopyOrigin* dorg) {
    auto* d = reinterpret_cast<MTexture*>(dest);
    auto* s = reinterpret_cast<MTexture*>(source);
    id<MTLCommandBuffer> cb = [p->queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    MTLOrigin srcO = MTLOriginMake(so ? so->x : 0, so ? so->y : 0, 0);
    MTLSize   srcSz = ss ? MTLSizeMake(ss->width, ss->height, 1)
                         : MTLSizeMake(s->tex.width, s->tex.height, 1);
    MTLOrigin dstO = MTLOriginMake(dorg ? dorg->x : 0, dorg ? dorg->y : 0, 0);
    [blit copyFromTexture:s->tex sourceSlice:0 sourceLevel:0 sourceOrigin:srcO sourceSize:srcSz
                toTexture:d->tex destinationSlice:0 destinationLevel:0 destinationOrigin:dstO];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
}

// IRenderBackend verb: read a storageShared texture's pixels back to host memory.
// (GrabOutput / screenshot path.) The texture is storageModeShared so getBytes is
// valid directly; the prior render/blit already completed under the per-pass wait.
void MetalBackend::ReadbackTexture(BackendTexture* h, void* dst, size_t rowPitch) {
    auto* t = reinterpret_cast<MTexture*>(h);
    [t->tex getBytes:dst bytesPerRow:rowPitch
          fromRegion:MTLRegionMake2D(0, 0, t->tex.width, t->tex.height) mipmapLevel:0];
}

std::vector<uint8_t> MetalBackend::ReadbackBGRA(BackendTexture* h, uint32_t w, uint32_t height) {
    std::vector<uint8_t> out(w * height * 4);
    ReadbackTexture(h, out.data(), w * 4);
    return out;
}

void MetalBackend::UploadBGRA(BackendTexture* h, const uint8_t* bytes, uint32_t w, uint32_t height) {
    auto* t = reinterpret_cast<MTexture*>(h);
    [t->tex replaceRegion:MTLRegionMake2D(0, 0, w, height) mipmapLevel:0
                withBytes:bytes bytesPerRow:w * 4];
}

} // namespace sg
