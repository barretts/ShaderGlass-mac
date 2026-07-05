//
// Neon edge glow for UI, terminals, and high-contrast desktop captures.
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

vertex VSOut vs_main(VSIn in [[stage_in]],
                     constant UBO& ubo [[buffer(0)]],
                     constant Push& push [[buffer(1)]]) {
    VSOut o;
    o.position = ubo.MVP * in.position;
    o.vTexCoord = in.texcoord;
    return o;
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]],
                        sampler Source_sampler [[sampler(2)]]) {
    float2 uv = in.vTexCoord;
    float2 px = push.SourceSize.zw;
    float3 c = Source.sample(Source_sampler, uv).rgb;
    float l = dot(c, float3(0.299, 0.587, 0.114));
    float lx1 = dot(Source.sample(Source_sampler, uv + float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float lx2 = dot(Source.sample(Source_sampler, uv - float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float ly1 = dot(Source.sample(Source_sampler, uv + float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114));
    float ly2 = dot(Source.sample(Source_sampler, uv - float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114));
    float edge = length(float2(lx1 - lx2, ly1 - ly2));
    float pulse = sin(float(push.FrameCount) * 0.045 + uv.y * 12.0) * 0.5 + 0.5;
    float3 neonA = float3(0.08, 0.85, 1.00);
    float3 neonB = float3(1.00, 0.08, 0.72);
    float3 neon = mix(neonA, neonB, smoothstep(0.0, 1.0, uv.x + pulse * 0.18));
    float sat = clamp(push.SGColorBoost, 0.0, 1.5);
    float3 base = mix(float3(l), c, 0.48 + sat * 0.34);
    float glow = smoothstep(0.02, 0.28, edge) * (0.55 + 0.55 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float3 col = base * 0.72 + neon * glow;
    float scan = sin((uv.y * push.OutputSize.y + float(push.FrameCount) * 0.06) * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.76, 1.10, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    col += neon * smoothstep(0.92, 1.0, l) * 0.18;
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
