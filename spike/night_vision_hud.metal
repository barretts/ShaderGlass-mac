//
// Clean night-vision HUD tint with edge enhancement and low noise.
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

static float hash21(float2 p) {
    p = fract(p * float2(61.7, 173.3));
    p += dot(p, p + 23.1);
    return fract(p.x * p.y);
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
    float noise = (hash21(floor(in.position.xy) + float2(push.FrameCount * 0.15, 3.0)) - 0.5) * 0.018;
    float2 p = uv * 2.0 - 1.0;
    float vignette = smoothstep(1.50, 0.18, dot(p, p));
    float3 tint = float3(0.18, 1.0, 0.66);
    float mono = pow(l, 0.82) + edge * (0.70 + 0.35 * clamp(push.SGMaskStrength, 0.0, 1.0)) + noise;
    float3 col = tint * mono;
    col *= mix(0.78, 1.04, vignette);
    col = mix(float3(dot(col, float3(0.3333))), col, 0.45 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.45);
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
