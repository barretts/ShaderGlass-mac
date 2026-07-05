//
// High-contrast monochrome film look with stable texture, mild halation, and vignette.
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

static float hash21(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 74.7);
    return fract(p.x * p.y);
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]],
                        sampler Source_sampler [[sampler(2)]]) {
    float2 uv = in.vTexCoord;
    float2 px = push.SourceSize.zw;
    float3 src = Source.sample(Source_sampler, uv).rgb;
    float luma = dot(src, float3(0.299, 0.587, 0.114));

    float glow = 0.0;
    glow += dot(Source.sample(Source_sampler, uv + px * float2( 2.0,  0.0)).rgb, float3(0.299, 0.587, 0.114));
    glow += dot(Source.sample(Source_sampler, uv + px * float2(-2.0,  0.0)).rgb, float3(0.299, 0.587, 0.114));
    glow += dot(Source.sample(Source_sampler, uv + px * float2( 0.0,  2.0)).rgb, float3(0.299, 0.587, 0.114));
    glow += dot(Source.sample(Source_sampler, uv + px * float2( 0.0, -2.0)).rgb, float3(0.299, 0.587, 0.114));
    glow *= 0.25;

    float contrast = smoothstep(0.04, 0.96, luma);
    contrast = pow(contrast, 0.72);
    float halation = smoothstep(0.55, 1.0, glow) * 0.16;
    float grain = hash21(floor(in.position.xy)) - 0.5;
    float paper = hash21(floor(in.position.xy * 0.11) + 19.0) - 0.5;
    float2 p = uv * 2.0 - 1.0;
    float vignette = smoothstep(1.65, 0.22, dot(p, p));

    float mono = contrast + halation;
    mono += grain * (0.010 + 0.010 * clamp(push.SGMaskStrength, 0.0, 1.0));
    mono += paper * 0.018;
    mono *= mix(0.72, 1.06, vignette);
    float scan = sin((uv.y * push.OutputSize.y + 0.25) * 3.14159265) * 0.5 + 0.5;
    mono *= mix(1.0, mix(0.88, 1.02, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));

    float warm = clamp(push.SGColorBoost, 0.0, 1.5);
    float3 tint = mix(float3(1.0), float3(1.06, 1.00, 0.92), warm * 0.35);
    return float4(clamp(float3(mono) * tint * push.SGIntensity, 0.0, 1.0), 1.0);
}
