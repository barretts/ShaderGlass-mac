/*
ShaderGlass macOS core engine wrapper.

This is the mac-first bridge point for the shared resource path: it owns a shared
Preset/ShaderPass pair and renders through sg::IRenderBackend. It deliberately
does not expose AppKit or Metal types.
*/

#pragma once

#include "../backend/IRenderBackend.h"
#include "../backend/sg_geometry.h"
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

class Preset;
class PresetDef;
class ShaderPass;

namespace sg {

enum class EngineEvent
{
    PresetChanged,
    FrameRendered,
};

struct EngineCallbacks
{
    std::function<void(EngineEvent)> notify;
};

class SGCoreEngine
{
public:
    SGCoreEngine();
    ~SGCoreEngine();

    bool Initialize(IRenderBackend& backend, const std::string& singlePassMSL);
    bool InitializeChain(IRenderBackend& backend,
                         const std::vector<std::string>& passMSL,
                         const std::vector<std::vector<std::pair<std::string, int>>>& extraSamplers = {});
    bool InitializeChain(IRenderBackend& backend,
                         const std::string& preprocessMSL,
                         const std::vector<std::string>& passMSL,
                         const std::vector<std::vector<std::pair<std::string, int>>>& extraSamplers = {});
    void SetCallbacks(EngineCallbacks callbacks);
    void SetGeometryProvider(IGeometryProvider* geometryProvider);
    void Shutdown();

    bool RenderSinglePass(BackendTexture* source,
                          uint32_t sourceWidth,
                          uint32_t sourceHeight,
                          BackendTexture* target,
                          uint32_t targetWidth,
                          uint32_t targetHeight,
                          uint32_t frameCount);
    bool RenderChain(BackendTexture* source,
                     uint32_t sourceWidth,
                     uint32_t sourceHeight,
                     BackendTexture* target,
                     uint32_t targetWidth,
                     uint32_t targetHeight,
                     uint32_t frameCount);
    BackendTexture* GrabOutput();
    bool ReadbackLastOutput(void* dst, size_t rowPitch);

private:
    IRenderBackend* m_backend {nullptr};
    IGeometryProvider* m_geometryProvider {nullptr};
    std::unique_ptr<IGeometryProvider> m_defaultGeometryProvider;
    std::string m_singlePassMSL;
    std::unique_ptr<PresetDef> m_preprocessPresetDef;
    std::unique_ptr<Preset> m_preprocessPreset;
    std::unique_ptr<ShaderPass> m_preprocessPass;
    BackendTexture* m_preprocessTexture {nullptr};
    std::unique_ptr<PresetDef> m_presetDef;
    std::unique_ptr<Preset> m_preset;
    std::vector<std::unique_ptr<ShaderPass>> m_passes;
    std::vector<BackendTexture*> m_intermediateTextures;
    std::vector<BackendTexture*> m_feedbackTextures;
    bool m_requiresFeedback {false};
    uint32_t m_chainWidth {0};
    uint32_t m_chainHeight {0};
    BackendTexture* m_lastOutput {nullptr};
    uint32_t m_lastOutputWidth {0};
    uint32_t m_lastOutputHeight {0};
    EngineCallbacks m_callbacks;

    void DestroyRenderState();
    void Notify(EngineEvent event);
};

} // namespace sg
