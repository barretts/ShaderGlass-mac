/*
ShaderGlass macOS port -- MetalBackend.h

Concrete Metal implementation of IRenderBackend. Objective-C++ (.mm).

This is deliberately usable HEADLESS (offscreen render-to-texture, no CAMetalLayer)
so the abstraction can be validated without a window. InitializeHeadless() brings up
just device + command queue; the windowed Initialize()/BeginFrame()/Present() path
(CAMetalLayer drawable) drives the live app path.

Every render pass is committed and waited at EndRenderPass so offscreen output is
immediately readable via ReadbackTexture -- correctness over batching for now; the
interface permits a backend to coalesce later.
*/

#pragma once

#include "IRenderBackend.h"
#include <vector>
#include <cstdint>

namespace sg {

class MetalBackend : public IRenderBackend
{
public:
    MetalBackend();
    ~MetalBackend() override;

    // Headless bring-up (device + queue only). Returns false if no Metal device.
    bool InitializeHeadless();

    // The backing id<MTLDevice> as an opaque void* (kept off the neutral interface).
    // Lets SCKCapture's CVMetalTextureCache share this device instead of creating a
    // second one. __bridge-cast back to id<MTLDevice> at the call site.
    void* NativeDevice();

    // Test/utility: copy BGRA8 bytes to/from a texture's host-visible storage. Not
    // part of the engine-facing interface; used by the abstraction conformance test.
    // (The engine never uploads CPU pixels except via WIC/capture, which use
    // WrapNativeFrame / a future image loader.)
    std::vector<uint8_t> ReadbackBGRA(BackendTexture* texture, uint32_t w, uint32_t h);
    void                 UploadBGRA(BackendTexture* texture, const uint8_t* bytes, uint32_t w, uint32_t h);

    // ---- IRenderBackend ----
    bool            Initialize(void* nativeWindow, uint32_t width, uint32_t height, bool hdr) override;
    void            ResizeSwapChain(uint32_t width, uint32_t height) override;
    BackendTexture* BeginFrame() override;
    void            Present() override;

    BackendTexture* CreateTexture(const TextureDesc& desc,
                                  const void* initialData = nullptr, size_t rowPitch = 0) override;
    BackendTexture* WrapNativeFrame(void* nativeFrame, const TextureDesc& desc) override;
    void            DestroyTexture(BackendTexture* texture) override;
    void            ReadbackTexture(BackendTexture* texture, void* dst, size_t rowPitch) override;

    BackendShader*  CreateShader(const void* vertexCode, size_t vertexCodeSize,
                                 const void* fragmentCode, size_t fragmentCodeSize) override;
    void            DestroyShader(BackendShader* shader) override;

    BackendBuffer*  CreateVertexBuffer(const void* initialData, size_t size) override;
    BackendBuffer*  CreateConstantBuffer(size_t size) override;
    void            DestroyBuffer(BackendBuffer* buffer) override;

    BackendSampler* CreateSampler(const SamplerDesc& desc) override;
    void            DestroySampler(BackendSampler* sampler) override;

    void UpdateConstantBuffer(BackendBuffer* buffer, const void* data, size_t size) override;

    void BeginRenderPass(BackendTexture* target, bool clear, const float clearColor[4]) override;
    void EndRenderPass() override;
    void SetViewport(float x, float y, float width, float height) override;
    void BindShader(BackendShader* shader) override;
    void SetVertexBuffer(BackendBuffer* buffer, uint32_t stride, uint32_t offset) override;
    void BindTexture(uint32_t slot, BackendTexture* texture) override;
    void BindSampler(uint32_t slot, BackendSampler* sampler) override;
    void BindConstantBuffer(uint32_t index, BackendBuffer* buffer) override;
    void SetBlend(BlendMode mode) override;
    void Draw(uint32_t vertexCount, uint32_t startVertex) override;

    void CopyTexture(BackendTexture* dest, BackendTexture* source,
                     const CopyOrigin* sourceOrigin, const CopyExtent* sourceSize,
                     const CopyOrigin* destOrigin) override;

private:
    // Build + cache the pipeline state for a shader at a given Metal pixel format
    // and blend mode. Returns id<MTLRenderPipelineState> (opaque void* to keep this
    // header free of Metal types). Defined in the .mm.
    void* psoFor(void* shaderHandle, uint32_t mtlPixelFormat, BlendMode blend);

    struct Impl;
    Impl* p; // opaque ObjC++ state (id<MTL...> members live here)
};

} // namespace sg
