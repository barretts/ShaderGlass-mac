/*
ShaderGlass: shader effect overlay
Copyright (C) 2021-2025 mausimus (mausimus.net)
https://github.com/mausimus/ShaderGlass
GNU General Public License v3.0

------------------------------------------------------------------------------
IRenderBackend.h -- backend-neutral rendering interface for the macOS port.

This abstracts the D3D11 verbs that the Windows engine issues from ShaderPass.cpp
(per-pass draw) and ShaderGlass.cpp (swap-chain / resource / copy / present loop)
so the same engine logic can drive a Metal backend on macOS or the existing D3D11
backend on Windows.

The Metal mapping below is VERIFIED: the M-1 spike (mac/spike/main.mm +
passthrough.metal) ran pixel-perfect on real Apple Silicon hardware and pinned
down every binding convention this interface assumes:

  * Geometry / vertex buffer is bound at Metal buffer index 30 (must not alias
    the constant buffers). See kGeometryBufferIndex below.
  * The UBO constant buffer (D3D register b0) maps to Metal buffer index 0, bound
    to BOTH the vertex and fragment stages (matches VSSetConstantBuffers(0,...)
    + PSSetConstantBuffers(0,...)).
  * The Push constant buffer (D3D register b1) maps to Metal buffer index 1, also
    bound to both stages (matches the (1,...) binding in ShaderPass::Render).
  * Textures and samplers are bound by the SPIR-V/D3D binding slot reported in
    ShaderDef::Samplers (PSSetShaderResources(binding,...) /
    PSSetSamplers(binding,...) -> setFragmentTexture:atIndex: /
    setFragmentSamplerState:atIndex:). SPIRV-Cross emits texture+sampler at the
    same Metal index, so one slot integer drives both.
  * The internal working format is BGRA8 unorm (the engine's sFormats table maps
    the *layout* "R8G8B8A8_UNORM" to DXGI_FORMAT_B8G8R8A8_UNORM, i.e. BGRA, not
    the literal RGBA the SPIR-V name implies). PixFmt mirrors this layout-based
    mapping exactly.
  * The default shader-pass MVP (row-major, ShaderPass.cpp:164-169) is uploaded
    as raw 64 bytes with NO transpose -- the spike proved Metal consumes it
    directly. UpdateConstantBuffer copies bytes verbatim; the engine owns layout.
  * Sampler BORDER -> clampToBorderColor + transparentBlack; point filter ->
    Nearest. See Filter / Wrap below.
  * The shader-pass quad is drawn as a triangle strip of 4 vertices starting at
    vertex 4 (Draw(4,4)); the preprocess pass starts at vertex 0 (Draw(4,0)).

This header is strictly backend-neutral. It MUST NOT include windows.h, d3d11.h,
dxgi*.h, or any winrt header. Only <cstdint>, <cstddef>, <string> are permitted.
All native objects (ID3D11* / MTL*) live behind the opaque handle structs below
and are owned by the concrete backend.
------------------------------------------------------------------------------
*/

#pragma once

#include <cstdint>
#include <cstddef>
#include <string>

namespace sg {

// ----------------------------------------------------------------------------
// Opaque handles.
//
// These are forward-declared, never-defined tag types. The engine holds them by
// pointer only; the concrete backend defines the real struct internally and
// reinterpret_casts at the boundary. This keeps every native type
// (ID3D11Texture2D / id<MTLTexture>, ID3D11Buffer / id<MTLBuffer>, ...) out of
// the engine's translation units.
//
// Ownership: every handle returned by a Create*/Wrap* method is owned by the
// caller and must be released with the matching Destroy* call. Handles passed
// into draw/copy methods are borrowed (not retained past the call) unless noted.
// ----------------------------------------------------------------------------
struct BackendTexture; // D3D: ID3D11Texture2D (+ its RTV/SRV)   Metal: id<MTLTexture>
struct BackendShader;  // D3D: ID3D11VertexShader + ID3D11PixelShader + input layout
                       // Metal: id<MTLRenderPipelineState> (+ vertex descriptor)
struct BackendBuffer;  // D3D: ID3D11Buffer (vertex / constant / push)
                       // Metal: id<MTLBuffer>
struct BackendSampler; // D3D: ID3D11SamplerState   Metal: id<MTLSamplerState>

// ----------------------------------------------------------------------------
// Metal binding-index constants verified by the M-1 spike.
//
// The constant-buffer indices (0 = UBO/b0, 1 = Push/b1) and the geometry buffer
// index (30) are part of the backend contract because SPIRV-Cross emits MSL that
// references them by these exact numbers. They are surfaced here so the engine
// and backend agree without a magic number buried in the .mm.
// ----------------------------------------------------------------------------
static constexpr uint32_t kUboBufferIndex      = 0;  // D3D register b0  -> Metal buffer(0)
static constexpr uint32_t kPushBufferIndex     = 1;  // D3D register b1  -> Metal buffer(1)
static constexpr uint32_t kGeometryBufferIndex = 30; // vertex stream    -> Metal buffer(30)

// ----------------------------------------------------------------------------
// PixFmt -- pixel formats, enumerated by MEMORY LAYOUT, not by SPIR-V channel
// name. This is the load-bearing subtlety: Shader.cpp's sFormats table maps the
// SPIR-V layout token "R8G8B8A8_UNORM" to DXGI_FORMAT_B8G8R8A8_UNORM (BGRA), and
// "R8G8B8A8_SRGB" to DXGI_FORMAT_B8G8R8A8_UNORM_SRGB (BGRA sRGB). We replicate
// that by giving each sFormats row an enumerant named for the layout the engine
// actually allocates, then mapping to DXGI on Windows and MTLPixelFormat on Metal
// in the concrete backend.
//
// The "// <- sFormats key" comments record which sFormats row each enumerant
// covers so the backend's format tables can be cross-checked against Shader.cpp.
// ----------------------------------------------------------------------------
enum class PixFmt : uint32_t
{
    Unknown = 0,

    // --- 8-bit single / dual channel ---
    R8_UNORM,        // <- "R8_UNORM"     DXGI_FORMAT_R8_UNORM        MTLPixelFormatR8Unorm
    R8_UINT,         // <- "R8_UINT"      DXGI_FORMAT_R8_UINT         MTLPixelFormatR8Uint
    R8_SINT,         // <- "R8_SINT"      (sFormats reuses R8_UINT)   MTLPixelFormatR8Sint
    RG8_UNORM,       // <- "R8G8_UNORM"   DXGI_FORMAT_R8G8_UNORM      MTLPixelFormatRG8Unorm
    RG8_UINT,        // <- "R8G8_UINT"    DXGI_FORMAT_R8G8_UINT       MTLPixelFormatRG8Uint
    RG8_SINT,        // <- "R8G8_SINT"    DXGI_FORMAT_R8G8_SINT       MTLPixelFormatRG8Sint

    // --- 8-bit four channel. NOTE the layout flip: the SPIR-V "R8G8B8A8" names
    //     resolve to BGRA storage in the engine, so the engine's whole internal
    //     working chain is BGRA8. This is the format the spike rendered with. ---
    BGRA8_UNORM,     // <- "R8G8B8A8_UNORM"  DXGI_FORMAT_B8G8R8A8_UNORM       MTLPixelFormatBGRA8Unorm
    RGBA8_UINT,      // <- "R8G8B8A8_UINT"   DXGI_FORMAT_R8G8B8A8_UINT        MTLPixelFormatRGBA8Uint
    RGBA8_SINT,      // <- "R8G8B8A8_SINT"   DXGI_FORMAT_R8G8B8A8_SINT        MTLPixelFormatRGBA8Sint
    BGRA8_SRGB,      // <- "R8G8B8A8_SRGB"   DXGI_FORMAT_B8G8R8A8_UNORM_SRGB  MTLPixelFormatBGRA8Unorm_sRGB

    // --- 10/10/10/2 packed ---
    RGB10A2_UNORM,   // <- "A2B10G10R10_UNORM_PACK32"  DXGI_FORMAT_R10G10B10A2_UNORM  MTLPixelFormatRGB10A2Unorm
    RGB10A2_UINT,    // <- "A2B10G10R10_UINT_PACK32"   DXGI_FORMAT_R10G10B10A2_UINT   MTLPixelFormatRGB10A2Uint

    // --- 16-bit ---
    R16_UINT,        // <- "R16_UINT"          DXGI_FORMAT_R16_UINT            MTLPixelFormatR16Uint
    R16_SINT,        // <- "R16_SINT"          DXGI_FORMAT_R16_SINT            MTLPixelFormatR16Sint
    R16_SFLOAT,      // <- "R16_SFLOAT"        DXGI_FORMAT_R16_FLOAT           MTLPixelFormatR16Float
    RG16_UINT,       // <- "R16G16_UINT"       DXGI_FORMAT_R16G16_UINT         MTLPixelFormatRG16Uint
    RG16_SINT,       // <- "R16G16_SINT"       DXGI_FORMAT_R16G16_SINT         MTLPixelFormatRG16Sint
    RG16_SFLOAT,     // <- "R16G16_SFLOAT"     DXGI_FORMAT_R16G16_FLOAT        MTLPixelFormatRG16Float
    RGBA16_UINT,     // <- "R16G16B16A16_UINT" DXGI_FORMAT_R16G16B16A16_UINT   MTLPixelFormatRGBA16Uint
    RGBA16_SINT,     // <- "R16G16B16A16_SINT" DXGI_FORMAT_R16G16B16A16_SINT   MTLPixelFormatRGBA16Sint
    RGBA16_SFLOAT,   // <- "R16G16B16A16_SFLOAT" DXGI_FORMAT_R16G16B16A16_FLOAT MTLPixelFormatRGBA16Float
                     //    (also the HDR swap-chain / float_framebuffer format)

    // --- 32-bit ---
    R32_UINT,        // <- "R32_UINT"          DXGI_FORMAT_R32_UINT            MTLPixelFormatR32Uint
    R32_SINT,        // <- "R32_SINT"          DXGI_FORMAT_R32_SINT            MTLPixelFormatR32Sint
    R32_SFLOAT,      // <- "R32_SFLOAT"        DXGI_FORMAT_R32_FLOAT           MTLPixelFormatR32Float
    RG32_UINT,       // <- "R32G32_UINT"       DXGI_FORMAT_R32G32_UINT         MTLPixelFormatRG32Uint
    RG32_SINT,       // <- "R32G32_SINT"       DXGI_FORMAT_R32G32_SINT         MTLPixelFormatRG32Sint
    RG32_SFLOAT,     // <- "R32G32_SFLOAT"     DXGI_FORMAT_R32G32_FLOAT        MTLPixelFormatRG32Float
    RGBA32_UINT,     // <- "R32G32B32A32_UINT" DXGI_FORMAT_R32G32B32A32_UINT   MTLPixelFormatRGBA32Uint
    RGBA32_SINT,     // <- "R32G32B32A32_SINT" DXGI_FORMAT_R32G32B32A32_SINT   MTLPixelFormatRGBA32Sint
    RGBA32_SFLOAT,   // <- "R32G32B32A32_SFLOAT" DXGI_FORMAT_R32G32B32A32_FLOAT MTLPixelFormatRGBA32Float
};

// ----------------------------------------------------------------------------
// Sampler description -- mirrors the D3D11_SAMPLER_DESC the engine builds in
// ShaderPass::Initialize (lines 62-127). The engine only ever toggles filter
// (point vs linear) and wrap (border / wrap / clamp / mirror) uniformly across
// U/V/W, so we collapse to one Filter and one Wrap. Border color is always
// transparent black in the engine, which the spike verified maps to Metal
// transparentBlack; it is not exposed here.
// ----------------------------------------------------------------------------
enum class Filter : uint32_t
{
    Nearest, // D3D11_FILTER_MIN_MAG_MIP_POINT  -> MTLSamplerMinMagFilterNearest (engine default)
    Linear,  // D3D11_FILTER_MIN_MAG_MIP_LINEAR -> MTLSamplerMinMagFilterLinear
};

enum class Wrap : uint32_t
{
    Border, // D3D11_TEXTURE_ADDRESS_BORDER -> MTLSamplerAddressModeClampToBorderColor
            //   + MTLSamplerBorderColorTransparentBlack  (engine default)
    Clamp,  // D3D11_TEXTURE_ADDRESS_CLAMP  -> MTLSamplerAddressModeClampToEdge
    Repeat, // D3D11_TEXTURE_ADDRESS_WRAP   -> MTLSamplerAddressModeRepeat
    Mirror, // D3D11_TEXTURE_ADDRESS_MIRROR -> MTLSamplerAddressModeMirrorRepeat
};

struct SamplerDesc
{
    Filter filter = Filter::Nearest; // engine default before preset overrides
    Wrap   wrap   = Wrap::Border;    // engine default before preset overrides
};

// ----------------------------------------------------------------------------
// Texture description -- the engine derives these from a captured-frame desc
// (texture->GetDesc) or m_displayTexture->GetDesc and then overrides width /
// height / format / bind usage (ShaderGlass.cpp:700-925). We model the two D3D
// bind-flag combinations the engine actually uses:
//
//   renderTarget=true  -> D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET
//                         (pass-output textures; Metal usage ShaderRead|RenderTarget)
//   renderTarget=false -> D3D11_BIND_SHADER_RESOURCE only
//                         (feedback / history textures; Metal usage ShaderRead)
//
// All engine intermediate textures are USAGE_DEFAULT, CPUAccessFlags 0,
// MiscFlags 0, single mip, single sample.
// ----------------------------------------------------------------------------
struct TextureDesc
{
    uint32_t width        = 0;
    uint32_t height       = 0;
    PixFmt   format       = PixFmt::BGRA8_UNORM;
    bool     renderTarget = false; // true => also usable as a render target
    bool     cpuReadable  = false; // true => host-readable via ReadbackTexture
                                   //         (GrabOutput / screenshot path; Metal
                                   //         storageModeShared, D3D staging copy)
};

// ----------------------------------------------------------------------------
// Blend mode for the cursor overlay pass. The engine builds exactly one blend
// state (ShaderPass::Initialize:190-202, used in RenderCursor) -- standard
// premultiply-by-source-alpha over. Everything else renders opaque (blend off).
// ----------------------------------------------------------------------------
enum class BlendMode : uint32_t
{
    Disabled,     // OMSetBlendState(NULL,...) -- opaque (default for all shader passes)
    AlphaOver,    // SrcBlend=SRC_ALPHA, DestBlend=INV_SRC_ALPHA, Op=ADD,
                  // SrcBlendAlpha=ONE, DestBlendAlpha=ZERO, OpAlpha=ADD
                  // -> Metal: sourceRGB=sourceAlpha, destRGB=oneMinusSourceAlpha, add;
                  //           sourceAlpha=one, destAlpha=zero, add (cursor pass only)
};

// ----------------------------------------------------------------------------
// Optional 3D extent / origin for the boxed CopySubresourceRegion path. When a
// CopyRegion is supplied to CopyTexture, the engine is doing the D3D11_BOX copy
// used for boxed feedback (ShaderGlass.cpp:1120-1127) and GrabOutput
// (1199-1219); when omitted it is a full-surface CopyResource (1104 / 1131 /
// 1155 / 1226). depth/back are always 1 in the engine.
// ----------------------------------------------------------------------------
struct CopyOrigin
{
    uint32_t x = 0;
    uint32_t y = 0;
};

struct CopyExtent
{
    uint32_t width  = 0;
    uint32_t height = 0;
};

// ----------------------------------------------------------------------------
// IRenderBackend -- pure virtual. One concrete subclass per platform
// (D3D11Backend on Windows, MetalBackend on macOS). Methods are grouped by the
// engine call site they serve. Each is annotated with the D3D11 verb it replaces
// and the Metal verb it maps to.
//
// Threading: all methods are called from the single render thread, in the order
// the engine issues them. The backend may defer/coalesce GPU work but must make
// resource creation observable to subsequent draws (matching the D3D11 immediate
// context's implicit ordering).
// ----------------------------------------------------------------------------
class IRenderBackend
{
public:
    virtual ~IRenderBackend() = default;

    // ========================================================================
    // Device / swap-chain lifecycle  (ShaderGlass.cpp swap-chain block 87-166)
    // ========================================================================

    // Create the device + swap-chain bound to a native surface.
    //   nativeWindow: HWND on Windows / NSView* (or CAMetalLayer*) on macOS,
    //                 passed as an opaque void* so this header stays neutral.
    //   width/height 0 => size to the surface (D3D passes Width=Height=0).
    //   hdr=true selects the float swap-chain format (RGBA16_SFLOAT, matching the
    //   m_useHDR ? R16G16B16A16_FLOAT : B8G8R8A8_UNORM choice at line 106) AND
    //   commits the backend to the scRGB-linear extended-range colorspace the
    //   engine assumes: gamma 1.0, values >1.0 allowed (D3D:
    //   DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709, applied at ShaderGlass.cpp:156/339).
    //   This is NOT HDR10/PQ. Metal: CAMetalLayer pixelFormat RGBA16Float +
    //   wantsExtendedDynamicRangeContent=YES + an extended-linear (sRGB primaries,
    //   linear transfer) colorspace -- NOT a PQ/HDR10 colorspace.
    // D3D11: D3D11CreateDevice + IDXGIFactory2::CreateSwapChainForHwnd
    //        + GetBuffer(0) + CreateRenderTargetView (the display RTV)
    // Metal: MTLCreateSystemDefaultDevice + newCommandQueue
    //        + attach CAMetalLayer to the view (pixelFormat/colorspace from hdr)
    virtual bool Initialize(void* nativeWindow, uint32_t width, uint32_t height, bool hdr) = 0;

    // Resize the swap-chain backbuffer and rebuild the display render target.
    // When Initialize was called with hdr=true the backend MUST RE-ASSERT the HDR
    // colorspace after the resize: on D3D, ResizeBuffers resets swap-chain
    // colorspace state, so the engine re-calls SetColorSpace1 (ShaderGlass.cpp:371-374);
    // a Metal backend must likewise re-apply the extended-range colorspace /
    // wantsExtendedDynamicRangeContent on the CAMetalLayer after changing
    // drawableSize, since those layer properties can be reset by the size change.
    // D3D11: IDXGISwapChain::ResizeBuffers + GetBuffer(0) + CreateRenderTargetView
    //        (ShaderGlass.cpp:362-368) [+ SetColorSpace1 re-apply when HDR]
    // Metal: set CAMetalLayer.drawableSize (the per-frame drawable is acquired in
    //        BeginFrame); no persistent backbuffer object to rebuild
    virtual void ResizeSwapChain(uint32_t width, uint32_t height) = 0;

    // Acquire the backbuffer for this frame and return it as the display target
    // handle (what the final shader pass renders into, m_displayRenderTarget).
    // The returned handle is borrowed and valid only until EndFrame/Present.
    // D3D11: (backbuffer already held from GetBuffer(0)) -- returns the cached
    //        display texture/RTV
    // Metal: [CAMetalLayer nextDrawable] -> wrap drawable.texture as the target
    virtual BackendTexture* BeginFrame() = 0;

    // Present the current frame to the surface.
    // D3D11: IDXGISwapChain1::Present1 / IDXGISwapChain::Present
    //        (ShaderGlass::PresentFrame, lines 402-417)
    // Metal: [commandBuffer presentDrawable:drawable]; [commandBuffer commit]
    virtual void Present() = 0;

    // ========================================================================
    // Resource creation / destruction
    // ========================================================================

    // Create an internal 2D texture (pass output, feedback, history,
    // preprocessed-input). Allocates the backing surface plus the views the
    // engine needs (SRV always; RTV when desc.renderTarget).
    //
    // initialData (optional): CPU pixel bytes to upload at creation, with
    // rowPitch bytes per row. Used for preset LUT/image textures decoded on the CPU
    // (Texture.cpp WIC path -> sg::DecodeImageRGBA -> CreateTexture). null/0 leaves
    // the texture uninitialized (the normal pass-output/feedback/history case).
    // desc.cpuReadable=true additionally makes the texture host-readable via
    // ReadbackTexture (the GrabOutput / screenshot path).
    // D3D11: ID3D11Device::CreateTexture2D (+ CreateShaderResourceView,
    //        + CreateRenderTargetView when renderTarget; + UpdateSubresource /
    //        D3D11_SUBRESOURCE_DATA when initialData) (ShaderGlass.cpp:709/831/...,
    //        Texture.cpp:38-49)
    // Metal: [device newTextureWithDescriptor:] (+ replaceRegion:withBytes: when
    //        initialData); storageModeShared when cpuReadable
    virtual BackendTexture* CreateTexture(const TextureDesc& desc,
                                          const void* initialData = nullptr,
                                          size_t      rowPitch     = 0) = 0;

    // Wrap an externally-owned native frame (the capture surface delivered by
    // Windows.Graphics.Capture / ScreenCaptureKit) as a read-only sampleable
    // texture, WITHOUT copying or taking ownership of the underlying surface.
    //   nativeFrame: ID3D11Texture2D* on Windows / id<MTLTexture> or
    //                CVPixelBufferRef/IOSurfaceRef on macOS, as opaque void*.
    // The engine then makes an SRV over it and feeds it to the preprocess pass
    // (ShaderGlass.cpp:1021-1024, CreateShaderResourceView over the captured
    // texture). The returned handle is owned by the caller and released with
    // DestroyTexture, but the wrapped surface itself is NOT freed.
    // D3D11: CreateShaderResourceView over the capture frame's ID3D11Texture2D
    // Metal: import the IOSurface as id<MTLTexture> via
    //        newTextureWithDescriptor:iosurface:plane: (zero-copy)
    virtual BackendTexture* WrapNativeFrame(void* nativeFrame, const TextureDesc& desc) = 0;

    // Release a texture created by CreateTexture / WrapNativeFrame / BeginFrame.
    // (BeginFrame's borrowed target is a no-op to destroy.)
    virtual void DestroyTexture(BackendTexture* texture) = 0;

    // Compile a shader pass from cross-compiled bytecode/source. The engine
    // supplies the same VertexByteCode/FragmentByteCode it feeds to
    // CreateVertexShader/CreatePixelShader.
    //   vertexCode/fragmentCode: DXBC blobs on Windows; MSL source (or precompiled
    //   metallib) on macOS. Passed as raw bytes so this header is format-neutral.
    //
    // NOTE the returned shader is render-target-FORMAT-AGNOSTIC. The color
    // attachment format is resolved per-draw from the render target bound at
    // BeginRenderPass, NOT baked here -- because the engine's intermediate passes
    // render into pass.m_shader.m_format textures (ShaderGlass.cpp:823) while the
    // FINAL pass renders into the swap-chain display target (line 901), which is
    // RGBA16_SFLOAT under HDR or BGRA8_UNORM otherwise (line 106) and can differ
    // from any single pass's format (e.g. a last pass declaring srgb_framebuffer /
    // float_framebuffer). A Metal backend lazily builds + caches one PSO variant
    // per (bound target format, blend mode); D3D11 binds the VS/PS directly and is
    // format-agnostic anyway.
    //
    // RASTERIZER INVARIANT (mirrors the single global RSSetState at
    // ShaderGlass.cpp:143-159): every pass draws the full-screen quad with NO face
    // culling, solid fill, and NO depth attachment. The backend MUST honor this --
    // on Metal: never setCullMode: (default MTLCullModeNone is required because the
    // quad winding is transform-dependent), and never attach a depth/stencil target.
    // D3D's DepthClipEnable=FALSE has a Metal analog (setDepthClipMode:) but it is a
    // no-op here: no depth buffer, quad at z=0 in [0,1]. Do not add one.
    //
    // D3D11: ID3D11Device::CreateVertexShader + CreatePixelShader
    //        + CreateInputLayout (Shader::Create / ShaderPass::Initialize:46)
    // Metal: [device newLibraryWithSource:] -> newFunctionWithName: (vs_main/fs_main)
    //        + MTLVertexDescriptor (TEXCOORD0 float4@0, TEXCOORD1 float2@16,
    //          stride 24, buffer index 30); PSO built lazily at draw (VERIFIED by
    //          the M-1 spike)
    virtual BackendShader* CreateShader(const void* vertexCode,
                                        size_t      vertexCodeSize,
                                        const void* fragmentCode,
                                        size_t      fragmentCodeSize) = 0;

    virtual void DestroyShader(BackendShader* shader) = 0;

    // Buffer creation. The engine makes three kinds:
    //   - the static vertex buffer (immutable, the 8-vertex sVertexBuffer)
    //   - the UBO constant buffer (dynamic, register b0)
    //   - the Push constant buffer (dynamic, register b1)
    // initialData may be null for the dynamic constant buffers (filled later via
    // UpdateConstantBuffer); it is non-null for the immutable vertex buffer.
    // D3D11: ID3D11Device::CreateBuffer with D3D11_BIND_VERTEX_BUFFER
    //        (USAGE_DEFAULT) for the vertex buffer
    //        (ShaderPass::Initialize:49-55)
    // Metal: [device newBufferWithBytes:length:options:MTLResourceStorageModeShared]
    virtual BackendBuffer* CreateVertexBuffer(const void* initialData, size_t size) = 0;

    // D3D11: ID3D11Device::CreateBuffer, D3D11_BIND_CONSTANT_BUFFER,
    //        USAGE_DYNAMIC, CPU_ACCESS_WRITE, size rounded up to 16
    //        (ShaderPass::Initialize:133-156, both UBO and Push)
    // Metal: [device newBufferWithLength:options:MTLResourceStorageModeShared]
    virtual BackendBuffer* CreateConstantBuffer(size_t size) = 0;

    virtual void DestroyBuffer(BackendBuffer* buffer) = 0;

    // D3D11: ID3D11Device::CreateSamplerState (ShaderPass::Initialize:127)
    // Metal: [device newSamplerStateWithDescriptor:]
    virtual BackendSampler* CreateSampler(const SamplerDesc& desc) = 0;

    virtual void DestroySampler(BackendSampler* sampler) = 0;

    // ========================================================================
    // Per-pass constant upload  (ShaderPass::Render:275-289, RenderCursor:381-387)
    //
    // The engine maps the dynamic constant buffer with WRITE_DISCARD and memcpys
    // the params blob (Shader::FillParams). The MVP rows go in verbatim -- NO
    // transpose -- which the spike proved Metal consumes correctly.
    // D3D11: Map(WRITE_DISCARD) + memcpy + Unmap
    // Metal: memcpy into the shared MTLBuffer.contents (optionally
    //        ring-buffered to avoid GPU/CPU hazards)
    // ========================================================================
    virtual void UpdateConstantBuffer(BackendBuffer* buffer, const void* data, size_t size) = 0;

    // ========================================================================
    // Render pass setup + draw  (ShaderPass::Render:291-360, RenderCursor:372-401)
    //
    // The engine's per-pass sequence, factored into the calls below:
    //   RSSetViewports          -> SetViewport
    //   OMSetRenderTargets      -> BeginRenderPass (target) / EndRenderPass
    //   OMSetBlendState         -> SetBlend
    //   IASetPrimitiveTopology  } baked into the pipeline + Draw's topology arg
    //   IASetInputLayout        } (Metal vertex descriptor lives in the PSO)
    //   IASetVertexBuffers      -> SetVertexBuffer
    //   VSSetShader/PSSetShader -> BindShader (selects the PSO)
    //   PSSetShaderResources    -> BindTexture
    //   PSSetSamplers           -> BindSampler
    //   VS/PSSetConstantBuffers -> BindConstantBuffer
    //   Draw                    -> Draw
    // ========================================================================

    // Begin rendering into a target texture. Must be created with
    // renderTarget=true (or be the display target from BeginFrame). clear=true
    // clears to clearColor first (the engine's ClearRenderTargetView for blank
    // areas / the display background, ShaderGlass.cpp:638/644/1018).
    // clearColor is RGBA in 0..1; ignored when clear=false.
    // D3D11: OMSetRenderTargets(1,&rtv,NULL) (+ ClearRenderTargetView when clear)
    // Metal: configure MTLRenderPassDescriptor.colorAttachments[0]
    //        (loadAction = clear ? Clear : Load, storeAction = Store)
    //        + renderCommandEncoderWithDescriptor:
    virtual void BeginRenderPass(BackendTexture* target, bool clear, const float clearColor[4]) = 0;

    // End the current render pass (unbinds the target; D3D unbinds RTV/SRVs so
    // the surface can be rebound as input next pass -- ShaderPass.cpp:362-369).
    // D3D11: OMSetRenderTargets(1,{nullptr},NULL) + PSSetShaderResources(...,null)
    // Metal: [encoder endEncoding]
    virtual void EndRenderPass() = 0;

    // D3D11: RSSetViewports(1,&viewport) with TopLeftX=x, TopLeftY=y
    //        (ShaderPass::Render:291, RenderCursor:377). Note the engine offsets
    //        the viewport by (boxX,boxY) for letterboxed output.
    // Metal: [encoder setViewport:(MTLViewport){x,y,width,height,0,1}]
    virtual void SetViewport(float x, float y, float width, float height) = 0;

    // Select the pipeline for the pass (both VS and PS in one PSO on Metal).
    // D3D11: VSSetShader + PSSetShader (ShaderPass::Render:302-303)
    // Metal: [encoder setRenderPipelineState:]
    virtual void BindShader(BackendShader* shader) = 0;

    // Bind the geometry stream. On Metal this goes to buffer index 30
    // (kGeometryBufferIndex) so it never aliases the b0/b1 constant buffers.
    // stride/offset match the engine's s_vertexStride / s_vertexOffset.
    // D3D11: IASetVertexBuffers(0,1,&vb,&stride,&offset) + IASetInputLayout
    //        (ShaderPass::Render:298-300)
    // Metal: [encoder setVertexBuffer:offset:atIndex:kGeometryBufferIndex]
    virtual void SetVertexBuffer(BackendBuffer* buffer, uint32_t stride, uint32_t offset) = 0;

    // Bind a sampled texture at a SPIR-V/D3D binding slot, fragment stage.
    // texture==null unbinds (the engine nulls slots to rebind as RT next pass).
    // D3D11: PSSetShaderResources(slot,1,&srv) (ShaderPass::Render:312/325)
    // Metal: [encoder setFragmentTexture:atIndex:slot]
    virtual void BindTexture(uint32_t slot, BackendTexture* texture) = 0;

    // Bind a sampler at the matching binding slot, fragment stage.
    // D3D11: PSSetSamplers(slot,1,&samplerState) (ShaderPass::Render:337)
    // Metal: [encoder setFragmentSamplerState:atIndex:slot]
    virtual void BindSampler(uint32_t slot, BackendSampler* sampler) = 0;

    // Bind a constant buffer to BOTH vertex and fragment stages at the given
    // Metal buffer index. Pass kUboBufferIndex (0) for the UBO/b0 buffer and
    // kPushBufferIndex (1) for the Push/b1 buffer.
    // D3D11: VSSetConstantBuffers(index,1,&cb) + PSSetConstantBuffers(index,1,&cb)
    //        (ShaderPass::Render:343-350)
    // Metal: [encoder setVertexBuffer:offset:atIndex:index]
    //        + [encoder setFragmentBuffer:offset:atIndex:index]
    virtual void BindConstantBuffer(uint32_t index, BackendBuffer* buffer) = 0;

    // Set the blend state for the current pass. Disabled for every shader pass;
    // AlphaOver only for the cursor overlay (RenderCursor:392, restored to
    // Disabled at 399). On Metal this is part of the PSO, so the backend keeps a
    // pair of pipeline variants per shader (opaque + alpha-over) and swaps the
    // active PSO; the engine's call site maps 1:1 to OMSetBlendState.
    // D3D11: OMSetBlendState(blendState/NULL, NULL, 0xffffffff)
    // Metal: select the PSO variant whose colorAttachments[0] blend matches mode
    virtual void SetBlend(BlendMode mode) = 0;

    // Issue the draw. The engine always draws a triangle strip; vertexCount is
    // s_vertexCount (4) and startVertex is 4 for shader passes (Draw(4,4)) or 0
    // for the preprocess pass (Draw(4,0)) -- the spike confirmed start-vertex 4.
    // D3D11: ID3D11DeviceContext::Draw(vertexCount, startVertex)
    //        (ShaderPass::Render:355/359, RenderCursor:394)
    // Metal: [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
    //                   vertexStart:startVertex vertexCount:vertexCount]
    virtual void Draw(uint32_t vertexCount, uint32_t startVertex) = 0;

    // ========================================================================
    // Resource copies  (feedback / history / GrabOutput)
    //
    // Single entry point covering both the full-surface CopyResource and the
    // boxed CopySubresourceRegion. When sourceOrigin/sourceSize/destOrigin are
    // all null it is a whole-resource copy; when provided it is the D3D11_BOX
    // copy used for letterboxed feedback and grab (back/front depth = 1).
    //
    // ORDERING CONTRACT: CopyTexture observes all prior draws into `source` and is
    // observed by subsequent draws that sample `dest`. The engine relies on this
    // for self-referential feedback/history (it copies a pass output written THIS
    // frame, then samples the copy next frame -- ShaderGlass.cpp:1093-1158). A
    // backend that defers/coalesces GPU work MUST NOT reorder a CopyTexture across
    // the draws that produce its source or consume its dest.
    // D3D11: CopyResource              (ShaderGlass.cpp:1104/1131/1155/1226)
    //        CopySubresourceRegion     (ShaderGlass.cpp:1127/1219, boxed)
    // Metal: blit encoder copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:
    //        sourceSize:toTexture:destinationSlice:destinationLevel:
    //        destinationOrigin: (full copy uses the source's full extent at origin 0)
    // ========================================================================
    virtual void CopyTexture(BackendTexture*   dest,
                             BackendTexture*   source,
                             const CopyOrigin* sourceOrigin = nullptr,
                             const CopyExtent* sourceSize   = nullptr,
                             const CopyOrigin* destOrigin    = nullptr) = 0;

    // Read a cpuReadable texture's pixels back to host memory, rowPitch bytes/row.
    // Used by GrabOutput / screenshot export, which the engine returns as a GPU
    // texture today (ShaderGlass.cpp:1176-1230) but which must be CPU-read on macOS
    // to PNG-encode. The texture must have been created with desc.cpuReadable=true.
    // D3D11: (staging texture) Map(READ) + memcpy + Unmap
    // Metal: [blit synchronizeResource:] then [tex getBytes:bytesPerRow:fromRegion:]
    //        (texture is storageModeShared)
    virtual void ReadbackTexture(BackendTexture* texture, void* dst, size_t rowPitch) = 0;
};

} // namespace sg
