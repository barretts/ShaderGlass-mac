/*
ShaderGlass macOS core engine wrapper.
*/

#include "SGCoreEngine.h"
#include "../../ShaderGlass/pch.h"
#include "../../ShaderGC/ShaderDef.h"
#include "../../ShaderGC/TextureDef.h"
#include "../../ShaderGC/PresetDef.h"
#include "../../ShaderGlass/Preset.h"
#include "../../ShaderGlass/Shader.h"
#include "../../ShaderGlass/ShaderPass.h"

namespace sg {

namespace {
struct PassPlan
{
    uint32_t sourceWidth {0};
    uint32_t sourceHeight {0};
    uint32_t targetWidth {0};
    uint32_t targetHeight {0};
    PixFmt format {PixFmt::BGRA8_UNORM};
    std::string alias;
};

static uint32_t scaledDimension(float scale, bool viewportScale, bool absoluteScale, uint32_t sourceDim, uint32_t viewportDim)
{
    float value = 0.0f;
    if(absoluteScale)
        value = scale;
    else if(viewportScale)
        value = static_cast<float>(viewportDim) * scale;
    else
        value = static_cast<float>(sourceDim) * scale;
    return std::max<uint32_t>(1u, static_cast<uint32_t>(std::lround(value)));
}

class MslPresetDef final : public PresetDef
{
public:
    MslPresetDef(const std::vector<std::string>& passMSL,
                 const std::vector<std::vector<std::pair<std::string, int>>>& extraSamplers) :
        m_ownedMSL(passMSL)
    {
        Name = "mac-core-msl-chain";
        Category = "general";

        for(size_t i = 0; i < m_ownedMSL.size(); ++i)
        {
            ShaderDef shader;
            shader.Name = "mac-core-msl-pass-" + std::to_string(i);
            shader.VertexByteCode = reinterpret_cast<const uint8_t*>(m_ownedMSL[i].data());
            shader.VertexLength = m_ownedMSL[i].size();
            shader.FragmentByteCode = reinterpret_cast<const uint8_t*>(m_ownedMSL[i].data());
            shader.FragmentLength = m_ownedMSL[i].size();
            shader.Params.push_back(ShaderParam("MVP", UBO_BUFFER, 0, 64, 0, 0, 0));
            shader.Params.push_back(ShaderParam("SourceSize", PUSH_BUFFER, 0, 16, 0, 0, 0));
            shader.Params.push_back(ShaderParam("OriginalSize", PUSH_BUFFER, 16, 16, 0, 0, 0));
            shader.Params.push_back(ShaderParam("OutputSize", PUSH_BUFFER, 32, 16, 0, 0, 0));
            shader.Params.push_back(ShaderParam("FrameCount", PUSH_BUFFER, 48, 4, 0, 0, 0));
            shader.Params.push_back(ShaderParam("SGIntensity", PUSH_BUFFER, 52, 4, 0.35f, 1.85f, 1.0f, 0.01f, "Overall output gain"));
            shader.Params.push_back(ShaderParam("SGScanlineStrength", PUSH_BUFFER, 56, 4, 0.0f, 1.5f, 0.65f, 0.01f, "Scanline emphasis"));
            shader.Params.push_back(ShaderParam("SGMaskStrength", PUSH_BUFFER, 60, 4, 0.0f, 1.5f, 0.7f, 0.01f, "Subpixel mask emphasis"));
            shader.Params.push_back(ShaderParam("SGColorBoost", PUSH_BUFFER, 64, 4, 0.0f, 1.5f, 1.0f, 0.01f, "Color saturation boost"));
            shader.Samplers.push_back(ShaderSampler("Source", 2));
            if(i < extraSamplers.size())
            {
                for(const auto& sampler : extraSamplers[i])
                    shader.Samplers.push_back(ShaderSampler(sampler.first.c_str(), sampler.second));
            }
            ShaderDefs.push_back(shader);
        }
    }

private:
    std::vector<std::string> m_ownedMSL;
};
} // namespace

SGCoreEngine::SGCoreEngine() = default;
SGCoreEngine::~SGCoreEngine() { Shutdown(); }

bool SGCoreEngine::Initialize(IRenderBackend& backend, const std::string& singlePassMSL)
{
    return InitializeChain(backend, std::vector<std::string> {singlePassMSL});
}

bool SGCoreEngine::InitializeChain(IRenderBackend& backend,
                                   const std::vector<std::string>& passMSL,
                                   const std::vector<std::vector<std::pair<std::string, int>>>& extraSamplers)
{
    return InitializeChain(backend, passMSL.empty() ? std::string() : passMSL.front(), passMSL, extraSamplers);
}

bool SGCoreEngine::InitializeChain(IRenderBackend& backend,
                                   const std::string& preprocessMSL,
                                   const std::vector<std::string>& passMSL,
                                   const std::vector<std::vector<std::pair<std::string, int>>>& extraSamplers)
{
    Shutdown();
    if(preprocessMSL.empty() || passMSL.empty())
        return false;
    for(const auto& msl : passMSL)
        if(msl.empty())
            return false;

    m_backend = &backend;
    m_defaultGeometryProvider = std::make_unique<FullFrameGeometryProvider>();
    m_geometryProvider = m_defaultGeometryProvider.get();
    m_preprocessPresetDef = std::make_unique<MslPresetDef>(std::vector<std::string> {preprocessMSL},
                                                           std::vector<std::vector<std::pair<std::string, int>>> {});
    m_preprocessPreset = std::make_unique<Preset>(*m_preprocessPresetDef);
    m_preprocessPreset->Create(backend);
    if(m_preprocessPreset->m_shaders.empty())
        return false;
    m_preprocessPass = std::make_unique<ShaderPass>(m_preprocessPreset->m_shaders[0], *m_preprocessPreset, backend);

    m_presetDef = std::make_unique<MslPresetDef>(passMSL, extraSamplers);
    m_preset = std::make_unique<Preset>(*m_presetDef);
    m_preset->Create(backend);
    if(m_preset->m_shaders.empty())
        return false;

    for(auto& shader : m_preset->m_shaders)
    {
        m_passes.push_back(std::make_unique<ShaderPass>(shader, *m_preset, backend));
        m_requiresFeedback |= m_passes.back()->RequiresFeedback();
    }
    Notify(EngineEvent::PresetChanged);
    return true;
}

void SGCoreEngine::SetCallbacks(EngineCallbacks callbacks)
{
    m_callbacks = std::move(callbacks);
}

void SGCoreEngine::SetGeometryProvider(IGeometryProvider* geometryProvider)
{
    m_geometryProvider = geometryProvider ? geometryProvider : m_defaultGeometryProvider.get();
}

void SGCoreEngine::Shutdown()
{
    DestroyRenderState();
    m_preprocessPass.reset();
    m_preprocessPreset.reset();
    m_preprocessPresetDef.reset();
    m_passes.clear();
    m_preset.reset();
    m_presetDef.reset();
    m_singlePassMSL.clear();
    m_requiresFeedback = false;
    m_backend = nullptr;
    m_geometryProvider = nullptr;
    m_defaultGeometryProvider.reset();
}

void SGCoreEngine::DestroyRenderState()
{
    if(m_backend)
    {
        for(auto* texture : m_intermediateTextures)
            m_backend->DestroyTexture(texture);
        for(auto* texture : m_feedbackTextures)
            m_backend->DestroyTexture(texture);
        if(m_preprocessTexture)
            m_backend->DestroyTexture(m_preprocessTexture);
    }
    m_intermediateTextures.clear();
    m_feedbackTextures.clear();
    m_preprocessTexture = nullptr;
    m_chainWidth = 0;
    m_chainHeight = 0;
    m_lastOutput = nullptr;
    m_lastOutputWidth = 0;
    m_lastOutputHeight = 0;
}

bool SGCoreEngine::RenderSinglePass(BackendTexture* source,
                                    uint32_t sourceWidth,
                                    uint32_t sourceHeight,
                                    BackendTexture* target,
                                    uint32_t targetWidth,
                                    uint32_t targetHeight,
                                    uint32_t frameCount)
{
    return RenderChain(source, sourceWidth, sourceHeight, target, targetWidth, targetHeight, frameCount);
}

bool SGCoreEngine::RenderChain(BackendTexture* source,
                               uint32_t sourceWidth,
                               uint32_t sourceHeight,
                               BackendTexture* target,
                               uint32_t targetWidth,
                               uint32_t targetHeight,
                               uint32_t frameCount)
{
    if(!m_backend || m_passes.empty() || !source || !target || !sourceWidth || !sourceHeight || !targetWidth || !targetHeight)
        return false;

    std::vector<PassPlan> passPlans;
    passPlans.reserve(m_passes.size());
    uint32_t currentSourceWidth = sourceWidth;
    uint32_t currentSourceHeight = sourceHeight;
    for(const auto& pass : m_passes)
    {
        const auto& shader = pass->m_shader;
        PassPlan plan;
        plan.sourceWidth = currentSourceWidth;
        plan.sourceHeight = currentSourceHeight;
        plan.targetWidth = scaledDimension(shader.m_scaleX, shader.m_scaleViewportX, shader.m_scaleAbsoluteX, sourceWidth, targetWidth);
        plan.targetHeight = scaledDimension(shader.m_scaleY, shader.m_scaleViewportY, shader.m_scaleAbsoluteY, sourceHeight, targetHeight);
        plan.format = shader.m_format;
        plan.alias = shader.m_alias;
        passPlans.push_back(plan);
        currentSourceWidth = plan.targetWidth;
        currentSourceHeight = plan.targetHeight;
    }

    const bool sizeChanged = m_chainWidth != targetWidth || m_chainHeight != targetHeight || m_sourceWidth != sourceWidth || m_sourceHeight != sourceHeight;
    if(sizeChanged)
    {
        DestroyRenderState();
        m_sourceWidth = sourceWidth;
        m_sourceHeight = sourceHeight;
        m_chainWidth = targetWidth;
        m_chainHeight = targetHeight;
        m_preprocessTexture = m_backend->CreateTexture(TextureDesc {sourceWidth, sourceHeight, m_preprocessPass->m_shader.m_format, true, false});
        if(!m_preprocessTexture)
            return false;
        for(size_t i = 0; i + 1 < passPlans.size(); ++i)
        {
            auto* texture = m_backend->CreateTexture(TextureDesc {passPlans[i].targetWidth, passPlans[i].targetHeight, passPlans[i].format, true, false});
            if(!texture)
                return false;
            m_intermediateTextures.push_back(texture);
        }
        if(m_requiresFeedback)
        {
            for(const auto& plan : passPlans)
            {
                auto* texture = m_backend->CreateTexture(TextureDesc {plan.targetWidth, plan.targetHeight, plan.format, true, false});
                if(!texture)
                    return false;
                float clear[4] = {0, 0, 0, 1};
                m_backend->BeginRenderPass(texture, true, clear);
                m_backend->EndRenderPass();
                m_feedbackTextures.push_back(texture);
            }
        }
    }

    std::map<std::string, float4> textureSizes;
    auto geometry = m_geometryProvider ? m_geometryProvider->Geometry(sourceWidth, sourceHeight, targetWidth, targetHeight)
                                       : FrameGeometry {Rect {0, 0, static_cast<int32_t>(sourceWidth), static_cast<int32_t>(sourceHeight)},
                                                        Rect {0, 0, static_cast<int32_t>(targetWidth), static_cast<int32_t>(targetHeight)}};
    const uint32_t originalWidth = sourceWidth;
    const uint32_t originalHeight = sourceHeight;

    textureSizes.insert(std::make_pair("Original", float4 {(float)originalWidth, (float)originalHeight, 1.0f / originalWidth, 1.0f / originalHeight}));
    textureSizes.insert(std::make_pair("FinalViewport", float4 {(float)targetWidth, (float)targetHeight, 1.0f / targetWidth, 1.0f / targetHeight}));

    std::vector<std::array<uint32_t, 4>> passSizes;
    for(const auto& plan : passPlans)
    {
        passSizes.push_back({plan.sourceWidth, plan.sourceHeight, plan.targetWidth, plan.targetHeight});
    }

    std::map<std::string, BackendTexture*> resources;
    m_preprocessPass->m_sourceView = source;
    m_preprocessPass->m_targetView = m_preprocessTexture;
    std::vector<std::array<uint32_t, 4>> preprocessSizes;
    m_preprocessPass->Resize((int)sourceWidth, (int)sourceHeight, (int)targetWidth, (int)targetHeight, textureSizes, preprocessSizes);
    float clear[4] = {0, 0, 0, 1};
    m_backend->BeginRenderPass(m_preprocessTexture, true, clear);
    m_backend->EndRenderPass();
    m_preprocessPass->Render(source, resources, (int)frameCount, geometry.outputRect.left, geometry.outputRect.top);

    resources.insert(std::make_pair("Original", m_preprocessTexture));
    for(size_t i = 0; i < m_feedbackTextures.size(); ++i)
        resources.insert(std::make_pair("PassFeedback" + std::to_string(i), m_feedbackTextures[i]));

    for(size_t i = 0; i < m_passes.size(); ++i)
    {
        auto& pass = *m_passes[i];
        BackendTexture* passSource = i == 0 ? m_preprocessTexture : m_intermediateTextures[i - 1];
        BackendTexture* passTarget = (i + 1 == m_passes.size()) ? target : m_intermediateTextures[i];
        pass.m_sourceView = passSource;
        pass.m_targetView = passTarget;
        pass.Resize((int)passPlans[i].sourceWidth, (int)passPlans[i].sourceHeight, (int)passPlans[i].targetWidth, (int)passPlans[i].targetHeight, textureSizes, passSizes);
        pass.Render(resources, (int)frameCount, 0, 0);
        resources["PassOutput" + std::to_string(i)] = passTarget;
        if(!passPlans[i].alias.empty())
            resources[passPlans[i].alias] = passTarget;
    }

    if(m_requiresFeedback)
    {
        for(size_t i = 0; i < m_feedbackTextures.size(); ++i)
        {
            BackendTexture* sourceTexture = (i + 1 == m_passes.size()) ? target : m_intermediateTextures[i];
            m_backend->CopyTexture(m_feedbackTextures[i], sourceTexture, nullptr, nullptr, nullptr);
        }
    }
    m_lastOutput = target;
    m_lastOutputWidth = targetWidth;
    m_lastOutputHeight = targetHeight;
    Notify(EngineEvent::FrameRendered);
    return true;
}

BackendTexture* SGCoreEngine::GrabOutput()
{
    if(!m_backend || !m_lastOutput || !m_lastOutputWidth || !m_lastOutputHeight)
        return nullptr;
    auto* output = m_backend->CreateTexture(TextureDesc {m_lastOutputWidth, m_lastOutputHeight, PixFmt::BGRA8_UNORM, true, true});
    if(!output)
        return nullptr;
    m_backend->CopyTexture(output, m_lastOutput, nullptr, nullptr, nullptr);
    return output;
}

bool SGCoreEngine::ReadbackLastOutput(void* dst, size_t rowPitch)
{
    auto* output = GrabOutput();
    if(!output)
        return false;
    m_backend->ReadbackTexture(output, dst, rowPitch);
    m_backend->DestroyTexture(output);
    return true;
}

void SGCoreEngine::Notify(EngineEvent event)
{
    if(m_callbacks.notify)
        m_callbacks.notify(event);
}

} // namespace sg
