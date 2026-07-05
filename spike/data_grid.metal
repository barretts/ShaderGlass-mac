//
// Crisp image with a restrained blue-white data grid overlay.
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
    float2 cell = fract(in.position.xy / 32.0);
    float grid = max(1.0 - smoothstep(0.0, 0.055, min(cell.x, 1.0 - cell.x)),
                     1.0 - smoothstep(0.0, 0.055, min(cell.y, 1.0 - cell.y)));
    float major = max(1.0 - smoothstep(0.0, 0.026, min(fract(in.position.x / 128.0), 1.0 - fract(in.position.x / 128.0))),
                      1.0 - smoothstep(0.0, 0.026, min(fract(in.position.y / 128.0), 1.0 - fract(in.position.y / 128.0))));
    float pulse = sin(float(push.FrameCount) * 0.025 + floor(in.position.y / 32.0) * 0.7) * 0.5 + 0.5;
    float alpha = (0.035 + 0.055 * clamp(push.SGMaskStrength, 0.0, 1.0)) * grid + 0.05 * major * pulse;
    float3 gridColor = float3(0.24, 0.74, 1.0);
    float3 col = src * 0.98 + gridColor * alpha;
    float l = dot(src, float3(0.299, 0.587, 0.114));
    col += gridColor * smoothstep(0.78, 1.0, l) * 0.035 * clamp(push.SGColorBoost, 0.0, 1.5);
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
