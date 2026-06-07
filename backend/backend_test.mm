/*
IRenderBackend conformance test.

Drives the passthrough shader pass through the ABSTRACTION (sg::IRenderBackend ->
MetalBackend), issuing the same verb sequence ShaderPass::Render issues, and
pixel-diffs offscreen output vs input. This validates that the interface is
correctly shaped and the Metal backend implements it faithfully -- the real M0
deliverable verifiable without a Windows compiler or a window.

Mirrors the verified spike (mac/spike), but through the interface rather than
inline Metal calls.
*/

#include "MetalBackend.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <string>
#include <fstream>
#include <sstream>

using namespace sg;

// engine's exact shader-pass vertex buffer (ShaderPass.cpp:23-35)
static const float sVertexBuffer[] = {
    -1,-1,0,1, 0,1,  -1,1,0,1, 0,0,  1,-1,0,1, 1,1,  1,1,0,1, 1,0,
     0, 0,0,1, 0,1,   0,1,0,1, 0,0,  1, 0,0,1, 1,1,  1,1,0,1, 1,0
};
struct UBO  { float MVP[16]; };
struct Push { float SourceSize[4]; float OriginalSize[4]; float OutputSize[4]; uint32_t FrameCount; };

static std::string readFile(const char* path) {
    std::ifstream f(path);
    if (!f) { fprintf(stderr, "FAIL: cannot read %s\n", path); exit(2); }
    std::stringstream ss; ss << f.rdbuf(); return ss.str();
}

int main(int argc, char** argv) {
    const char* mslPath = (argc > 1) ? argv[1] : "../spike/passthrough.metal";
    const uint32_t W = 64, H = 64;

    MetalBackend be;
    if (!be.InitializeHeadless()) { fprintf(stderr, "FAIL: no Metal device\n"); return 2; }

    std::string msl = readFile(mslPath);

    // --- create resources through the interface ---
    BackendShader* shader = be.CreateShader(msl.data(), msl.size(), msl.data(), msl.size());
    if (!shader) { fprintf(stderr, "FAIL: CreateShader\n"); return 2; }

    SamplerDesc sdesc; // defaults: Nearest + Border (engine default)
    BackendSampler* sampler = be.CreateSampler(sdesc);

    BackendBuffer* vtx  = be.CreateVertexBuffer(sVertexBuffer, sizeof(sVertexBuffer));
    BackendBuffer* ubo  = be.CreateConstantBuffer(sizeof(UBO));
    BackendBuffer* push = be.CreateConstantBuffer(sizeof(Push));

    // input texture (BGRA gradient + white corner marker)
    std::vector<uint8_t> in(W*H*4);
    for (uint32_t y=0;y<H;++y) for (uint32_t x=0;x<W;++x){
        uint8_t* q=&in[(y*W+x)*4];
        uint8_t r=(uint8_t)(x*255/(W-1)), g=(uint8_t)(y*255/(H-1)), b=64;
        if (x<4&&y<4){r=g=b=255;}
        q[0]=b;q[1]=g;q[2]=r;q[3]=255;
    }
    TextureDesc itd{W,H,PixFmt::BGRA8_UNORM,false};
    BackendTexture* inTex = be.CreateTexture(itd);
    be.UploadBGRA(inTex, in.data(), W, H); // test-only helper (engine uses WrapNativeFrame)

    TextureDesc otd{W,H,PixFmt::BGRA8_UNORM,true};
    BackendTexture* outTex = be.CreateTexture(otd);

    // constants: engine default shader-pass MVP
    UBO u; memset(u.MVP,0,sizeof(u.MVP));
    u.MVP[0]=2; u.MVP[5]=2; u.MVP[12]=-1; u.MVP[13]=-1; u.MVP[15]=1;
    Push pu; memset(&pu,0,sizeof(pu));
    pu.SourceSize[0]=W; pu.SourceSize[1]=H; pu.SourceSize[2]=1.0f/W; pu.SourceSize[3]=1.0f/H;
    pu.OutputSize[0]=W; pu.OutputSize[1]=H; pu.OutputSize[2]=1.0f/W; pu.OutputSize[3]=1.0f/H;
    be.UpdateConstantBuffer(ubo,  &u,  sizeof(u));
    be.UpdateConstantBuffer(push, &pu, sizeof(pu));

    // --- the ShaderPass::Render verb sequence, through the interface ---
    float clear[4] = {0,0,0,1};
    be.BeginRenderPass(outTex, true, clear);
    be.SetViewport(0,0,(float)W,(float)H);
    be.BindShader(shader);
    be.SetVertexBuffer(vtx, 24, 0);
    be.BindConstantBuffer(kUboBufferIndex,  ubo);
    be.BindConstantBuffer(kPushBufferIndex, push);
    be.BindTexture(2, inTex);
    be.BindSampler(2, sampler);
    be.SetBlend(BlendMode::Disabled);
    be.Draw(4, 4); // triangle strip, shader-pass start vertex 4
    be.EndRenderPass();

    // --- verify ---
    auto out = be.ReadbackBGRA(outTex, W, H);
    long maxd=0; for (size_t i=0;i<in.size();++i) maxd=std::max(maxd,labs((long)out[i]-(long)in[i]));
    fprintf(stderr, "through-interface passthrough (BGRA8 target): maxChannelDiff=%ld\n", maxd);
    bool ok = (maxd == 0);

    // --- regression for the format-agnostic PSO cache (review finding #6) ---
    // The SAME shader handle must serve a different render-target format. Render a
    // uniform linear 128/255 input into an sRGB target; the PSO cache must build a
    // second variant keyed on BGRA8_sRGB and the sRGB RTV must encode on store
    // (linear 0.502 -> ~188), matching D3D's B8G8R8A8_UNORM_SRGB semantics.
    {
        std::vector<uint8_t> gin(8*8*4);
        for (int i=0;i<8*8;++i){gin[i*4+0]=128;gin[i*4+1]=128;gin[i*4+2]=128;gin[i*4+3]=255;}
        TextureDesc gitd{8,8,PixFmt::BGRA8_UNORM,false};
        BackendTexture* gInTex = be.CreateTexture(gitd);
        be.UploadBGRA(gInTex, gin.data(), 8, 8);
        TextureDesc gotd{8,8,PixFmt::BGRA8_SRGB,true};
        BackendTexture* gOutTex = be.CreateTexture(gotd);

        UBO u2; memset(u2.MVP,0,sizeof(u2.MVP)); u2.MVP[0]=2;u2.MVP[5]=2;u2.MVP[12]=-1;u2.MVP[13]=-1;u2.MVP[15]=1;
        Push p2; memset(&p2,0,sizeof(p2)); p2.SourceSize[0]=8;p2.SourceSize[1]=8;p2.OutputSize[0]=8;p2.OutputSize[1]=8;
        BackendBuffer* ub2 = be.CreateConstantBuffer(sizeof(UBO));
        BackendBuffer* pb2 = be.CreateConstantBuffer(sizeof(Push));
        BackendSampler* smp2 = be.CreateSampler(SamplerDesc{Filter::Nearest, Wrap::Clamp});
        be.UpdateConstantBuffer(ub2,&u2,sizeof(u2)); be.UpdateConstantBuffer(pb2,&p2,sizeof(p2));

        be.BeginRenderPass(gOutTex, true, clear);
        be.SetViewport(0,0,8,8);
        be.BindShader(shader); // <-- same handle as the BGRA8 pass above
        be.SetVertexBuffer(vtx,24,0);
        be.BindConstantBuffer(kUboBufferIndex,ub2);
        be.BindConstantBuffer(kPushBufferIndex,pb2);
        be.BindTexture(2,gInTex); be.BindSampler(2,smp2);
        be.SetBlend(BlendMode::Disabled);
        be.Draw(4,4);
        be.EndRenderPass();

        auto gout = be.ReadbackBGRA(gOutTex,8,8);
        int v = gout[(4*8+4)*4+2];
        fprintf(stderr, "format-agnostic PSO cache (sRGB target, same shader): stored byte=%d (expect ~188)\n", v);
        ok = ok && (v>=180 && v<=196);

        be.DestroyTexture(gInTex); be.DestroyTexture(gOutTex);
        be.DestroyBuffer(ub2); be.DestroyBuffer(pb2); be.DestroySampler(smp2);
    }

    // --- regression for G1 (CreateTexture initialData) + G3 (ReadbackTexture) ---
    // Create an input texture WITH initial CPU pixels (the Texture.cpp preset-image
    // path), render passthrough into a cpuReadable target, and read it back through
    // the interface verb -- exercising the two API additions the engine refactor needs.
    {
        const int S = 32;
        std::vector<uint8_t> src(S*S*4);
        for (int y=0;y<S;++y) for (int x=0;x<S;++x){ uint8_t* q=&src[(y*S+x)*4];
            q[0]=(uint8_t)(x*255/(S-1)); q[1]=(uint8_t)(y*255/(S-1)); q[2]=128; q[3]=255; }
        TextureDesc sitd{(uint32_t)S,(uint32_t)S,PixFmt::BGRA8_UNORM,false,false};
        BackendTexture* sTex = be.CreateTexture(sitd, src.data(), S*4); // <-- G1 initialData upload
        TextureDesc sotd{(uint32_t)S,(uint32_t)S,PixFmt::BGRA8_UNORM,true,true}; // cpuReadable
        BackendTexture* dTex = be.CreateTexture(sotd);

        UBO u3; memset(u3.MVP,0,sizeof(u3.MVP)); u3.MVP[0]=2;u3.MVP[5]=2;u3.MVP[12]=-1;u3.MVP[13]=-1;u3.MVP[15]=1;
        Push p3; memset(&p3,0,sizeof(p3)); p3.SourceSize[0]=S;p3.SourceSize[1]=S;p3.OutputSize[0]=S;p3.OutputSize[1]=S;
        BackendBuffer* ub3=be.CreateConstantBuffer(sizeof(UBO)); BackendBuffer* pb3=be.CreateConstantBuffer(sizeof(Push));
        BackendBuffer* vb3=be.CreateVertexBuffer(sVertexBuffer,sizeof(sVertexBuffer));
        BackendSampler* sm3=be.CreateSampler(SamplerDesc{});
        be.UpdateConstantBuffer(ub3,&u3,sizeof(u3)); be.UpdateConstantBuffer(pb3,&p3,sizeof(p3));

        be.BeginRenderPass(dTex,true,clear); be.SetViewport(0,0,S,S);
        be.BindShader(shader); be.SetVertexBuffer(vb3,24,0);
        be.BindConstantBuffer(kUboBufferIndex,ub3); be.BindConstantBuffer(kPushBufferIndex,pb3);
        be.BindTexture(2,sTex); be.BindSampler(2,sm3); be.SetBlend(BlendMode::Disabled);
        be.Draw(4,4); be.EndRenderPass();

        std::vector<uint8_t> rb(S*S*4);
        be.ReadbackTexture(dTex, rb.data(), S*4); // <-- G3 ReadbackTexture verb
        long m=0; for (size_t i=0;i<src.size();++i) m=std::max(m,labs((long)rb[i]-(long)src[i]));
        fprintf(stderr,"G1/G3 round-trip (initialData upload -> render -> ReadbackTexture): maxChannelDiff=%ld\n",m);
        ok = ok && (m==0);

        be.DestroyTexture(sTex); be.DestroyTexture(dTex);
        be.DestroyBuffer(ub3); be.DestroyBuffer(pb3); be.DestroyBuffer(vb3); be.DestroySampler(sm3);
    }

    be.DestroyTexture(inTex); be.DestroyTexture(outTex);
    be.DestroyBuffer(vtx); be.DestroyBuffer(ubo); be.DestroyBuffer(push);
    be.DestroySampler(sampler); be.DestroyShader(shader);

    if (!ok) { fprintf(stderr, "FAIL: a backend conformance case failed\n"); return 1; }
    fprintf(stderr, "PASS: IRenderBackend/MetalBackend conformance (passthrough + PSO cache + G1/G3 verbs).\n");
    return 0;
}
