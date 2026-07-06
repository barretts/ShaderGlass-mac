//
// Anime4K-style clean edge push with restrained saturation lift.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float2 px=p.SourceSize.zw; float3 c=Source.sample(s,uv).rgb; float3 h=(Source.sample(s,uv+float2(px.x,0)).rgb+Source.sample(s,uv-float2(px.x,0)).rgb+Source.sample(s,uv+float2(0,px.y)).rgb+Source.sample(s,uv-float2(0,px.y)).rgb)*0.25;
    c=c+(c-h)*(0.40+0.25*clamp(p.SGMaskStrength,0.0,1.0)); float l=dot(c,float3(0.299,0.587,0.114)); c=mix(float3(l),c,0.90+clamp(p.SGColorBoost,0.0,1.5)*0.12); return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
