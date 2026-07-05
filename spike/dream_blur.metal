//
// Soft prism blur with subtle animated chromatic drift.
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
    float time = float(push.FrameCount) * 0.017;
    float shimmer = sin(uv.y * 9.0 + time) * 0.5 + cos(uv.x * 7.0 - time * 0.7) * 0.5;
    float spread = 1.25 + 2.5 * clamp(push.SGMaskStrength, 0.0, 1.0);
    float2 drift = px * float2(cos(time + shimmer), sin(time * 0.9 - shimmer)) * spread;

    float3 base = Source.sample(Source_sampler, uv).rgb;
    float3 blur = float3(0.0);
    blur += Source.sample(Source_sampler, uv + px * float2( 1.5,  0.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2(-1.5,  0.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 0.0,  1.5)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 0.0, -1.5)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 2.0,  2.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2(-2.0, -2.0)).rgb;
    blur /= 6.0;

    float r = Source.sample(Source_sampler, uv + drift).r;
    float g = Source.sample(Source_sampler, uv).g;
    float b = Source.sample(Source_sampler, uv - drift).b;
    float3 prism = float3(r, g, b);
    float3 col = mix(base, blur, 0.38);
    col = mix(col, prism, 0.28 + 0.22 * clamp(push.SGColorBoost, 0.0, 1.5) / 1.5);
    float2 p = uv * 2.0 - 1.0;
    col += smoothstep(0.72, 0.0, length(p)) * blur * 0.08;
    col = pow(clamp(col * push.SGIntensity, 0.0, 1.0), float3(0.88));
    float scan = sin((uv.y * push.OutputSize.y + 0.5) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.94, 1.02, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    return float4(clamp(col, 0.0, 1.0), 1.0);
}
