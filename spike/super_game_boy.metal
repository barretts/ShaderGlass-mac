//
// Super Game Boy flavor: Game Boy greens with a soft SNES-era color wash.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float3 c=Source.sample(s,uv).rgb; float l=dot(c,float3(0.299,0.587,0.114)); l=floor(clamp(l,0.0,0.999)*4.0)/3.0;
    float3 gb=mix(float3(0.05,0.16,0.07),float3(0.76,0.82,0.46),l); gb=mix(gb,gb*float3(1.10,0.96,1.04),0.18); return float4(clamp(gb*p.SGIntensity,0.0,1.0),1.0);
}
