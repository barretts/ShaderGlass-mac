//
// CRT Royale-style approximation with strong phosphor, glow, and shadow mask.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]) { VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o; }
static float2 curve(float2 uv){ float2 q=uv*2.0-1.0; q*=1.0+dot(q,q)*0.055; return q*0.5+0.5; }
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=curve(in.vTexCoord); if(any(uv<0.0)||any(uv>1.0)) return float4(0,0,0,1);
    float2 px=p.SourceSize.zw; float3 c=Source.sample(s,uv).rgb; float3 b=(Source.sample(s,uv+px*float2(1.5,0)).rgb+Source.sample(s,uv-px*float2(1.5,0)).rgb+Source.sample(s,uv+px*float2(0,1.5)).rgb+Source.sample(s,uv-px*float2(0,1.5)).rgb)*0.25;
    float scan=sin(uv.y*p.SourceSize.y*3.14159265)*0.5+0.5; c=mix(c,mix(c*0.60,c*1.12,scan),clamp(p.SGScanlineStrength,0.0,1.0));
    float m=fract(in.position.x/3.0); float3 mask=m<0.333?float3(1.12,0.80,0.80):m<0.666?float3(0.80,1.10,0.80):float3(0.82,0.84,1.14);
    c*=mix(float3(1.0),mask,clamp(p.SGMaskStrength,0.0,1.0)); c+=b*smoothstep(0.45,1.0,max(max(b.r,b.g),b.b))*0.14;
    float2 v=uv*(1.0-uv)*15.0; c*=pow(max(v.x*v.y,0.0),0.24); return float4(clamp(c*1.20*p.SGIntensity,0.0,1.0),1.0);
}
