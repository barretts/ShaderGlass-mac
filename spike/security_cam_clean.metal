//
// Clean blue-gray security camera feel without overlays or text.
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
    float scan = sin((uv.y * push.OutputSize.y * 0.5 + float(push.FrameCount) * 0.015) * 3.14159265) * 0.5 + 0.5;
    float2 p = uv * 2.0 - 1.0;
    float vignette = smoothstep(1.72, 0.22, dot(p, p));
    float3 tint = float3(0.62, 0.78, 0.92);
    float3 col = mix(src, float3(l) * tint, 0.58);
    col *= mix(1.0, mix(0.93, 1.03, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    col *= mix(0.82, 1.02, vignette);
    col += tint * smoothstep(0.78, 1.0, l) * 0.04 * clamp(push.SGColorBoost, 0.0, 1.5);
    col *= 0.98 + 0.04 * clamp(push.SGMaskStrength, 0.0, 1.0);
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
