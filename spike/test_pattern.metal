//
// Compact corner test-pattern overlay for alignment and color sanity checks.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord;
    float3 base=Source.sample(s,uv).rgb;
    float2 overlayMin=float2(0.03,0.03);
    float2 overlayMax=float2(0.30,0.14);
    if (uv.x < overlayMin.x || uv.x > overlayMax.x || uv.y < overlayMin.y || uv.y > overlayMax.y) {
        return float4(clamp(base * p.SGIntensity, 0.0, 1.0), 1.0);
    }
    float2 local=(uv-overlayMin)/(overlayMax-overlayMin);
    float bars=floor(local.x*7.0);
    float3 bar=bars<1?float3(1,1,1):bars<2?float3(1,1,0):bars<3?float3(0,1,1):bars<4?float3(0,1,0):bars<5?float3(1,0,1):bars<6?float3(1,0,0):float3(0,0,1);
    float frame=step(local.x,0.01)+step(local.y,0.01)+step(0.99,local.x)+step(0.99,local.y);
    float3 outc=mix(base, bar, 0.42);
    outc = mix(outc, float3(1.0), min(frame, 1.0) * 0.35);
    return float4(clamp(outc * p.SGIntensity, 0.0, 1.0), 1.0);
}
