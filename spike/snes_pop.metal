//
// Saturated 16-bit console color with light smoothing and readable edges.
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
    soft += Source.sample(Source_sampler, uv + px * float2( 1.0, 0.0)).rgb;
    soft += Source.sample(Source_sampler, uv + px * float2(-1.0, 0.0)).rgb;
    soft += Source.sample(Source_sampler, uv + px * float2( 0.0, 1.0)).rgb;
    soft += Source.sample(Source_sampler, uv + px * float2( 0.0,-1.0)).rgb;
    soft *= 0.2;

    float3 q = floor(clamp(soft, 0.0, 0.999) * 6.0) / 5.0;
    float l = dot(q, float3(0.299, 0.587, 0.114));
    float3 pop = mix(float3(l), q, 1.20 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.18);
    pop = mix(src, pop, 0.62);

    float lx = dot(Source.sample(Source_sampler, uv + float2(px.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float ly = dot(Source.sample(Source_sampler, uv + float2(0.0, px.y)).rgb, float3(0.299, 0.587, 0.114));
    float edge = abs(l - lx) + abs(l - ly);
    pop += float3(0.18, 0.12, 0.32) * edge * (0.18 + 0.12 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float scan = sin((uv.y * push.OutputSize.y + 0.2) * 3.14159265) * 0.5 + 0.5;
    pop *= mix(1.0, mix(0.90, 1.04, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    return float4(clamp(pop * push.SGIntensity, 0.0, 1.0), 1.0);
}
