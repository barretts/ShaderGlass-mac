//
// PlayStation dirty analog look with jitter, noise, and desaturated fog.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
static float hash21(float2 p){p=fract(p*float2(61.7,173.3)); p+=dot(p,p+23.1); return fract(p.x*p.y);}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; uv.x+=sin(uv.y*14.0+float(p.FrameCount)*0.03)*0.0008; float3 c=Source.sample(s,uv).rgb; float l=dot(c,float3(0.299,0.587,0.114));
    c=mix(float3(l),c,0.58+clamp(p.SGColorBoost,0.0,1.5)*0.20); c=mix(c,float3(l)*float3(0.95,0.93,1.00),0.12);
    c+=(hash21(floor(in.position.xy)+float2(p.FrameCount,5.0))-0.5)*0.02; return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
