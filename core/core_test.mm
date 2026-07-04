/*
ShaderGlass macOS core test -- exercises shared Shader/ShaderPass/Preset resources
through sg::IRenderBackend without the thin LivePipeline draw path.
*/

#include "../../ShaderGlass/pch.h"
#include "../../ShaderGC/ShaderDef.h"
#include "../../ShaderGC/TextureDef.h"
#include "../../ShaderGC/PresetDef.h"
#include "../../ShaderGlass/Shader.h"
#include "../../ShaderGlass/Preset.h"
#include "../../ShaderGlass/ShaderPass.h"
#include "../../ShaderGlass/CursorEmulator.h"
#include "../../ShaderGlass/ShaderGlass.h"
#include "SGCoreEngine.h"
#include "../backend/MetalBackend.h"
#include "../backend/sg_image.h"

#include <cstdio>

using namespace sg;

static std::string readText(const char* path) {
    std::ifstream f(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
}

static bool sameBytes(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
    return a.size() == b.size() && std::equal(a.begin(), a.end(), b.begin());
}

static std::string feedbackMSL() {
    return R"(
#include <metal_stdlib>
using namespace metal;
struct UBO { float4x4 MVP; };
struct Push { float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; };
struct VSIn { float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]]; };
struct VSOut { float4 position [[position]]; float2 vTexCoord; };
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& ubo [[buffer(0)]], constant Push& push [[buffer(1)]]) {
    VSOut out; out.position = ubo.MVP * in.position; out.vTexCoord = in.texcoord; return out;
}
fragment float4 fs_main(VSOut in [[stage_in]],
                        texture2d<float> Source [[texture(2)]],
                        texture2d<float> PassFeedback0 [[texture(3)]],
                        sampler Source_sampler [[sampler(2)]],
                        sampler Feedback_sampler [[sampler(3)]]) {
    float4 cur = Source.sample(Source_sampler, in.vTexCoord);
    float4 prev = PassFeedback0.sample(Feedback_sampler, in.vTexCoord);
    return float4((cur.rgb * 0.5) + (prev.rgb * 0.5), 1.0);
}
)";
}

class TestMslPresetDef final : public PresetDef
{
public:
    explicit TestMslPresetDef(const std::string& msl) : m_ownedMSL(msl)
    {
        Name = "core-test-msl";
        Category = "general";
        ShaderDef shader;
        shader.Name = "core-test-pass";
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

class TestGeometryProvider final : public IGeometryProvider
{
public:
    TestGeometryProvider(uint32_t w, uint32_t h) : width(w), height(h) { }

    FrameGeometry Geometry(uint32_t, uint32_t, uint32_t, uint32_t) override
    {
        const auto rw = static_cast<int32_t>(width);
        const auto rh = static_cast<int32_t>(height);
        return FrameGeometry {sg::Rect {0, 0, rw, rh}, sg::Rect {0, 0, rw, rh}, sg::Rect {0, 0, rw, rh}, sg::Rect {0, 0, rw, rh}, sg::Rect {0, 0, rw, rh}, sg::Point {0, 0}, false};
    }

private:
    uint32_t width;
    uint32_t height;
};

static long maxChannelDiff(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
    long maxd = 0;
    for (size_t i = 0; i < a.size(); ++i)
        maxd = std::max(maxd, labs((long)a[i] - (long)b[i]));
    return maxd;
}

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: core_test passthrough.metal input.png output.png\n");
        return 2;
    }

    MetalBackend backend;
    if (!backend.Initialize(nullptr, 0, 0, false)) {
        fprintf(stderr, "core_test: backend init failed\n");
        return 1;
    }

    std::string msl = readText(argv[1]);
    if (msl.empty()) {
        fprintf(stderr, "core_test: cannot read shader %s\n", argv[1]);
        return 1;
    }

    uint32_t w = 0, h = 0;
    std::vector<uint8_t> input;
    if (!DecodeImageFileBGRA(argv[2], w, h, input)) {
        fprintf(stderr, "core_test: cannot decode input %s\n", argv[2]);
        return 1;
    }

    BackendTexture* src = backend.CreateTexture(TextureDesc{w, h, PixFmt::BGRA8_UNORM, false, false}, input.data(), (size_t)w * 4);
    BackendTexture* dst = backend.CreateTexture(TextureDesc{w, h, PixFmt::BGRA8_UNORM, true, true});
    if (!src || !dst) {
        fprintf(stderr, "core_test: texture creation failed\n");
        return 1;
    }

    SGCoreEngine engine;
    int presetChanged = 0;
    int frameRendered = 0;
    engine.SetCallbacks(EngineCallbacks{[&](EngineEvent event) {
        if (event == EngineEvent::PresetChanged) presetChanged++;
        if (event == EngineEvent::FrameRendered) frameRendered++;
    }});
    if (!engine.Initialize(backend, msl)) {
        fprintf(stderr, "core_test: engine init failed\n");
        return 1;
    }
    if (presetChanged != 1 || frameRendered != 0) {
        fprintf(stderr, "core_test: unexpected callback counts after init (preset=%d frame=%d)\n", presetChanged, frameRendered);
        return 1;
    }
    if (!engine.RenderSinglePass(src, w, h, dst, w, h, 0)) {
        fprintf(stderr, "core_test: engine render failed\n");
        return 1;
    }
    if (presetChanged != 1 || frameRendered != 1) {
        fprintf(stderr, "core_test: unexpected callback counts after render (preset=%d frame=%d)\n", presetChanged, frameRendered);
        return 1;
    }

    std::vector<uint8_t> output((size_t)w * h * 4);
    backend.ReadbackTexture(dst, output.data(), (size_t)w * 4);
    std::vector<uint8_t> grabbed((size_t)w * h * 4);
    if(!engine.ReadbackLastOutput(grabbed.data(), (size_t)w * 4)) {
        fprintf(stderr, "core_test: readback last output failed\n");
        return 1;
    }
    if (!EncodePNGFromBGRA(argv[3], output.data(), w, h, (size_t)w * 4)) {
        fprintf(stderr, "core_test: failed to write %s\n", argv[3]);
        return 1;
    }

    if (!sameBytes(input, output)) {
        fprintf(stderr, "core_test: passthrough output differs from input\n");
        return 1;
    }
    if (!sameBytes(output, grabbed)) {
        fprintf(stderr, "core_test: grabbed output differs from direct readback\n");
        return 1;
    }

    {
        MetalBackend layerBackend;
        if (!layerBackend.Initialize(nullptr, 0, 0, false)) {
            fprintf(stderr, "core_test: ShaderGlass backend init failed\n");
            return 1;
        }
        BackendTexture* sgSrc = layerBackend.CreateTexture(TextureDesc{w, h, PixFmt::BGRA8_UNORM, false, false}, input.data(), (size_t)w * 4);
        CursorEmulator cursor;
        ShaderGlass shaderGlass(cursor);
        TestMslPresetDef preset(msl);
        TestGeometryProvider geometry(w, h);
        int repaintCount = 0;
        int paramsCount = 0;
        shaderGlass.SetShaderPreset(&preset, {});
        shaderGlass.Initialize(nullptr, nullptr, nullptr, false, true, false, false, false, layerBackend, &geometry, [&]() { repaintCount++; }, [&]() { paramsCount++; });
        shaderGlass.Process(sgSrc, SG_TICKS(), 1);
        BackendTexture* sgOut = shaderGlass.GrabOutput();
        if (!sgOut) {
            fprintf(stderr, "core_test: ShaderGlass GrabOutput failed\n");
            return 1;
        }
        std::vector<uint8_t> sgPixels((size_t)w * h * 4);
        layerBackend.ReadbackTexture(sgOut, sgPixels.data(), (size_t)w * 4);
        layerBackend.DestroyTexture(sgOut);
        layerBackend.DestroyTexture(sgSrc);
        shaderGlass.Stop();
        if (!sameBytes(input, sgPixels)) {
            fprintf(stderr, "core_test: ShaderGlass passthrough output differs from input (max=%ld)\n", maxChannelDiff(input, sgPixels));
            return 1;
        }
        if (repaintCount != 1 || paramsCount != 0) {
            fprintf(stderr, "core_test: ShaderGlass callbacks unexpected (repaint=%d params=%d)\n", repaintCount, paramsCount);
            return 1;
        }
    }

    BackendTexture* multi = backend.CreateTexture(TextureDesc{w, h, PixFmt::BGRA8_UNORM, true, true});
    SGCoreEngine multiEngine;
    if (!multiEngine.InitializeChain(backend, msl, std::vector<std::string>{msl, msl})) {
        fprintf(stderr, "core_test: multi-pass engine init failed\n");
        return 1;
    }
    if (!multiEngine.RenderChain(src, w, h, multi, w, h, 7)) {
        fprintf(stderr, "core_test: multi-pass render failed\n");
        return 1;
    }
    std::vector<uint8_t> multiOut((size_t)w * h * 4);
    backend.ReadbackTexture(multi, multiOut.data(), (size_t)w * 4);
    if (!sameBytes(input, multiOut)) {
        fprintf(stderr, "core_test: multi-pass output differs from input (max=%ld)\n", maxChannelDiff(input, multiOut));
        return 1;
    }

    const uint32_t fw = 16, fh = 16;
    std::vector<uint8_t> white((size_t)fw * fh * 4, 255);
    for (size_t i = 0; i < white.size(); i += 4) white[i + 3] = 255;
    BackendTexture* feedbackSrc = backend.CreateTexture(TextureDesc{fw, fh, PixFmt::BGRA8_UNORM, false, false}, white.data(), fw * 4);
    BackendTexture* feedbackDst = backend.CreateTexture(TextureDesc{fw, fh, PixFmt::BGRA8_UNORM, true, true});
    SGCoreEngine feedbackEngine;
    if (!feedbackEngine.InitializeChain(backend, msl, std::vector<std::string>{feedbackMSL()}, {{{"PassFeedback0", 3}}})) {
        fprintf(stderr, "core_test: feedback engine init failed\n");
        return 1;
    }
    if (!feedbackEngine.RenderChain(feedbackSrc, fw, fh, feedbackDst, fw, fh, 1)) {
        fprintf(stderr, "core_test: feedback frame 1 failed\n");
        return 1;
    }
    std::vector<uint8_t> frame1((size_t)fw * fh * 4);
    backend.ReadbackTexture(feedbackDst, frame1.data(), fw * 4);
    if (!feedbackEngine.RenderChain(feedbackSrc, fw, fh, feedbackDst, fw, fh, 2)) {
        fprintf(stderr, "core_test: feedback frame 2 failed\n");
        return 1;
    }
    std::vector<uint8_t> frame2((size_t)fw * fh * 4);
    backend.ReadbackTexture(feedbackDst, frame2.data(), fw * 4);
    if (sameBytes(frame1, frame2)) {
        fprintf(stderr, "core_test: feedback frame 2 did not depend on frame 1\n");
        return 1;
    }
    if (frame2[0] <= frame1[0]) {
        fprintf(stderr, "core_test: feedback did not accumulate (frame1=%u frame2=%u)\n", frame1[0], frame2[0]);
        return 1;
    }

    backend.DestroyTexture(multi);
    backend.DestroyTexture(feedbackSrc);
    backend.DestroyTexture(feedbackDst);
    backend.DestroyTexture(src);
    backend.DestroyTexture(dst);
    engine.Shutdown();
    multiEngine.Shutdown();
    feedbackEngine.Shutdown();

    printf("core_test: passthrough byte-identical, callbacks fire, ShaderGlass renders, multi-pass stable, feedback accumulates (%ux%u)\n", w, h);
    return 0;
}
