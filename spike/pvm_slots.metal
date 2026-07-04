//
// PVM-style slot mask, less warped than CRT Pro.
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

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]],
                        sampler Source_sampler [[sampler(2)]]) {
    float2 uv = in.vTexCoord;
    float3 col = Source.sample(Source_sampler, uv).rgb;
    float2 cell = fract(in.position.xy / float2(6.0, 4.0));
    float slot = (cell.y > 0.72 || cell.x > 0.82) ? 0.68 : 1.0;
    float stripe = cell.x < 0.333 ? 1.08 : (cell.x < 0.666 ? 1.02 : 1.10);
    float scan = sin(uv.y * push.SourceSize.y * 3.14159265) * 0.5 + 0.5;
    float3 tint = float3(cell.x < 0.333 ? stripe : 0.84,
                         (cell.x >= 0.333 && cell.x < 0.666) ? stripe : 0.84,
                         cell.x >= 0.666 ? stripe : 0.84);
    col *= tint * slot * mix(0.78, 1.06, scan);
    col = clamp(col * 1.15, 0.0, 1.0);
    return float4(col, 1.0);
}
