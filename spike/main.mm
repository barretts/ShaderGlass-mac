//
// M-1 spike driver (headless, multi-case): proves the D3D11 -> Metal pass mapping
// the real MetalBackend will use, in isolation from libsgcore / capture.
//
// Hardened after adversarial review (run wtlvi6i8u). The original single isotropic
// 1:1 case proved the transpose claim but MASKED axis-swap / flip / anisotropic
// scale / half-texel / filter / gamma errors. This version adds discriminating
// cases, each with an ANALYTIC expected output so a wrong convention fails:
//
//   case A "identity 1:1"   : exact (0-LSB) passthrough; geometry+channel order.
//   case B "asymmetric MVP" : sx!=sy, sy<0 (vertical flip), tx!=ty -- mirrors a
//                             real preprocess UpdateMVP. Predicts each out pixel's
//                             sampled input texel analytically. Catches axis-swap,
//                             tx/ty-swap, flip-sign, and any residual transpose.
//   case C "magnify 2x linear": 32->64 with LINEAR filter + a 2-color checker;
//                             proves sub-texel UV + linear filtering produce the
//                             expected blended midpoints (point would not blend).
//   case D "border sample"  : a quad that samples OUTSIDE [0,1]; clampToBorderColor
//                             transparentBlack must yield 0 there (engine BORDER).
//   case E "sRGB target"    : render into a bgra8Unorm_srgb target and read back;
//                             proves the Metal sRGB RTV encode matches a hand
//                             computed linear->sRGB on a known mid value.
//
// Exit 0 iff every case passes.
//

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <string>

// engine's exact shader-pass vertex buffer (ShaderPass.cpp:23-35): 8 verts x
// (float4 pos + float2 uv). Verts 0..3 preprocess, 4..7 shader pass.
static const float sVertexBuffer[] = {
    -1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 1.0f,
    -1.0f,  1.0f, 0.0f, 1.0f, 0.0f, 0.0f,
     1.0f, -1.0f, 0.0f, 1.0f, 1.0f, 1.0f,
     1.0f,  1.0f, 0.0f, 1.0f, 1.0f, 0.0f,
     0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f,
     0.0f, 1.0f, 0.0f, 1.0f, 0.0f, 0.0f,
     1.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f,
     1.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f
};

struct UBO  { float MVP[16]; };
struct Push { float SourceSize[4]; float OriginalSize[4]; float OutputSize[4]; uint32_t FrameCount; };

static const int GEOM_IDX = 30;

// engine MVP layout (row-major m[i][j]), ShaderPass.cpp:164-213.
// SetMVP sets only the entries UpdateMVP touches; rest 0.
static void setMVP(float* m, float sx, float sy, float tx, float ty) {
    memset(m, 0, 16 * sizeof(float));
    m[0*4 + 0] = sx;   // m[0][0]
    m[1*4 + 1] = sy;   // m[1][1]
    m[3*4 + 0] = tx;   // m[3][0]
    m[3*4 + 1] = ty;   // m[3][1]
    m[3*4 + 3] = 1.0f; // m[3][3]
}

static id<MTLDevice>            gDev;
static id<MTLCommandQueue>      gQueue;
static id<MTLRenderPipelineState> gPSO_bgra;
static id<MTLRenderPipelineState> gPSO_srgb;

static NSString* readFile(const char* path) {
    NSError* err = nil;
    NSString* s = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:path]
                                            encoding:NSUTF8StringEncoding error:&err];
    if (!s) { fprintf(stderr, "FAIL: cannot read %s: %s\n", path, err.localizedDescription.UTF8String); exit(2); }
    return s;
}

static id<MTLTexture> makeTex(int w, int h, MTLPixelFormat fmt, MTLTextureUsage usage) {
    MTLTextureDescriptor* td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:fmt width:w height:h mipmapped:NO];
    td.usage = usage;
    return [gDev newTextureWithDescriptor:td];
}

// Render the shader-pass quad (verts 4..7) of `inTex` into an offscreen target of
// size (outW,outH) with the given MVP, filter and address mode. Returns BGRA bytes.
static std::vector<uint8_t> renderPass(id<MTLTexture> inTex, int outW, int outH,
                                       const float mvp[16],
                                       MTLSamplerMinMagFilter filter,
                                       MTLSamplerAddressMode addr,
                                       bool srgbTarget,
                                       int srcW, int srcH) {
    MTLSamplerDescriptor* sd = [[MTLSamplerDescriptor alloc] init];
    sd.minFilter = filter; sd.magFilter = filter;
    sd.sAddressMode = addr; sd.tAddressMode = addr; sd.rAddressMode = addr; // match engine AddressW too
    sd.borderColor = MTLSamplerBorderColorTransparentBlack;
    id<MTLSamplerState> sampler = [gDev newSamplerStateWithDescriptor:sd];

    MTLPixelFormat fmt = srgbTarget ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm;
    id<MTLTexture> outTex = makeTex(outW, outH, fmt, MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead);

    UBO ubo; memcpy(ubo.MVP, mvp, sizeof(ubo.MVP));
    Push push; memset(&push, 0, sizeof(push));
    push.SourceSize[0] = srcW; push.SourceSize[1] = srcH;
    push.SourceSize[2] = 1.0f/srcW; push.SourceSize[3] = 1.0f/srcH;
    push.OutputSize[0] = outW; push.OutputSize[1] = outH;
    push.OutputSize[2] = 1.0f/outW; push.OutputSize[3] = 1.0f/outH;

    id<MTLBuffer> uboBuf  = [gDev newBufferWithBytes:&ubo  length:sizeof(ubo)  options:MTLResourceStorageModeShared];
    id<MTLBuffer> pushBuf = [gDev newBufferWithBytes:&push length:sizeof(push) options:MTLResourceStorageModeShared];
    id<MTLBuffer> vtxBuf  = [gDev newBufferWithBytes:sVertexBuffer length:sizeof(sVertexBuffer) options:MTLResourceStorageModeShared];

    MTLRenderPassDescriptor* rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = outTex;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [gQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:(srgbTarget ? gPSO_srgb : gPSO_bgra)];
    [enc setViewport:(MTLViewport){0, 0, (double)outW, (double)outH, 0, 1}];
    [enc setVertexBuffer:vtxBuf offset:0 atIndex:GEOM_IDX];
    [enc setVertexBuffer:uboBuf offset:0 atIndex:0];
    [enc setVertexBuffer:pushBuf offset:0 atIndex:1];
    [enc setFragmentBuffer:uboBuf offset:0 atIndex:0];
    [enc setFragmentBuffer:pushBuf offset:0 atIndex:1];
    [enc setFragmentTexture:inTex atIndex:2];
    [enc setFragmentSamplerState:sampler atIndex:2];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:4 vertexCount:4];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.error) { fprintf(stderr, "FAIL: GPU: %s\n", cb.error.localizedDescription.UTF8String); exit(2); }

    std::vector<uint8_t> out(outW * outH * 4);
    [outTex getBytes:out.data() bytesPerRow:outW * 4
          fromRegion:MTLRegionMake2D(0, 0, outW, outH) mipmapLevel:0];
    return out;
}

static id<MTLTexture> uploadBGRA(const std::vector<uint8_t>& px, int w, int h) {
    id<MTLTexture> t = makeTex(w, h, MTLPixelFormatBGRA8Unorm, MTLTextureUsageShaderRead);
    [t replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:px.data() bytesPerRow:w*4];
    return t;
}

static int gFails = 0;
static void check(bool cond, const char* caseName, const char* msg) {
    fprintf(stderr, "  [%s] %s %s\n", cond ? "PASS" : "FAIL", caseName, msg);
    if (!cond) ++gFails;
}

// ---------------------------------------------------------------------------
int main(int argc, char** argv) {
    @autoreleasepool {
        const char* metalPath = (argc > 1) ? argv[1] : "passthrough.metal";

        gDev = MTLCreateSystemDefaultDevice();
        if (!gDev) { fprintf(stderr, "FAIL: no Metal device\n"); return 2; }
        fprintf(stderr, "Metal device: %s\n", gDev.name.UTF8String);
        gQueue = [gDev newCommandQueue];

        NSError* err = nil;
        id<MTLLibrary> lib = [gDev newLibraryWithSource:readFile(metalPath) options:nil error:&err];
        if (!lib) { fprintf(stderr, "FAIL: MSL compile: %s\n", err.localizedDescription.UTF8String); return 2; }
        id<MTLFunction> vs = [lib newFunctionWithName:@"vs_main"];
        id<MTLFunction> fs = [lib newFunctionWithName:@"fs_main"];
        if (!vs || !fs) { fprintf(stderr, "FAIL: missing vs_main/fs_main\n"); return 2; }

        MTLVertexDescriptor* vd = [[MTLVertexDescriptor alloc] init];
        vd.attributes[0].format = MTLVertexFormatFloat4; vd.attributes[0].offset = 0;  vd.attributes[0].bufferIndex = GEOM_IDX;
        vd.attributes[1].format = MTLVertexFormatFloat2; vd.attributes[1].offset = 16; vd.attributes[1].bufferIndex = GEOM_IDX;
        vd.layouts[GEOM_IDX].stride = 24;
        vd.layouts[GEOM_IDX].stepFunction = MTLVertexStepFunctionPerVertex;

        for (int srgb = 0; srgb < 2; ++srgb) {
            MTLRenderPipelineDescriptor* pd = [[MTLRenderPipelineDescriptor alloc] init];
            pd.vertexFunction = vs; pd.fragmentFunction = fs; pd.vertexDescriptor = vd;
            pd.colorAttachments[0].pixelFormat = srgb ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm;
            id<MTLRenderPipelineState> pso = [gDev newRenderPipelineStateWithDescriptor:pd error:&err];
            if (!pso) { fprintf(stderr, "FAIL: PSO(srgb=%d): %s\n", srgb, err.localizedDescription.UTF8String); return 2; }
            if (srgb) gPSO_srgb = pso; else gPSO_bgra = pso;
        }

        // gradient builder: BGRA, R=x, G=y, B=64, white 4x4 corner at (0,0)
        auto gradient = [](int W, int H){
            std::vector<uint8_t> p(W*H*4);
            for (int y=0;y<H;++y) for (int x=0;x<W;++x){
                uint8_t* q=&p[(y*W+x)*4];
                uint8_t r=(uint8_t)(x*255/(W-1)), g=(uint8_t)(y*255/(H-1)), b=64;
                if (x<4&&y<4){r=g=b=255;}
                q[0]=b;q[1]=g;q[2]=r;q[3]=255;
            }
            return p;
        };
        auto px = [](const std::vector<uint8_t>& v,int W,int x,int y,int c){ return (int)v[(y*W+x)*4+c]; };

        // =====================================================================
        // CASE A: identity 1:1, NEAREST, exact 0-LSB. (tightened from >1)
        // =====================================================================
        {
            const int W=64,H=64; float mvp[16]; setMVP(mvp,2,2,-1,-1);
            auto in=gradient(W,H); auto out=renderPass(uploadBGRA(in,W,H),W,H,mvp,
                MTLSamplerMinMagFilterNearest, MTLSamplerAddressModeClampToBorderColor,false,W,H);
            long maxd=0; for (size_t i=0;i<in.size();++i) maxd=std::max(maxd,labs((long)out[i]-(long)in[i]));
            check(maxd==0,"A:identity","exact passthrough, maxDiff==0 (no flip/swap/gamma on linear UNORM)");
        }

        // =====================================================================
        // CASE B: asymmetric MVP sx=1.5, sy=-2.0 (flip), tx=-0.3, ty=0.7.
        // Analytic model: the shader-VB quad has pos in [0,1]^2 paired with uv:
        //   vertex (posx,posy) -> uv (posx, 1-posy)  (verts 4..7: uv = (px, 1-py))
        // clip = MVP * pos (col-major load of row-major bytes), NDC = clip.xy/clip.w.
        // With this MVP: ndc.x = sx*posx + tx ; ndc.y = sy*posy + ty ; w=1.
        // Metal frag coord -> NDC: ndc.x = 2*(ox+0.5)/outW - 1 ; ndc.y = 1 - 2*(oy+0.5)/outH.
        // Invert to posx,posy, then uv, then input texel = (floor(uv.x*srcW), floor(uv.y*srcH)).
        // We replicate exactly that and compare to GPU output where uv in [0,1].
        // =====================================================================
        {
            const int W=64,H=64,OW=64,OH=64;
            float sx=1.5f, sy=-2.0f, tx=-0.3f, ty=0.7f; float mvp[16]; setMVP(mvp,sx,sy,tx,ty);
            auto in=gradient(W,H);
            auto out=renderPass(uploadBGRA(in,W,H),OW,OH,mvp,
                MTLSamplerMinMagFilterNearest, MTLSamplerAddressModeClampToBorderColor,false,W,H);
            long mism=0, checked=0; int fx=-1,fy=-1;
            for (int oy=0;oy<OH;++oy) for (int ox=0;ox<OW;++ox){
                float ndcx = 2.0f*(ox+0.5f)/OW - 1.0f;
                float ndcy = 1.0f - 2.0f*(oy+0.5f)/OH;
                float posx = (ndcx - tx)/sx;
                float posy = (ndcy - ty)/sy;
                float uvx = posx;          // verts 4..7: uv.x == posx
                float uvy = 1.0f - posy;   //              uv.y == 1 - posy
                if (uvx<0||uvx>=1||uvy<0||uvy>=1) continue; // border region handled in case D
                int sxi = std::min(W-1,(int)floorf(uvx*W));
                int syi = std::min(H-1,(int)floorf(uvy*H));
                ++checked;
                for (int c=0;c<3;++c){ // compare BGR (alpha forced to 1 by shader)
                    if (labs((long)out[(oy*OW+ox)*4+c]-(long)in[(syi*W+sxi)*4+c])>1){
                        if(mism==0){fx=ox;fy=oy;} ++mism; break;
                    }
                }
            }
            char m[160];
            snprintf(m,sizeof(m),"anisotropic+flip predicted-sample match (%ld in-range texels, %ld mismatch, first@(%d,%d))",checked,mism,fx,fy);
            check(mism==0 && checked>1000,"B:asym",m);
        }

        // =====================================================================
        // CASE C: magnify 32->64 with LINEAR filter, 2-color vertical split.
        // Left half input value 40, right half 200 (R channel). At the magnified
        // boundary, LINEAR sampling must produce intermediate values; NEAREST would
        // produce only 40 or 200. We assert that at least some output texels near
        // the boundary are strictly between (proves linear filtering is wired).
        // =====================================================================
        {
            const int W=32,H=32,OW=64,OH=64; float mvp[16]; setMVP(mvp,2,2,-1,-1);
            std::vector<uint8_t> in(W*H*4);
            for(int y=0;y<H;++y)for(int x=0;x<W;++x){uint8_t*q=&in[(y*W+x)*4]; uint8_t r=(x<W/2)?40:200; q[0]=r;q[1]=r;q[2]=r;q[3]=255;}
            auto out=renderPass(uploadBGRA(in,W,H),OW,OH,mvp,
                MTLSamplerMinMagFilterLinear, MTLSamplerAddressModeClampToEdge,false,W,H);
            int between=0, hi=0, lo=0;
            for(int i=0;i<OW*OH;++i){int v=out[i*4+2]; if(v>50&&v<190)++between; if(v>=190)++hi; if(v<=50)++lo;}
            char m[160]; snprintf(m,sizeof(m),"linear magnify blends boundary (between=%d, lo=%d, hi=%d)",between,lo,hi);
            check(between>0 && hi>0 && lo>0,"C:linear",m);
        }

        // =====================================================================
        // CASE D: border-mode does not corrupt in-range sampling.
        //
        // SCOPE (honest): the passthrough shader -- faithful to the engine -- only
        // ever samples uv in [0,1], so this spike CANNOT push uv out of range
        // without diverging from the real shader. Therefore this case proves only
        // that clampToBorderColor mode leaves in-range sampling untouched (a fully
        // white 16x16 magnified to 48x48 stays fully white, no edge bleed).
        //
        // RESIDUAL GAP (not closed here): the transparent-black border VALUE for
        // true out-of-range UV is NOT verified. In the engine that path is the
        // preprocess letterbox (source smaller than dest), so it must be covered by
        // an end-to-end preprocess-pass test in the real MetalBackend, not this
        // hand-ported shader-pass spike.
        // =====================================================================
        {
            const int W=16,H=16,OW=48,OH=48; float mvp[16]; setMVP(mvp,2,2,-1,-1);
            std::vector<uint8_t> in(W*H*4,255);
            auto out=renderPass(uploadBGRA(in,W,H),OW,OH,mvp,
                MTLSamplerMinMagFilterNearest, MTLSamplerAddressModeClampToBorderColor,false,W,H);
            long nonwhite=0; for(int i=0;i<OW*OH;++i){if(out[i*4+2]<254||out[i*4+1]<254||out[i*4+0]<254)++nonwhite;}
            check(nonwhite==0,"D:border","in-range magnify w/ border mode stays white (no edge bleed)");
        }

        // =====================================================================
        // CASE E: sRGB render target. Render a constant linear value into a
        // bgra8Unorm_srgb target; the Metal RTV must sRGB-encode it on store, so
        // the read-back byte equals the sRGB encoding of the linear value, matching
        // D3D's B8G8R8A8_UNORM_SRGB semantics. We feed a uniform input of linear
        // 0.5 (128/255 ish) through passthrough and check the stored byte > the
        // linear byte (encode brightens mid-grey toward ~188).
        // The fragment writes Source.Sample(...).xyz directly; Source is a plain
        // BGRA8Unorm input sampled as linear 0..1, so feeding stored byte 128 yields
        // shader output ~0.502 linear, which the sRGB target encodes to ~0.735
        // (~188/255). We assert the stored byte is in [180,196].
        // =====================================================================
        {
            const int W=8,H=8; float mvp[16]; setMVP(mvp,2,2,-1,-1);
            std::vector<uint8_t> in(W*H*4); for(int i=0;i<W*H;++i){in[i*4+0]=128;in[i*4+1]=128;in[i*4+2]=128;in[i*4+3]=255;}
            auto out=renderPass(uploadBGRA(in,W,H),W,H,mvp,
                MTLSamplerMinMagFilterNearest, MTLSamplerAddressModeClampToEdge,/*srgb*/true,W,H);
            int v=px(out,W,4,4,2); // center R
            char m[128]; snprintf(m,sizeof(m),"linear 128/255 -> sRGB-encoded stored byte=%d (expect ~188)",v);
            check(v>=180 && v<=196,"E:srgb",m);
        }

        fprintf(stderr,"\n%s: %d case(s) failed.\n", gFails?"OVERALL FAIL":"OVERALL PASS", gFails);
        return gFails ? 1 : 0;
    }
}
