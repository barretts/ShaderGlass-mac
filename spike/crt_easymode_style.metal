//
// crt-easymode-style approximation: clean, lightweight CRT for readable desktop use.
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
    float2 p = uv * 2.0 - 1.0;
    uv = p * (1.0 + dot(p, p) * 0.028) * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 col = Source.sample(Source_sampler, uv).rgb;
    float scan = sin(uv.y * push.SourceSize.y * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.78, 1.04, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    float m = fract(in.position.x / 2.0);
    float3 mask = mix(float3(0.94, 1.02, 0.96), float3(1.04, 0.94, 1.02), step(0.5, m));
    col *= mix(float3(1.0), mask, clamp(push.SGMaskStrength, 0.0, 1.0) * 0.65);
    float vignette = smoothstep(1.45, 0.20, dot(p, p));
    col *= mix(0.82, 1.02, vignette);
    float l = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(l), col, 0.60 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.30);
    return float4(clamp(col * 1.08 * push.SGIntensity, 0.0, 1.0), 1.0);
}
