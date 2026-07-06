//
// Guest Advanced-style approximation: crisp scanlines, slot mask, mild bloom.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord; float2 px=p.SourceSize.zw; float3 c=Source.sample(s,uv).rgb;
    float scan=sin((uv.y*p.SourceSize.y+0.35)*3.14159265)*0.5+0.5; c*=mix(1.0,mix(0.55,1.10,scan),clamp(p.SGScanlineStrength,0.0,1.0));
    float phase=fract(in.position.x/2.5); float3 mask=phase<0.5?float3(1.05,0.90,1.00):float3(0.92,1.08,0.92); c*=mix(float3(1.0),mask,clamp(p.SGMaskStrength,0.0,1.0)*0.8);
    float3 blur=(Source.sample(s,uv+px*float2(1.0,0)).rgb+Source.sample(s,uv-px*float2(1.0,0)).rgb)*0.5; c+=blur*smoothstep(0.62,1.0,max(max(blur.r,blur.g),blur.b))*0.06;
    float l=dot(c,float3(0.299,0.587,0.114)); c=mix(float3(l),c,0.62+clamp(p.SGColorBoost,0.0,1.5)*0.25); return float4(clamp(c*1.08*p.SGIntensity,0.0,1.0),1.0);
}
