//
// Soft composite/VHS-style shader for video and games.
//

#include <metal_stdlib>
using namespace metal;

struct UBO  { float4x4 MVP; };
struct Push { float4 SourceSize; float4 OriginalSize; float4 OutputSize; uint FrameCount; };

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

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]],
                        sampler Source_sampler [[sampler(2)]]) {
    float2 uv = in.vTexCoord;
    float t = float(push.FrameCount);
    float trackingY = fract(t * 0.0065);
    float lineDist = abs(uv.y - trackingY);
    lineDist = min(lineDist, 1.0 - lineDist);
    float trackingLine = exp(-lineDist * 95.0);
    float lineJitter = (hash21(float2(floor(in.position.y), floor(t * 0.25))) - 0.5) * 0.018;
    float softDrift = sin(uv.y * 18.0 + t * 0.018) * 0.0007;
    float2 wuv = uv + float2(softDrift + lineJitter * trackingLine, 0.0);

    float2 texel = push.SourceSize.zw;
    float3 c0 = Source.sample(Source_sampler, wuv).rgb;
    float3 c1 = Source.sample(Source_sampler, wuv + float2(texel.x * 1.5, 0.0)).rgb;
    float3 c2 = Source.sample(Source_sampler, wuv - float2(texel.x * 1.5, 0.0)).rgb;
    float3 col = mix(c0, (c1 + c2) * 0.5, 0.28);

    float luma = dot(col, float3(0.299, 0.587, 0.114));
    float3 chroma = col - luma;
    col = float3(luma) + chroma * 0.78;

    float noise = hash21(floor(in.position.xy) + float2(t, t * 0.37)) - 0.5;
    float lineNoise = hash21(float2(floor(in.position.x * 0.25), floor(t))) - 0.5;
    float scan = sin((uv.y * push.OutputSize.y + t * 0.08) * 3.14159265) * 0.5 + 0.5;
    col += noise * 0.025;
    col += trackingLine * (0.09 + lineNoise * 0.10);
    col *= 1.0 + trackingLine * 0.12;
    col *= mix(0.91, 1.02, scan);
    col = clamp(col * float3(1.03, 0.99, 0.94), 0.0, 1.0);
    return float4(col, 1.0);
}
