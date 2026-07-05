/*
ShaderGlass macOS port -- EngineBridge
*/

#import "EngineBridge.h"
#include "../backend/MetalBackend.h"
#include "../backend/sg_clock.h"
#include "../../ShaderGlass/CursorEmulator.h"
#include "../../ShaderGlass/ShaderGlass.h"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <memory>
#include <sstream>
#include <vector>

using namespace sg;

namespace {
struct PresetMetadataSpec
{
    std::string presetID;
    std::string displayName;
    std::string category;
};

static uint64_t HashStringFNV1a(const std::string& value)
{
    uint64_t hash = 1469598103934665603ull;
    for (unsigned char ch : value) {
        hash ^= ch;
        hash *= 1099511628211ull;
    }
    return hash;
}

static std::string HexString(uint64_t value)
{
    std::ostringstream stream;
    stream << std::hex << value;
    return stream.str();
}

static PresetMetadataSpec BuildFallbackPresetMetadata(const std::string& preprocessSource, const std::string& shaderSource)
{
    const std::string presetID = "inline-" + HexString(HashStringFNV1a(preprocessSource)) + "-" + HexString(HashStringFNV1a(shaderSource));
    return PresetMetadataSpec {presetID, presetID, "general"};
}

static PresetMetadataSpec BuildPresetMetadataSpec(const std::string& preprocessSource,
                                                  const std::string& shaderSource,
                                                  NSString* _Nullable presetID,
                                                  NSString* _Nullable displayName,
                                                  NSString* _Nullable category)
{
    PresetMetadataSpec metadata = BuildFallbackPresetMetadata(preprocessSource, shaderSource);
    if (presetID.length > 0)
        metadata.presetID = presetID.UTF8String;
    if (displayName.length > 0)
        metadata.displayName = displayName.UTF8String;
    if (category.length > 0)
        metadata.category = category.UTF8String;
    return metadata;
}

static NSString* ParameterIdentifier(NSInteger passIndex, const ShaderParam& param)
{
    return [NSString stringWithFormat:@"%ld:%s", (long)passIndex, param.name.c_str()];
}

class MslPresetDef final : public PresetDef
{
public:
    MslPresetDef(const std::string& msl, const PresetMetadataSpec& metadata) : m_ownedMSL(msl)
    {
        Name = metadata.presetID;
        Category = metadata.category;
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
        shader.Params.push_back(ShaderParam("SGIntensity", PUSH_BUFFER, 52, 4, 0.35f, 1.85f, 1.0f, 0.01f, "Overall output gain"));
        shader.Params.push_back(ShaderParam("SGScanlineStrength", PUSH_BUFFER, 56, 4, 0.0f, 1.5f, 0.65f, 0.01f, "Scanline emphasis"));
        shader.Params.push_back(ShaderParam("SGMaskStrength", PUSH_BUFFER, 60, 4, 0.0f, 1.5f, 0.7f, 0.01f, "Subpixel mask emphasis"));
        shader.Params.push_back(ShaderParam("SGColorBoost", PUSH_BUFFER, 64, 4, 0.0f, 1.5f, 1.0f, 0.01f, "Color saturation boost"));
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

static const float kFullscreenQuadVertices[] = {
    -1, -1, 0, 1, 0, 1,  -1, 1, 0, 1, 0, 0,  1, -1, 0, 1, 1, 1,  1, 1, 0, 1, 1, 0,
     0,  0, 0, 1, 0, 1,   0, 1, 0, 1, 0, 0,  1,  0, 0, 1, 1, 1,  1, 1, 0, 1, 1, 0,
};

struct CompareUBO
{
    float mvp[16];
};

struct ComparePush
{
    float outputSize[4];
    float compareParams[4];
};

static std::string CompareCompositeMSL()
{
    return R"(
#include <metal_stdlib>
using namespace metal;
struct UBO { float4x4 MVP; };
struct Push { float4 OutputSize; float4 CompareParams; };
struct VSIn { float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]]; };
struct VSOut { float4 position [[position]]; float2 uv; };
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& ubo [[buffer(0)]]) {
    VSOut out;
    out.position = ubo.MVP * in.position;
    out.uv = in.texcoord;
    return out;
}
fragment float4 fs_main(VSOut in [[stage_in]],
                        texture2d<float> Original [[texture(2)]],
                        texture2d<float> Processed [[texture(3)]],
                        sampler Original_sampler [[sampler(2)]],
                        sampler Processed_sampler [[sampler(3)]],
                        constant Push& push [[buffer(1)]]) {
    const float split = clamp(push.CompareParams.x, 0.0, 1.0);
    float4 color = (in.uv.x < split)
        ? Original.sample(Original_sampler, in.uv)
        : Processed.sample(Processed_sampler, in.uv);
    const float dividerWidth = max(push.OutputSize.z * 2.0, 0.0015);
    if (split > 0.0 && split < 1.0 && fabs(in.uv.x - split) <= dividerWidth)
        color.rgb = mix(color.rgb, float3(1.0), 0.35);
    return color;
}
)";
}
} // namespace

@interface SGPresetMetadata ()

- (instancetype)initWithPresetID:(NSString*)presetID
                     displayName:(NSString*)displayName
                        category:(NSString*)category
                       passCount:(NSInteger)passCount;

@end

@implementation SGPresetMetadata

- (instancetype)initWithPresetID:(NSString*)presetID
                     displayName:(NSString*)displayName
                        category:(NSString*)category
                       passCount:(NSInteger)passCount {
    self = [super init];
    if (!self) return nil;
    _presetID = [presetID copy];
    _displayName = [displayName copy];
    _category = [category copy];
    _passCount = passCount;
    return self;
}

- (id)copyWithZone:(NSZone*)zone {
    return self;
}

@end

@interface SGParameterSnapshot ()

- (instancetype)initWithIdentifier:(NSString*)identifier
                         passIndex:(NSInteger)passIndex
                              name:(NSString*)name
              parameterDescription:(NSString*)parameterDescription
                      minimumValue:(float)minimumValue
                      maximumValue:(float)maximumValue
                      defaultValue:(float)defaultValue
                      currentValue:(float)currentValue
                         stepValue:(float)stepValue;

@end

@implementation SGParameterSnapshot

- (instancetype)initWithIdentifier:(NSString*)identifier
                         passIndex:(NSInteger)passIndex
                              name:(NSString*)name
              parameterDescription:(NSString*)parameterDescription
                      minimumValue:(float)minimumValue
                      maximumValue:(float)maximumValue
                      defaultValue:(float)defaultValue
                      currentValue:(float)currentValue
                         stepValue:(float)stepValue {
    self = [super init];
    if (!self) return nil;
    _identifier = [identifier copy];
    _passIndex = passIndex;
    _name = [name copy];
    _parameterDescription = [parameterDescription copy];
    _minimumValue = minimumValue;
    _maximumValue = maximumValue;
    _defaultValue = defaultValue;
    _currentValue = currentValue;
    _stepValue = stepValue;
    return self;
}

- (id)copyWithZone:(NSZone*)zone {
    return self;
}

@end

@implementation EngineBridge {
    MetalBackend _backend;
    std::unique_ptr<CursorEmulator> _cursor;
    std::unique_ptr<ShaderGlass> _engine;
    std::unique_ptr<BridgeGeometryProvider> _geometryProvider;
    std::vector<std::unique_ptr<MslPresetDef>> _presetDefs;
    SGPresetMetadata* _activePresetMetadata;
    BackendShader* _compareShader;
    BackendBuffer* _compareVertexBuffer;
    BackendBuffer* _compareUBOBuffer;
    BackendBuffer* _comparePushBuffer;
    BackendSampler* _compareSampler;
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
    _compareShader = nullptr;
    _compareVertexBuffer = nullptr;
    _compareUBOBuffer = nullptr;
    _comparePushBuffer = nullptr;
    _compareSampler = nullptr;
    const PresetMetadataSpec metadata = BuildFallbackPresetMetadata(preprocessSource, shaderSource);
    _presetDefs.push_back(std::make_unique<MslPresetDef>(shaderSource, metadata));
    _activePresetMetadata = [[SGPresetMetadata alloc] initWithPresetID:[NSString stringWithUTF8String:metadata.presetID.c_str()]
                                                           displayName:[NSString stringWithUTF8String:metadata.displayName.c_str()]
                                                              category:[NSString stringWithUTF8String:metadata.category.c_str()]
                                                             passCount:1];
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
    std::string compareMSL = CompareCompositeMSL();
    _compareShader = _backend.CreateShader(compareMSL.data(), compareMSL.size(), compareMSL.data(), compareMSL.size());
    _compareVertexBuffer = _backend.CreateVertexBuffer(kFullscreenQuadVertices, sizeof(kFullscreenQuadVertices));
    _compareUBOBuffer = _backend.CreateConstantBuffer(sizeof(CompareUBO));
    _comparePushBuffer = _backend.CreateConstantBuffer(sizeof(ComparePush));
    _compareSampler = _backend.CreateSampler(SamplerDesc {Filter::Linear, Wrap::Clamp});
    if (!_compareShader || !_compareVertexBuffer || !_compareUBOBuffer || !_comparePushBuffer || !_compareSampler)
        return nil;
    return self;
}

- (BOOL)setShaderSource:(const std::string&)shaderSource {
    return [self setPreprocessSource:shaderSource shaderSource:shaderSource];
}

- (BOOL)setShaderSource:(const std::string&)shaderSource
               presetID:(NSString*)presetID
            displayName:(NSString*)displayName
               category:(NSString*)category {
    return [self setPreprocessSource:shaderSource
                        shaderSource:shaderSource
                            presetID:presetID
                         displayName:displayName
                            category:category];
}

- (BOOL)setPreprocessSource:(const std::string&)preprocessSource shaderSource:(const std::string&)shaderSource {
    return [self setPreprocessSource:preprocessSource
                        shaderSource:shaderSource
                            presetID:nil
                         displayName:nil
                            category:nil];
}

- (BOOL)setPreprocessSource:(const std::string&)preprocessSource
               shaderSource:(const std::string&)shaderSource
                   presetID:(NSString*)presetID
                displayName:(NSString*)displayName
                   category:(NSString*)category {
    if (!_engine) return NO;
    const PresetMetadataSpec metadata = BuildPresetMetadataSpec(preprocessSource, shaderSource, presetID, displayName, category);
    _presetDefs.push_back(std::make_unique<MslPresetDef>(shaderSource, metadata));
    _activePresetMetadata = [[SGPresetMetadata alloc] initWithPresetID:[NSString stringWithUTF8String:metadata.presetID.c_str()]
                                                           displayName:[NSString stringWithUTF8String:metadata.displayName.c_str()]
                                                              category:[NSString stringWithUTF8String:metadata.category.c_str()]
                                                             passCount:1];
    _engine->SetShaderPreset(_presetDefs.back().get(), {});
    return YES;
}

- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height {
    _backend.ResizeSwapChain(width, height);
}

- (NSArray<SGParameterSnapshot*>*)parameterSnapshots {
    if (!_engine) return @[];

    NSMutableArray<SGParameterSnapshot*>* snapshots = [NSMutableArray array];
    for (const auto& entry : _engine->Params()) {
        const NSInteger passIndex = std::get<0>(entry);
        const ShaderParam* param = std::get<1>(entry);
        if (!param) continue;
        [snapshots addObject:[[SGParameterSnapshot alloc] initWithIdentifier:ParameterIdentifier(passIndex, *param)
                                                                   passIndex:passIndex
                                                                        name:[NSString stringWithUTF8String:param->name.c_str()]
                                                        parameterDescription:[NSString stringWithUTF8String:param->description.c_str()]
                                                                minimumValue:param->minValue
                                                                maximumValue:param->maxValue
                                                                defaultValue:_engine->GetDefaultValue(std::get<1>(entry))
                                                                currentValue:param->currentValue
                                                                   stepValue:param->stepValue]];
    }
    return [snapshots copy];
}

- (nullable SGParameterSnapshot*)parameterSnapshotForIdentifier:(NSString*)identifier {
    if (identifier.length == 0) return nil;
    for (SGParameterSnapshot* snapshot in [self parameterSnapshots])
        if ([snapshot.identifier isEqualToString:identifier])
            return snapshot;
    return nil;
}

- (BOOL)updateParameterValue:(float)value forIdentifier:(NSString*)identifier {
    if (!_engine || identifier.length == 0) return NO;

    for (const auto& entry : _engine->Params()) {
        const NSInteger passIndex = std::get<0>(entry);
        ShaderParam* param = std::get<1>(entry);
        if (!param || ![ParameterIdentifier(passIndex, *param) isEqualToString:identifier])
            continue;

        const float lowerBound = std::min(param->minValue, param->maxValue);
        const float upperBound = std::max(param->minValue, param->maxValue);
        const float clampedValue = std::clamp(value, lowerBound, upperBound);
        param->currentValue = clampedValue;
        _engine->UpdateParams();
        return YES;
    }

    return NO;
}

- (BOOL)resetParameterForIdentifier:(NSString*)identifier {
    if (!_engine || identifier.length == 0) return NO;

    for (const auto& entry : _engine->Params()) {
        const NSInteger passIndex = std::get<0>(entry);
        ShaderParam* param = std::get<1>(entry);
        if (!param || ![ParameterIdentifier(passIndex, *param) isEqualToString:identifier])
            continue;

        param->currentValue = _engine->GetDefaultValue(param);
        _engine->UpdateParams();
        return YES;
    }

    return NO;
}

- (BOOL)resetAllParameters {
    if (!_engine) return NO;
    _engine->ResetParams();
    return YES;
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
    if (!_engine || !source || !sourceWidth || !sourceHeight || !targetWidth || !targetHeight)
        return NO;
    _geometryProvider->Set(sourceWidth, sourceHeight, targetWidth, targetHeight);
    const uint32_t inputFrame = frameCount ? frameCount : _syntheticFrame++;
    _engine->Process(source, SG_TICKS(), static_cast<int>(inputFrame), target);
    return YES;
}

- (BOOL)composeCompareOriginal:(BackendTexture*)original
                     processed:(BackendTexture*)processed
                      toTarget:(BackendTexture*)target
                   targetWidth:(uint32_t)targetWidth
                  targetHeight:(uint32_t)targetHeight
                 splitPosition:(float)splitPosition {
    if (!original || !processed || !target || !targetWidth || !targetHeight ||
        !_compareShader || !_compareVertexBuffer || !_compareUBOBuffer || !_comparePushBuffer || !_compareSampler)
        return NO;

    CompareUBO ubo;
    std::memset(&ubo, 0, sizeof(ubo));
    ubo.mvp[0] = 2.0f;
    ubo.mvp[5] = 2.0f;
    ubo.mvp[12] = -1.0f;
    ubo.mvp[13] = -1.0f;
    ubo.mvp[15] = 1.0f;

    ComparePush push;
    std::memset(&push, 0, sizeof(push));
    push.outputSize[0] = static_cast<float>(targetWidth);
    push.outputSize[1] = static_cast<float>(targetHeight);
    push.outputSize[2] = 1.0f / std::max<float>(1.0f, static_cast<float>(targetWidth));
    push.outputSize[3] = 1.0f / std::max<float>(1.0f, static_cast<float>(targetHeight));
    push.compareParams[0] = std::clamp(splitPosition, 0.0f, 1.0f);

    _backend.UpdateConstantBuffer(_compareUBOBuffer, &ubo, sizeof(ubo));
    _backend.UpdateConstantBuffer(_comparePushBuffer, &push, sizeof(push));

    const float clear[4] = {0, 0, 0, 1};
    _backend.BeginRenderPass(target, true, clear);
    _backend.SetViewport(0, 0, static_cast<float>(targetWidth), static_cast<float>(targetHeight));
    _backend.BindShader(_compareShader);
    _backend.SetVertexBuffer(_compareVertexBuffer, 24, 0);
    _backend.BindConstantBuffer(kUboBufferIndex, _compareUBOBuffer);
    _backend.BindConstantBuffer(kPushBufferIndex, _comparePushBuffer);
    _backend.BindTexture(2, original);
    _backend.BindTexture(3, processed);
    _backend.BindSampler(2, _compareSampler);
    _backend.BindSampler(3, _compareSampler);
    _backend.SetBlend(BlendMode::Disabled);
    _backend.Draw(4, 4);
    _backend.EndRenderPass();
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
    if (_compareSampler) {
        _backend.DestroySampler(_compareSampler);
        _compareSampler = nullptr;
    }
    if (_comparePushBuffer) {
        _backend.DestroyBuffer(_comparePushBuffer);
        _comparePushBuffer = nullptr;
    }
    if (_compareUBOBuffer) {
        _backend.DestroyBuffer(_compareUBOBuffer);
        _compareUBOBuffer = nullptr;
    }
    if (_compareVertexBuffer) {
        _backend.DestroyBuffer(_compareVertexBuffer);
        _compareVertexBuffer = nullptr;
    }
    if (_compareShader) {
        _backend.DestroyShader(_compareShader);
        _compareShader = nullptr;
    }
    _activePresetMetadata = nil;
    _presetDefs.clear();
    _geometryProvider.reset();
    _cursor.reset();
}

- (void)dealloc {
    [self shutdown];
}

@end
