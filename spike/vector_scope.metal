//
// Cyan vector-scope edge emphasis while preserving midtone readability.
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
    float left = dot(Source.sample(Source_sampler, uv - float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float right = dot(Source.sample(Source_sampler, uv + float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float up = dot(Source.sample(Source_sampler, uv - float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114));
    float down = dot(Source.sample(Source_sampler, uv + float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114));
    float edge = length(float2(right - left, down - up));
    float3 base = mix(src, float3(l) * float3(0.40, 0.80, 0.88), 0.38);
    float3 cyan = float3(0.00, 0.95, 1.0);
    float3 col = base * 0.72 + cyan * smoothstep(0.025, 0.22, edge) * (0.42 + 0.35 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float scan = sin((uv.y * push.OutputSize.y + 0.4) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.90, 1.05, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    col = mix(float3(dot(col, float3(0.3333))), col, 0.55 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.30);
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
