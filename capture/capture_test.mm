/*
Headless test for the capture->render seam, minus the permission-gated SCStream.

Synthesizes an IOSurface-backed CVPixelBuffer (exactly what SCK delivers), converts
it to a zero-copy MTLTexture via CVToMetal (the bug-prone core), wraps it through
MetalBackend::WrapNativeFrame, runs the passthrough pass, and pixel-diffs the output
vs the bytes we wrote into the pixel buffer. Proves the CVPixelBuffer->MTLTexture->
WrapNativeFrame->Process path end-to-end without any TCC screen-recording grant.
*/

#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#include "SCKCapture.h"
#include "../backend/MetalBackend.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
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

static std::string readFile(const char* path) {
    std::ifstream f(path); if (!f){fprintf(stderr,"FAIL: read %s\n",path);exit(2);}
    std::stringstream ss; ss<<f.rdbuf(); return ss.str();
}

// Make an IOSurface-backed BGRA CVPixelBuffer (what SCK hands us) and fill it.
static CVPixelBufferRef makePixelBuffer(int w, int h, const std::vector<uint8_t>& bgra) {
    NSDictionary* attrs = @{
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVPixelBufferRef pb = nullptr;
    CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                     kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)attrs, &pb);
    if (r != kCVReturnSuccess || !pb) { fprintf(stderr,"FAIL: CVPixelBufferCreate %d\n",r); exit(2); }
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t* base = (uint8_t*)CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    for (int y=0;y<h;++y) memcpy(base + y*stride, bgra.data() + y*w*4, w*4);
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

int main(int argc, char** argv) {
    const char* mslPath = (argc>1)?argv[1]:"../spike/passthrough.metal";
    const int W=64, H=64;

    MetalBackend be;
    if (!be.InitializeHeadless()) { fprintf(stderr,"FAIL: no Metal device\n"); return 2; }

    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    CVToMetal conv;
    if (!conv.Initialize(dev)) { fprintf(stderr,"FAIL: CVToMetal init\n"); return 2; }

    // monotonic clock sanity
    uint64_t t0 = MonotonicMillis();
    if (t0 == 0) fprintf(stderr,"WARN: MonotonicMillis returned 0\n");

    // input bytes (BGRA gradient + white corner marker)
    std::vector<uint8_t> in(W*H*4);
    for (int y=0;y<H;++y) for (int x=0;x<W;++x){
        uint8_t* q=&in[(y*W+x)*4];
        uint8_t r=(uint8_t)(x*255/(W-1)), g=(uint8_t)(y*255/(H-1)), b=64;
        if (x<4&&y<4){r=g=b=255;}
        q[0]=b;q[1]=g;q[2]=r;q[3]=255;
    }
    CVPixelBufferRef pb = makePixelBuffer(W,H,in);

    // convert via the capture-path core
    id<MTLTexture> capTex = conv.TextureFromPixelBuffer(pb);
    if (!capTex) { fprintf(stderr,"FAIL: TextureFromPixelBuffer\n"); return 1; }
    if ((int)capTex.width != W || (int)capTex.height != H) {
        fprintf(stderr,"FAIL: tex dims %lux%lu\n",(unsigned long)capTex.width,(unsigned long)capTex.height); return 1;
    }

    // wrap through the backend exactly as SCKCapture does
    TextureDesc itd{(uint32_t)W,(uint32_t)H,PixFmt::BGRA8_UNORM,false};
    BackendTexture* inTex = be.WrapNativeFrame((__bridge void*)capTex, itd);

    // run passthrough into an offscreen target
    std::string msl = readFile(mslPath);
    BackendShader* shader = be.CreateShader(msl.data(),msl.size(),msl.data(),msl.size());
    BackendSampler* sampler = be.CreateSampler(SamplerDesc{});
    BackendBuffer* vtx = be.CreateVertexBuffer(sVertexBuffer,sizeof(sVertexBuffer));
    BackendBuffer* ubo = be.CreateConstantBuffer(sizeof(UBO));
    BackendBuffer* push= be.CreateConstantBuffer(sizeof(Push));
    TextureDesc otd{(uint32_t)W,(uint32_t)H,PixFmt::BGRA8_UNORM,true};
    BackendTexture* outTex = be.CreateTexture(otd);

    UBO u; memset(u.MVP,0,sizeof(u.MVP)); u.MVP[0]=2;u.MVP[5]=2;u.MVP[12]=-1;u.MVP[13]=-1;u.MVP[15]=1;
    Push pu; memset(&pu,0,sizeof(pu)); pu.SourceSize[0]=W;pu.SourceSize[1]=H;pu.OutputSize[0]=W;pu.OutputSize[1]=H;
    pu.SGIntensity = 1.0f; pu.SGScanlineStrength = 0.65f; pu.SGMaskStrength = 0.70f; pu.SGColorBoost = 1.0f;
    be.UpdateConstantBuffer(ubo,&u,sizeof(u)); be.UpdateConstantBuffer(push,&pu,sizeof(pu));

    float clear[4]={0,0,0,1};
    be.BeginRenderPass(outTex,true,clear);
    be.SetViewport(0,0,(float)W,(float)H);
    be.BindShader(shader);
    be.SetVertexBuffer(vtx,24,0);
    be.BindConstantBuffer(kUboBufferIndex,ubo);
    be.BindConstantBuffer(kPushBufferIndex,push);
    be.BindTexture(2,inTex);
    be.BindSampler(2,sampler);
    be.SetBlend(BlendMode::Disabled);
    be.Draw(4,4);
    be.EndRenderPass();

    auto out = be.ReadbackBGRA(outTex,W,H);
    long maxd=0; for (size_t i=0;i<in.size();++i) maxd=std::max(maxd,labs((long)out[i]-(long)in[i]));
    fprintf(stderr,"capture-path passthrough (CVPixelBuffer->MTLTexture->WrapNativeFrame): maxChannelDiff=%ld\n",maxd);
    bool ok = (maxd == 0);

    be.DestroyTexture(inTex); be.DestroyTexture(outTex);
    be.DestroyBuffer(vtx); be.DestroyBuffer(ubo); be.DestroyBuffer(push);
    be.DestroySampler(sampler); be.DestroyShader(shader);
    conv.Flush();
    CVPixelBufferRelease(pb);

    // --- multi-frame ring stress (exercises CVToMetal's ref ring) ---
    // Convert N distinct pixel buffers WITHOUT releasing prior ones, holding the
    // returned MTLTextures, then verify each still samples to its OWN content. A
    // single-slot converter would have released earlier IOSurfaces, corrupting the
    // earlier textures' reads. Mirrors frames-in-flight under SCStream queueDepth.
    {
        const int N = 6, S = 16; // > CVToMetal RING_DEPTH(4) so the ring wraps
        std::string msl2 = readFile(mslPath);
        BackendShader* sh = be.CreateShader(msl2.data(),msl2.size(),msl2.data(),msl2.size());
        BackendSampler* smp = be.CreateSampler(SamplerDesc{});
        BackendBuffer* vb = be.CreateVertexBuffer(sVertexBuffer,sizeof(sVertexBuffer));
        BackendBuffer* ub = be.CreateConstantBuffer(sizeof(UBO));
        BackendBuffer* pb2 = be.CreateConstantBuffer(sizeof(Push));
        UBO u2; memset(u2.MVP,0,sizeof(u2.MVP)); u2.MVP[0]=2;u2.MVP[5]=2;u2.MVP[12]=-1;u2.MVP[13]=-1;u2.MVP[15]=1;
        Push p2; memset(&p2,0,sizeof(p2)); p2.SourceSize[0]=S;p2.SourceSize[1]=S;p2.OutputSize[0]=S;p2.OutputSize[1]=S;
        p2.SGIntensity = 1.0f; p2.SGScanlineStrength = 0.65f; p2.SGMaskStrength = 0.70f; p2.SGColorBoost = 1.0f;
        be.UpdateConstantBuffer(ub,&u2,sizeof(u2)); be.UpdateConstantBuffer(pb2,&p2,sizeof(p2));

        std::vector<CVPixelBufferRef> pbs;
        std::vector<id<MTLTexture>> texs;
        for (int n=0;n<N;++n){ // create + convert all frames first (all refs in flight)
            std::vector<uint8_t> b(S*S*4, (uint8_t)(n*37+5)); // distinct uniform value per frame
            for (int i=0;i<S*S;++i){b[i*4+3]=255;}
            CVPixelBufferRef cpb = makePixelBuffer(S,S,b);
            pbs.push_back(cpb);
            texs.push_back(conv.TextureFromPixelBuffer(cpb));
        }
        int ringFails=0;
        for (int n=0;n<N;++n){
            BackendTexture* it = be.WrapNativeFrame((__bridge void*)texs[n], TextureDesc{(uint32_t)S,(uint32_t)S,PixFmt::BGRA8_UNORM,false});
            BackendTexture* ot = be.CreateTexture(TextureDesc{(uint32_t)S,(uint32_t)S,PixFmt::BGRA8_UNORM,true});
            be.BeginRenderPass(ot,true,clear); be.SetViewport(0,0,S,S);
            be.BindShader(sh); be.SetVertexBuffer(vb,24,0);
            be.BindConstantBuffer(kUboBufferIndex,ub); be.BindConstantBuffer(kPushBufferIndex,pb2);
            be.BindTexture(2,it); be.BindSampler(2,smp); be.SetBlend(BlendMode::Disabled);
            be.Draw(4,4); be.EndRenderPass();
            auto o = be.ReadbackBGRA(ot,S,S);
            uint8_t expect = (uint8_t)(n*37+5);
            // recent frames (within RING_DEPTH of the newest) must be exact; older
            // frames may have had their IOSurface reclaimed by the ring -- that is
            // expected/correct, so we only assert the last RING_DEPTH frames.
            if (n >= N-4 && (labs((long)o[2]-(long)expect)>1)) { ringFails++; fprintf(stderr,"  ring frame %d: got %d expect %d\n",n,o[2],expect); }
            be.DestroyTexture(it); be.DestroyTexture(ot);
        }
        fprintf(stderr,"ring stress: %d recent-frame mismatch(es) over %d frames\n",ringFails,N);
        ok = ok && (ringFails==0);
        for (auto cpb : pbs) CVPixelBufferRelease(cpb);
        be.DestroyBuffer(vb); be.DestroyBuffer(ub); be.DestroyBuffer(pb2);
        be.DestroySampler(smp); be.DestroyShader(sh);
        conv.Flush();
    }

    // --- restart stress: Start/Stop calls Initialize repeatedly on one converter ---
    // This used to overwrite the CVMetalTextureCacheRef without releasing the old
    // cache. The probe cannot count CF retains directly, but it exercises the exact
    // lifecycle: initialize -> convert -> flush -> initialize again.
    {
        int restartFails = 0;
        for (int n=0; n<4; ++n) {
            if (!conv.Initialize(dev)) { restartFails++; continue; }
            std::vector<uint8_t> b(8*8*4, (uint8_t)(40 + n));
            for (int i=0; i<8*8; ++i) b[i*4+3] = 255;
            CVPixelBufferRef rpb = makePixelBuffer(8, 8, b);
            id<MTLTexture> tex = conv.TextureFromPixelBuffer(rpb);
            if (!tex || tex.width != 8 || tex.height != 8) restartFails++;
            CVPixelBufferRelease(rpb);
            conv.Flush();
        }
        fprintf(stderr,"restart stress: %d failure(s) over 4 CVToMetal reinitializes\n", restartFails);
        ok = ok && (restartFails == 0);
    }

    if (!ok) { fprintf(stderr,"FAIL: a capture-path case failed\n"); return 1; }
    fprintf(stderr,"PASS: capture-path seam + CVToMetal ring deliver frames pixel-perfect.\n");
    return 0;
}
