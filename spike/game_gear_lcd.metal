//
// Game Gear LCD-style bright color with coarse portable panel grid.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float3 c=Source.sample(s,uv).rgb; c=mix(float3(dot(c,float3(0.299,0.587,0.114))),c,0.90+clamp(p.SGColorBoost,0.0,1.5)*0.12);
    float2 cell=fract(in.position.xy/3.5); float grid=max(step(0.86,cell.x),step(0.86,cell.y)); c*=1.0-grid*(0.05+0.05*clamp(p.SGMaskStrength,0.0,1.0)); return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
