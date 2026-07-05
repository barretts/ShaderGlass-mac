//
// Gentle bloom/glow pass for video and bright UI.
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
    float2 px = push.SourceSize.zw;
    float3 c = Source.sample(Source_sampler, uv).rgb;
    float3 blur = float3(0.0);
    blur += Source.sample(Source_sampler, uv + px * float2( 2.0,  0.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2(-2.0,  0.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 0.0,  2.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 0.0, -2.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 1.5,  1.5)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2(-1.5, -1.5)).rgb;
    blur /= 6.0;
    float bright = smoothstep(0.45, 1.0, max(max(blur.r, blur.g), blur.b));
    float3 col = c * 0.92 + blur * bright * (0.16 + 0.18 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float line = sin((uv.y * push.OutputSize.y + 0.15) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.72, 1.0, line), clamp(push.SGScanlineStrength, 0.0, 1.0));
    col = mix(float3(dot(col, float3(0.299, 0.587, 0.114))), col, 0.25 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.75);
    col = pow(clamp(col * push.SGIntensity, 0.0, 1.0), float3(0.92));
    return float4(col, 1.0);
}
