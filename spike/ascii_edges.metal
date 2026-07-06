//
// ASCII-ish edge blocks without destroying full readability.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float2 cell=floor(in.position.xy/8.0)*8.0; float2 suv=cell/p.OutputSize.xy; float3 c=Source.sample(s,suv).rgb; float l=dot(c,float3(0.299,0.587,0.114));
    float gx=fract(in.position.x/8.0), gy=fract(in.position.y/8.0); float pattern=(step(0.4,l)*(gx>0.2&&gx<0.8?1.0:0.0)+step(0.7,l)*(gy>0.4&&gy<0.6?1.0:0.0)); c=mix(c*0.30,c,pattern); return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
