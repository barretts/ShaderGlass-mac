/*
ShaderGlass macOS port -- EngineBridge
*/

#import "EngineBridge.h"
#include "../backend/MetalBackend.h"
#include "../backend/sg_clock.h"
#include "../../ShaderGlass/CursorEmulator.h"
#include "../../ShaderGlass/ShaderGlass.h"
#include <algorithm>
#include <memory>
#include <vector>

using namespace sg;

namespace {
class MslPresetDef final : public PresetDef
{
public:
    explicit MslPresetDef(const std::string& msl) : m_ownedMSL(msl)
    {
        Name = "mac-app-msl";
        Category = "general";
        ShaderDef shader;
        shader.Name = "mac-app-pass";
        shader.VertexByteCode = reinterpret_cast<const uint8_t*>(m_ownedMSL.data());
        shader.VertexLength = m_ownedMSL.size();
        shader.FragmentByteCode = reinterpret_cast<const uint8_t*>(m_ownedMSL.data());
        shader.FragmentLength = m_ownedMSL.size();
        shader.Params.push_back(ShaderParam("MVP", UBO_BUFFER, 0, 64, 0, 0, 0));
        shader.Params.push_back(ShaderParam("SourceSize", PUSH_BUFFER, 0, 16, 0, 0, 0));
        shader.Params.push_back(ShaderParam("OriginalSize", PUSH_BUFFER, 16, 16, 0, 0, 0));
        shader.Params.push_back(ShaderParam("OutputSize", PUSH_BUFFER, 32, 16, 0, 0, 0));
        shader.Params.push_back(ShaderParam("FrameCount", PUSH_BUFFER, 48, 4, 0, 0, 0));
        shader.Samplers.push_back(ShaderSampler("Source", 2));
        ShaderDefs.push_back(shader);
    }

private:
    std::string m_ownedMSL;
};

class BridgeGeometryProvider final : public IGeometryProvider
{
public:
    void Set(uint32_t sourceWidth, uint32_t sourceHeight, uint32_t targetWidth, uint32_t targetHeight)
    {
        m_sourceWidth = sourceWidth;
        m_sourceHeight = sourceHeight;
        m_targetWidth = targetWidth;
        m_targetHeight = targetHeight;
    }

    FrameGeometry Geometry(uint32_t, uint32_t, uint32_t, uint32_t) override
    {
        const auto sw = static_cast<int32_t>(std::max<uint32_t>(1, m_sourceWidth));
        const auto sh = static_cast<int32_t>(std::max<uint32_t>(1, m_sourceHeight));
        const auto tw = static_cast<int32_t>(std::max<uint32_t>(1, m_targetWidth));
        const auto th = static_cast<int32_t>(std::max<uint32_t>(1, m_targetHeight));
        return FrameGeometry {sg::Rect {0, 0, sw, sh},
                              sg::Rect {0, 0, tw, th},
                              sg::Rect {0, 0, tw, th},
                              sg::Rect {0, 0, tw, th},
                              sg::Rect {0, 0, tw, th},
                              sg::Point {0, 0},
                              false};
    }

private:
    uint32_t m_sourceWidth {1};
    uint32_t m_sourceHeight {1};
    uint32_t m_targetWidth {1};
    uint32_t m_targetHeight {1};
};
} // namespace

@implementation EngineBridge {
    MetalBackend _backend;
    std::unique_ptr<CursorEmulator> _cursor;
    std::unique_ptr<ShaderGlass> _engine;
    std::unique_ptr<BridgeGeometryProvider> _geometryProvider;
    std::vector<std::unique_ptr<MslPresetDef>> _presetDefs;
    uint32_t _syntheticFrame;
}

- (nullable instancetype)initWithLayer:(nullable CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                          shaderSource:(const std::string&)shaderSource {
    return [self initWithLayer:layer width:width height:height preprocessSource:shaderSource shaderSource:shaderSource];
}

- (nullable instancetype)initWithLayer:(nullable CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                       preprocessSource:(const std::string&)preprocessSource
                           shaderSource:(const std::string&)shaderSource {
    self = [super init];
    if (!self) return nil;
    if (!_backend.Initialize((__bridge void*)layer, width, height, /*hdr*/false))
        return nil;
    _cursor = std::make_unique<CursorEmulator>();
    _engine = std::make_unique<ShaderGlass>(*_cursor);
    _geometryProvider = std::make_unique<BridgeGeometryProvider>();
    _geometryProvider->Set(width, height, width, height);
    _syntheticFrame = 1;
    _presetDefs.push_back(std::make_unique<MslPresetDef>(shaderSource));
    _engine->SetShaderPreset(_presetDefs.back().get(), {});
    __weak EngineBridge* weakSelf = self;
    _engine->Initialize((__bridge void*)layer,
                        nullptr,
                        nullptr,
                        false,
                        false,
                        false,
                        false,
                        false,
                        _backend,
                        _geometryProvider.get(),
                        [weakSelf]() {
                            EngineBridge* s = weakSelf;
                            if (s && s.engineEventHandler) s.engineEventHandler(SGEngineEventFrameRendered);
                        },
                        [weakSelf]() {
                            EngineBridge* s = weakSelf;
                            if (s && s.engineEventHandler) s.engineEventHandler(SGEngineEventPresetChanged);
                        });
    if (!_engine)
        return nil;
    return self;
}

- (BOOL)setShaderSource:(const std::string&)shaderSource {
    return [self setPreprocessSource:shaderSource shaderSource:shaderSource];
}

- (BOOL)setPreprocessSource:(const std::string&)preprocessSource shaderSource:(const std::string&)shaderSource {
    (void)preprocessSource;
    if (!_engine) return NO;
    _presetDefs.push_back(std::make_unique<MslPresetDef>(shaderSource));
    _engine->SetShaderPreset(_presetDefs.back().get(), {});
    return YES;
}

- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height {
    _backend.ResizeSwapChain(width, height);
}

- (nullable BackendTexture*)beginFrame {
    return _backend.BeginFrame();
}

- (void)present {
    _backend.Present();
}

- (BOOL)renderSource:(BackendTexture*)source
         sourceWidth:(uint32_t)sourceWidth
        sourceHeight:(uint32_t)sourceHeight
            toTarget:(BackendTexture*)target
         targetWidth:(uint32_t)targetWidth
        targetHeight:(uint32_t)targetHeight
          frameCount:(uint32_t)frameCount {
    (void)target;
    if (!_engine || !source || !sourceWidth || !sourceHeight || !targetWidth || !targetHeight)
        return NO;
    _geometryProvider->Set(sourceWidth, sourceHeight, targetWidth, targetHeight);
    const uint32_t inputFrame = frameCount ? frameCount : _syntheticFrame++;
    _engine->Process(source, SG_TICKS(), static_cast<int>(inputFrame));
    return YES;
}

- (nullable BackendTexture*)createTexture:(const TextureDesc&)desc
                              initialData:(nullable const void*)initialData
                                 rowPitch:(size_t)rowPitch {
    return _backend.CreateTexture(desc, initialData, rowPitch);
}

- (void)destroyTexture:(nullable BackendTexture*)texture {
    _backend.DestroyTexture(texture);
}

- (void)readbackTexture:(BackendTexture*)texture dst:(void*)dst rowPitch:(size_t)rowPitch {
    _backend.ReadbackTexture(texture, dst, rowPitch);
}

- (nullable BackendTexture*)grabOutput {
    return _engine ? _engine->GrabOutput() : nullptr;
}

- (BOOL)readbackLastOutput:(void*)dst rowPitch:(size_t)rowPitch {
    if (!_engine) return NO;
    auto* output = _engine->GrabOutput();
    if (!output) return NO;
    _backend.ReadbackTexture(output, dst, rowPitch);
    _backend.DestroyTexture(output);
    return YES;
}

- (IRenderBackend*)renderBackend {
    return &_backend;
}

- (nullable void*)nativeDevice {
    return _backend.NativeDevice();
}

- (void)shutdown {
    if (_engine) {
        _engine->Stop();
        _engine.reset();
    }
    _presetDefs.clear();
    _geometryProvider.reset();
    _cursor.reset();
}

- (void)dealloc {
    [self shutdown];
}

@end
