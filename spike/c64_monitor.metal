//
// Commodore-style monitor palette with soft chroma, luma-preserving contrast, scanlines.
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
    float3 blur = src * 0.50;
    blur += Source.sample(Source_sampler, uv - float2(px.x * 1.2, 0.0)).rgb * 0.25;
    blur += Source.sample(Source_sampler, uv + float2(px.x * 1.2, 0.0)).rgb * 0.25;

    float y = dot(src, float3(0.299, 0.587, 0.114));
    float by = dot(blur, float3(0.299, 0.587, 0.114));
    float3 c64 = float3(y) + (blur - by) * 0.74;
    c64 = floor(clamp(c64, 0.0, 0.999) * 8.0) / 7.0;
    c64 = mix(c64, c64 * float3(0.82, 0.92, 1.18) + float3(0.04, 0.02, 0.06), 0.24);
    c64 = mix(src, c64, 0.58 + 0.12 * clamp(push.SGColorBoost, 0.0, 1.5));

    float scan = sin((uv.y * push.OutputSize.y + 0.3) * 3.14159265) * 0.5 + 0.5;
    c64 *= mix(1.0, mix(0.74, 1.05, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    float m = fract(in.position.x / 3.0);
    c64 *= mix(1.0, (m < 0.5 ? 0.94 : 1.04), clamp(push.SGMaskStrength, 0.0, 1.0));
    float2 p = uv * 2.0 - 1.0;
    c64 *= mix(0.84, 1.04, smoothstep(1.55, 0.20, dot(p, p)));
    return float4(clamp(c64 * push.SGIntensity, 0.0, 1.0), 1.0);
}
