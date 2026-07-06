//
// Generic TV-out look: gentle blur, color rolloff, dark scanlines.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float2 px=p.SourceSize.zw; float3 c=(Source.sample(s,uv).rgb*0.6+Source.sample(s,uv+float2(px.x,0)).rgb*0.2+Source.sample(s,uv-float2(px.x,0)).rgb*0.2);
    c=mix(c,c*float3(1.02,0.98,0.92),0.18); float scan=sin((uv.y*p.OutputSize.y+0.2)*3.14159265)*0.5+0.5; c*=mix(1.0,mix(0.82,1.02,scan),clamp(p.SGScanlineStrength,0.0,1.0));
    return float4(clamp(c*p.SGIntensity,0.0,1.0),1.0);
}
