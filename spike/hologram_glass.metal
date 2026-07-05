//
// Readable blue hologram sheen with soft horizontal shimmer bands.
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
    float lx = dot(Source.sample(Source_sampler, uv + float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float ly = dot(Source.sample(Source_sampler, uv + float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114));
    float edge = abs(l - lx) + abs(l - ly);
    float band = sin(uv.y * push.OutputSize.y * 0.45 + float(push.FrameCount) * 0.035) * 0.5 + 0.5;
    float sweep = smoothstep(0.92, 1.0, band) * (0.035 + 0.045 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float3 tint = float3(0.15, 0.74, 1.0);
    float3 col = mix(src, src * tint + tint * edge * 0.55, 0.18 + 0.12 * clamp(push.SGColorBoost, 0.0, 1.5));
    col += tint * sweep;
    float scan = sin((uv.y * push.OutputSize.y + 0.2) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.94, 1.03, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
