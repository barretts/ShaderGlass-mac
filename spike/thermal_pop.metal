//
// False-color thermal palette driven by source luminance.
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

static float3 palette(float t) {
    float3 cold = float3(0.02, 0.02, 0.18);
    float3 blue = float3(0.00, 0.28, 0.85);
    float3 cyan = float3(0.00, 0.88, 0.95);
    float3 yellow = float3(1.00, 0.88, 0.12);
    float3 hot = float3(1.00, 0.12, 0.02);
    float3 white = float3(1.00, 0.94, 0.78);
    float3 c = mix(cold, blue, smoothstep(0.00, 0.22, t));
    c = mix(c, cyan, smoothstep(0.18, 0.45, t));
    c = mix(c, yellow, smoothstep(0.38, 0.68, t));
    c = mix(c, hot, smoothstep(0.58, 0.84, t));
    c = mix(c, white, smoothstep(0.78, 1.00, t));
    return c;
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]],
                        sampler Source_sampler [[sampler(2)]]) {
    float2 uv = in.vTexCoord;
    float3 src = Source.sample(Source_sampler, uv).rgb;
    float luma = dot(src, float3(0.299, 0.587, 0.114));
    float edges = 0.0;
    float2 px = push.SourceSize.zw;
    edges += abs(luma - dot(Source.sample(Source_sampler, uv + float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114)));
    edges += abs(luma - dot(Source.sample(Source_sampler, uv + float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114)));
    float t = smoothstep(0.02, 0.98, luma);
    t = pow(t, mix(1.15, 0.72, clamp(push.SGColorBoost, 0.0, 1.5) / 1.5));
    float3 col = palette(t);
    col += edges * (0.75 + 0.40 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float line = sin((uv.y * push.OutputSize.y + float(push.FrameCount) * 0.04) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.82, 1.05, line), clamp(push.SGScanlineStrength, 0.0, 1.0));
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
