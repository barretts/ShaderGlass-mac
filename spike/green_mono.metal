//
// Green phosphor monochrome shader.
//

#include <metal_stdlib>
using namespace metal;

struct UBO  { float4x4 MVP; };
struct Push {
    float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount;
    float SGIntensity; float SGScanlineStrength; float SGMaskStrength; float SGColorBoost;
};

struct VSIn  { float4 position [[attribute(0)]]; float2 texcoord [[attribute(1)]]; };
struct VSOut { float4 position [[position]]; float2 vTexCoord; };

vertex VSOut vs_main(VSIn in [[stage_in]],
                     constant UBO& ubo [[buffer(0)]],
                     constant Push& push [[buffer(1)]]) {
    VSOut o;
    o.position = ubo.MVP * in.position;
    o.vTexCoord = in.texcoord;
    return o;
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]],
                        sampler Source_sampler [[sampler(2)]]) {
    float2 uv = in.vTexCoord;
    float3 src = Source.sample(Source_sampler, uv).rgb;
    float luma = dot(src, float3(0.299, 0.587, 0.114));
    float scan = sin(uv.y * push.SourceSize.y * 3.14159265) * 0.5 + 0.5;
    float2 p = uv * 2.0 - 1.0;
    float vignette = smoothstep(1.45, 0.15, dot(p, p));
    float3 green = float3(0.18, 1.0, 0.32) * pow(luma, 0.86);
    green += luma * luma * float3(0.02, 0.22, 0.06);
    green *= mix(1.0, mix(0.62, 1.08, scan), clamp(push.SGScanlineStrength, 0.0, 1.0)) * mix(0.68, 1.04, vignette);
    green = mix(float3(dot(green, float3(0.3333))), green, 0.25 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.75);
    return float4(clamp(green * push.SGIntensity, 0.0, 1.0), 1.0);
}
