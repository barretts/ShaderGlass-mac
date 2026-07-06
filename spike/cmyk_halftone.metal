//
// CMYK halftone overlay that keeps the original image legible.
//
#include <metal_stdlib>
using namespace metal;
struct UBO{float4x4 MVP;}; struct Push{float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;};
struct VSIn{float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]];}; struct VSOut{float4 position [[position]]; float2 vTexCoord;};
vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& u [[buffer(0)]], constant Push& p [[buffer(1)]]){VSOut o; o.position=u.MVP*in.position; o.vTexCoord=in.texcoord; return o;}
fragment float4 fs_main(VSOut in [[stage_in]], constant Push& p [[buffer(1)]], texture2d<float> Source [[texture(2)]], sampler s [[sampler(2)]]) {
    float2 uv=in.vTexCoord;
    float3 base=Source.sample(s,uv).rgb;
    float2 cell=fract(in.position.xy/6.0)-0.5;
    float r=length(cell);
    float l=dot(base,float3(0.299,0.587,0.114));
    float amount = 0.06 + 0.12 * clamp(p.SGMaskStrength, 0.0, 1.0);
    float dotv = 1.0 - smoothstep(0.18 + l * 0.05, 0.46 + l * 0.08, r);
    float3 cmykTint = mix(float3(0.10,0.12,0.16), base, 0.70);
    float3 outc = mix(base, base * (1.0 - amount) + cmykTint * dotv * amount, 0.85);
    return float4(clamp(outc * p.SGIntensity, 0.0, 1.0), 1.0);
}
