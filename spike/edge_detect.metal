//
// Edge-highlight overlay instead of a pure diagnostic mask.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float2 px=p.SourceSize.zw;
    float3 base=Source.sample(s,uv).rgb;
    float l=dot(base,float3(0.299,0.587,0.114));
    float lx=dot(Source.sample(s,uv+float2(px.x,0)).rgb,float3(0.299,0.587,0.114));
    float ly=dot(Source.sample(s,uv+float2(0,px.y)).rgb,float3(0.299,0.587,0.114));
    float e=smoothstep(0.015,0.18,abs(l-lx)+abs(l-ly));
    float3 tint = mix(float3(0.80,0.92,1.00), float3(0.20,1.00,0.70), clamp(p.SGColorBoost,0.0,1.5)*0.40);
    float overlay = e * (0.24 + 0.26 * clamp(p.SGMaskStrength, 0.0, 1.0));
    float3 outc = base * (1.0 - overlay * 0.30) + tint * overlay;
    return float4(clamp(outc * p.SGIntensity, 0.0, 1.0), 1.0);
}
