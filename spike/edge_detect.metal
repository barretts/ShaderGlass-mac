//
// Edge detect utility view.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float2 px=p.SourceSize.zw; float l=dot(Source.sample(s,uv).rgb,float3(0.299,0.587,0.114));
    float lx=dot(Source.sample(s,uv+float2(px.x,0)).rgb,float3(0.299,0.587,0.114)); float ly=dot(Source.sample(s,uv+float2(0,px.y)).rgb,float3(0.299,0.587,0.114));
    float e=abs(l-lx)+abs(l-ly); return float4(clamp(float3(e)*2.4*p.SGIntensity,0.0,1.0),1.0);
}
