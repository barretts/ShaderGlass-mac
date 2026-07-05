/*
ShaderGlass macOS port -- visible demo.

Decodes a real PNG, runs it through the VERIFIED MetalBackend pipeline (the same
IRenderBackend path the engine will use), and writes the result to a PNG you can
open. Proves the Metal renderer produces correct, viewable output end-to-end --
the visible counterpart to the headless pixel-diff tests.

  usage: demo <input.png> <shader.metal> <output.png> [outW outH]

If outW/outH are omitted, output matches the input size (passthrough) or a chosen
size for shader effects. Shaders use the passthrough constant layout (UBO{MVP}@0,
Push@1, Source@2).
*/

#import <Metal/Metal.h>
#include "../backend/MetalBackend.h"
#include "../backend/sg_image.h"
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>
#include <fstream>
#include <sstream>

using namespace sg;

static const float sVertexBuffer[] = {
    -1,-1,0,1, 0,1,  -1,1,0,1, 0,0,  1,-1,0,1, 1,1,  1,1,0,1, 1,0,
     0, 0,0,1, 0,1,   0,1,0,1, 0,0,  1, 0,0,1, 1,1,  1,1,0,1, 1,0
};
struct UBO  { float MVP[16]; };
struct Push {
    float SourceSize[4];
    float OriginalSize[4];
    float OutputSize[4];
    uint32_t FrameCount;
    float SGIntensity;
    float SGScanlineStrength;
    float SGMaskStrength;
    float SGColorBoost;
};

static std::string readFile(const char* p){ std::ifstream f(p); if(!f){fprintf(stderr,"FAIL read %s\n",p);exit(2);} std::stringstream s; s<<f.rdbuf(); return s.str(); }

int main(int argc, char** argv) {
    if (argc < 4) { fprintf(stderr, "usage: demo <in.png> <shader.metal> <out.png> [outW outH]\n"); return 2; }
    const char* inPath = argv[1]; const char* shaderPath = argv[2]; const char* outPath = argv[3];

    // decode input PNG -> BGRA
    uint32_t iw=0, ih=0; std::vector<uint8_t> inPixels;
    if (!DecodeImageFileBGRA(inPath, iw, ih, inPixels)) return 2;
    uint32_t ow = (argc >= 6) ? (uint32_t)atoi(argv[4]) : iw;
    uint32_t oh = (argc >= 6) ? (uint32_t)atoi(argv[5]) : ih;
    fprintf(stderr, "input %ux%u -> output %ux%u via %s\n", iw, ih, ow, oh, shaderPath);

    MetalBackend be;
    if (!be.InitializeHeadless()) { fprintf(stderr, "FAIL: no Metal device\n"); return 2; }

    // input texture from decoded pixels (G1 initialData upload path)
    BackendTexture* inTex = be.CreateTexture(TextureDesc{iw, ih, PixFmt::BGRA8_UNORM, false, false},
                                             inPixels.data(), iw*4);
    // cpuReadable output target (G3 readback path)
    BackendTexture* outTex = be.CreateTexture(TextureDesc{ow, oh, PixFmt::BGRA8_UNORM, true, true});

    std::string msl = readFile(shaderPath);
    BackendShader* shader = be.CreateShader(msl.data(), msl.size(), msl.data(), msl.size());
    if (!shader) { fprintf(stderr, "FAIL: shader compile\n"); return 1; }
    // linear filter so upscaled CRT output is smooth
    BackendSampler* sampler = be.CreateSampler(SamplerDesc{Filter::Linear, Wrap::Border});
    BackendBuffer* vtx = be.CreateVertexBuffer(sVertexBuffer, sizeof(sVertexBuffer));
    BackendBuffer* ubo = be.CreateConstantBuffer(sizeof(UBO));
    BackendBuffer* push = be.CreateConstantBuffer(sizeof(Push));

    UBO u; memset(u.MVP,0,sizeof(u.MVP)); u.MVP[0]=2;u.MVP[5]=2;u.MVP[12]=-1;u.MVP[13]=-1;u.MVP[15]=1;
    Push pu; memset(&pu,0,sizeof(pu));
    pu.SourceSize[0]=iw; pu.SourceSize[1]=ih; pu.SourceSize[2]=1.0f/iw; pu.SourceSize[3]=1.0f/ih;
    pu.OriginalSize[0]=iw; pu.OriginalSize[1]=ih; pu.OriginalSize[2]=1.0f/iw; pu.OriginalSize[3]=1.0f/ih;
    pu.OutputSize[0]=ow; pu.OutputSize[1]=oh; pu.OutputSize[2]=1.0f/ow; pu.OutputSize[3]=1.0f/oh;
    pu.FrameCount = 0;
    pu.SGIntensity = 1.0f;
    pu.SGScanlineStrength = 0.65f;
    pu.SGMaskStrength = 0.70f;
    pu.SGColorBoost = 1.0f;
    be.UpdateConstantBuffer(ubo, &u, sizeof(u));
    be.UpdateConstantBuffer(push, &pu, sizeof(pu));

    float clear[4] = {0,0,0,1};
    be.BeginRenderPass(outTex, true, clear);
    be.SetViewport(0,0,(float)ow,(float)oh);
    be.BindShader(shader);
    be.SetVertexBuffer(vtx, 24, 0);
    be.BindConstantBuffer(kUboBufferIndex, ubo);
    be.BindConstantBuffer(kPushBufferIndex, push);
    be.BindTexture(2, inTex);
    be.BindSampler(2, sampler);
    be.SetBlend(BlendMode::Disabled);
    be.Draw(4, 4);
    be.EndRenderPass();

    // read back and save
    std::vector<uint8_t> outPixels((size_t)ow*oh*4);
    be.ReadbackTexture(outTex, outPixels.data(), ow*4);
    if (!EncodePNGFromBGRA(outPath, outPixels.data(), ow, oh, ow*4)) { fprintf(stderr,"FAIL: PNG encode\n"); return 1; }
    fprintf(stderr, "wrote %s\n", outPath);

    be.DestroyTexture(inTex); be.DestroyTexture(outTex);
    be.DestroyBuffer(vtx); be.DestroyBuffer(ubo); be.DestroyBuffer(push);
    be.DestroySampler(sampler); be.DestroyShader(shader);
    return 0;
}
