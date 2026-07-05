//
// Jungle-night amber/green adventure look with readable highlights.
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

vertex VSOut vs_main(VSIn in [[stage_in]], constant UBO& ubo [[buffer(0)]], constant Push& push [[buffer(1)]]) {
    VSOut o; o.position = ubo.MVP * in.position; o.vTexCoord = in.texcoord; return o;
}

fragment float4 fs_main(VSOut in [[stage_in]], constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]], sampler Source_sampler [[sampler(2)]]) {
    float2 uv = in.vTexCoord;
    float2 px = push.SourceSize.zw;
    float3 src = Source.sample(Source_sampler, uv).rgb;
    float l = dot(src, float3(0.299, 0.587, 0.114));
    float l1 = dot(Source.sample(Source_sampler, uv + float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float l2 = dot(Source.sample(Source_sampler, uv + float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114));
    float edge = abs(l - l1) + abs(l - l2);

    float3 deep = float3(0.02, 0.13, 0.07);
    float3 leaf = float3(0.22, 0.55, 0.18);
    float3 amber = float3(1.00, 0.64, 0.12);
    float3 bone = float3(0.92, 0.84, 0.62);
    float3 col = mix(deep, leaf, smoothstep(0.04, 0.62, l));
    col = mix(col, amber, smoothstep(0.52, 0.86, l) * 0.46);
    col = mix(col, bone, smoothstep(0.82, 1.0, l) * 0.35);
    col = mix(src, col, 0.34 + 0.16 * clamp(push.SGColorBoost, 0.0, 1.5));
    col += amber * edge * (0.35 + 0.28 * clamp(push.SGMaskStrength, 0.0, 1.0));

    float leafShadow = sin(uv.x * 31.0 + sin(uv.y * 17.0) * 2.0 + float(push.FrameCount) * 0.01) * 0.5 + 0.5;
    col *= 1.0 - smoothstep(0.78, 1.0, leafShadow) * 0.045 * clamp(push.SGMaskStrength, 0.0, 1.0);

    float2 p = uv * 2.0 - 1.0;
    float vignette = smoothstep(1.64, 0.18, dot(p, p));
    col *= mix(0.76, 1.03, vignette);
    float scan = sin((uv.y * push.OutputSize.y + 0.4) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.91, 1.04, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));

    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
