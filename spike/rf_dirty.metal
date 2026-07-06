//
// Dirty RF style with soft luma, noise, and color wash.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
static float hash21(float2 p){p=fract(p*float2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y);}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float2 px=p.SourceSize.zw; float3 c=(Source.sample(s,uv).rgb+Source.sample(s,uv+float2(px.x*2,0)).rgb+Source.sample(s,uv-float2(px.x*2,0)).rgb)/3.0;
    float n=(hash21(floor(in.position.xy)+float2(p.FrameCount,7.0))-0.5)*0.04; c=mix(c,c*float3(1.04,0.98,0.90),0.20); c+=n;
    float scan=sin((uv.y*p.OutputSize.y+p.FrameCount*0.04)*3.14159265)*0.5+0.5; c*=mix(1.0,mix(0.88,1.02,scan),clamp(p.SGScanlineStrength,0.0,1.0));
    return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
