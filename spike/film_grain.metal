//
// Film grain overlay with mild contrast compression.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
static float hash21(float2 p){p=fract(p*float2(127.1,311.7)); p+=dot(p,p+74.7); return fract(p.x*p.y);}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float3 c=Source.sample(s,uv).rgb; float g=(hash21(floor(in.position.xy)+float2(p.FrameCount,p.FrameCount*0.41))-0.5)*(0.03+0.03*clamp(p.SGMaskStrength,0.0,1.0)); c=pow(c,float3(0.94)); c+=g; return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
