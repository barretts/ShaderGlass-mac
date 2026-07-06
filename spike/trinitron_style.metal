//
// Trinitron-style aperture grille with cool brightness and clean scanlines.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float3 c=Source.sample(s,uv).rgb; float scan=sin(uv.y*p.SourceSize.y*3.14159265)*0.5+0.5;
    c*=mix(1.0,mix(0.70,1.08,scan),clamp(p.SGScanlineStrength,0.0,1.0)); float m=fract(in.position.x/3.0);
    float3 grille=m<0.333?float3(1.12,0.86,0.86):m<0.666?float3(0.86,1.12,0.86):float3(0.88,0.90,1.14);
    c*=mix(float3(1.0),grille,clamp(p.SGMaskStrength,0.0,1.0)); c=mix(c,c*float3(0.94,0.98,1.05),0.35); return float4(clamp(c*1.10*p.SGIntensity,0.0,1.0),1.0);
}
