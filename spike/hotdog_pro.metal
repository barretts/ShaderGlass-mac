//
// Ketchup-and-mustard arcade palette with crisp contrast and light grill lines.
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
    float3 src = Source.sample(Source_sampler, uv).rgb;
    float l = dot(src, float3(0.299, 0.587, 0.114));
    float sat = clamp(push.SGColorBoost, 0.0, 1.5);

    float3 mustard = float3(1.00, 0.78, 0.08);
    float3 ketchup = float3(0.96, 0.08, 0.04);
    float3 bun = float3(1.00, 0.64, 0.30);
    float3 ink = float3(0.16, 0.03, 0.02);
    float3 hot = mix(ink, ketchup, smoothstep(0.08, 0.52, l));
    hot = mix(hot, mustard, smoothstep(0.44, 0.82, l));
    hot = mix(hot, bun, smoothstep(0.78, 1.0, l) * 0.38);
    hot = mix(src, hot, 0.42 + sat * 0.22);

    float stripe = sin((uv.y * push.OutputSize.y * 0.33 + uv.x * 13.0) * 3.14159265) * 0.5 + 0.5;
    float grill = smoothstep(0.88, 1.0, stripe) * (0.035 + 0.045 * clamp(push.SGMaskStrength, 0.0, 1.0));
    hot *= 1.0 - grill;

    float scan = sin((uv.y * push.OutputSize.y + 0.15) * 3.14159265) * 0.5 + 0.5;
    hot *= mix(1.0, mix(0.90, 1.04, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    hot += mustard * smoothstep(0.86, 1.0, l) * 0.04;

    return float4(clamp(hot * push.SGIntensity, 0.0, 1.0), 1.0);
}
