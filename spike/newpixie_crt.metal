//
// Newpixie-inspired CRT approximation: chunky pixel structure, glow, softened edges.
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
    float3 soft = src;
    soft += Source.sample(Source_sampler, uv + px * float2( 1.25,  0.0)).rgb;
    soft += Source.sample(Source_sampler, uv + px * float2(-1.25,  0.0)).rgb;
    soft += Source.sample(Source_sampler, uv + px * float2( 0.0,  1.25)).rgb;
    soft += Source.sample(Source_sampler, uv + px * float2( 0.0, -1.25)).rgb;
    soft *= 0.20;

    float2 cell = fract(in.position.xy / 4.0);
    float dotMask = smoothstep(0.15, 0.42, cell.x) * smoothstep(0.85, 0.58, cell.x) *
                    smoothstep(0.12, 0.42, cell.y) * smoothstep(0.88, 0.58, cell.y);
    float scan = sin((uv.y * push.OutputSize.y + 0.1) * 3.14159265) * 0.5 + 0.5;
    float3 col = mix(src, soft, 0.34);
    col *= mix(1.0, 0.78 + dotMask * 0.28, clamp(push.SGMaskStrength, 0.0, 1.0));
    col *= mix(1.0, mix(0.72, 1.06, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    float l = dot(soft, float3(0.299, 0.587, 0.114));
    col += soft * smoothstep(0.48, 1.0, l) * 0.12;
    col = mix(float3(l), col, 0.70 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.22);
    return float4(clamp(col * 1.05 * push.SGIntensity, 0.0, 1.0), 1.0);
}
