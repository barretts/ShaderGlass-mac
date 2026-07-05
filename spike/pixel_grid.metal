//
// Crisp pixel grid with slight integer-cell posterization.
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
    float3 col = Source.sample(Source_sampler, uv).rgb;
    float2 cell = fract(in.position.xy / 4.0);
    float grid = (cell.x > 0.86 || cell.y > 0.86) ? 0.58 : 1.0;
    float3 poster = floor(col * 7.0 + 0.5) / 7.0;
    col = mix(col, poster, 0.30);
    float phase = fract(in.position.x / 3.0);
    float3 mask = phase < 0.333 ? float3(1.10, 0.88, 0.88) :
                  phase < 0.666 ? float3(0.88, 1.08, 0.88) :
                                  float3(0.88, 0.92, 1.10);
    col = pow(col, float3(0.90)) * grid * 1.06;
    col *= mix(float3(1.0), mask, clamp(push.SGMaskStrength, 0.0, 1.0));
    float line = sin((uv.y * push.OutputSize.y + 0.15) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.68, 1.0, line), clamp(push.SGScanlineStrength, 0.0, 1.0));
    col = mix(float3(dot(col, float3(0.299, 0.587, 0.114))), col, 0.25 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.75);
    col *= push.SGIntensity;
    return float4(clamp(col, 0.0, 1.0), 1.0);
}
