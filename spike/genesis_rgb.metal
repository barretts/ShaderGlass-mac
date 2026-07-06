//
// Mega Drive / Genesis RGB look with bold primaries and clean edges.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float3 c=Source.sample(s,uv).rgb; float l=dot(c,float3(0.299,0.587,0.114)); c=mix(float3(l),c,0.95+clamp(p.SGColorBoost,0.0,1.5)*0.12);
    c=mix(c,c*float3(1.05,1.00,1.08),0.18); float scan=sin((uv.y*p.OutputSize.y+0.1)*3.14159265)*0.5+0.5; c*=mix(1.0,mix(0.90,1.03,scan),clamp(p.SGScanlineStrength,0.0,1.0)); return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
