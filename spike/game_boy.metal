//
// Four-tone green LCD handheld look with a faint pixel grid.
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
    float levels = floor(clamp(l, 0.0, 0.999) * 4.0) / 3.0;

    float3 dark = float3(0.05, 0.16, 0.07);
    float3 mid1 = float3(0.19, 0.38, 0.12);
    float3 mid2 = float3(0.48, 0.62, 0.24);
    float3 light = float3(0.76, 0.82, 0.46);
    float3 col = mix(dark, mid1, step(0.16, levels));
    col = mix(col, mid2, step(0.50, levels));
    col = mix(col, light, step(0.84, levels));

    float2 pix = fract(in.position.xy / 3.0);
    float grid = max(step(0.82, pix.x), step(0.82, pix.y));
    col *= 1.0 - grid * (0.035 + 0.055 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float scan = sin((uv.y * push.OutputSize.y * 0.5 + 0.3) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.92, 1.03, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    col = mix(float3(dot(col, float3(0.3333))), col, 0.55 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.25);
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
