//
// ASCII-ish overlay that preserves the original UI instead of replacing it.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord;
    float2 px=p.SourceSize.zw;
    float3 base=Source.sample(s,uv).rgb;
    float2 cellOrigin=floor(in.position.xy/8.0)*8.0;
    float2 suv=cellOrigin/p.OutputSize.xy;
    float3 cellColor=Source.sample(s,suv).rgb;
    float l=dot(cellColor,float3(0.299,0.587,0.114));
    float edge=abs(dot(Source.sample(s,uv+float2(px.x,0)).rgb,float3(0.299,0.587,0.114))-dot(base,float3(0.299,0.587,0.114)))
             + abs(dot(Source.sample(s,uv+float2(0,px.y)).rgb,float3(0.299,0.587,0.114))-dot(base,float3(0.299,0.587,0.114)));
    float2 local=fract(in.position.xy/8.0);
    float glyph=0.0;
    glyph=max(glyph, step(0.72,l) * step(0.20,local.x) * step(local.x,0.80) * step(0.18,local.y) * step(local.y,0.30));
    glyph=max(glyph, step(0.54,l) * step(0.20,local.x) * step(local.x,0.80) * step(0.46,local.y) * step(local.y,0.58));
    glyph=max(glyph, step(0.36,l) * step(0.20,local.x) * step(local.x,0.80) * step(0.74,local.y) * step(local.y,0.86));
    glyph=max(glyph, smoothstep(0.02,0.10,edge) * step(0.44,local.x) * step(local.x,0.56));
    float overlay = glyph * (0.18 + 0.30 * clamp(p.SGMaskStrength, 0.0, 1.0));
    float3 tint = mix(float3(1.0), float3(0.86,0.94,1.0), clamp(p.SGColorBoost,0.0,1.5)*0.35);
    float3 outc = base * (1.0 - overlay * 0.25) + tint * overlay;
    return float4(clamp(outc * p.SGIntensity, 0.0, 1.0), 1.0);
}
