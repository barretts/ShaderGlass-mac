//
// Readable composite-video look: luma stays crisp while chroma bleeds and phases.
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
    float3 c = Source.sample(Source_sampler, uv).rgb;
    float3 cL = Source.sample(Source_sampler, uv - float2(px.x * 1.5, 0.0)).rgb;
    float3 cR = Source.sample(Source_sampler, uv + float2(px.x * 1.5, 0.0)).rgb;
    float3 cLL = Source.sample(Source_sampler, uv - float2(px.x * 3.0, 0.0)).rgb;
    float3 cRR = Source.sample(Source_sampler, uv + float2(px.x * 3.0, 0.0)).rgb;

    float y = dot(c, float3(0.299, 0.587, 0.114));
    float3 chroma = ((cL + cR) * 0.28 + (cLL + cRR) * 0.11 + c * 0.22);
    float cy = dot(chroma, float3(0.299, 0.587, 0.114));
    float3 color = float3(y) + (chroma - cy) * (0.72 + 0.18 * clamp(push.SGColorBoost, 0.0, 1.5));

    float phase = sin((uv.x * push.SourceSize.x * 0.50 + uv.y * 2.0 + float(push.FrameCount) * 0.08) * 6.2831853);
    color.r += phase * 0.018 * clamp(push.SGMaskStrength, 0.0, 1.0);
    color.b -= phase * 0.014 * clamp(push.SGMaskStrength, 0.0, 1.0);

    float scan = sin((uv.y * push.OutputSize.y + 0.25) * 3.14159265) * 0.5 + 0.5;
    color *= mix(1.0, mix(0.88, 1.03, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    return float4(clamp(color * push.SGIntensity, 0.0, 1.0), 1.0);
}
