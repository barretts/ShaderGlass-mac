//
// LCD subpixel/grid shader for readable desktop use.
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

    float2 cell = fract(in.position.xy / float2(3.0, 3.0));
    float3 sub = cell.x < 0.333 ? float3(1.08, 0.86, 0.86) :
                 cell.x < 0.666 ? float3(0.86, 1.08, 0.86) :
                                  float3(0.86, 0.90, 1.08);
    float grid = (cell.x > 0.90 || cell.y > 0.84) ? 0.72 : 1.0;

    col = pow(col, float3(0.92));
    col *= sub * grid;
    col = clamp(col * 1.06, 0.0, 1.0);
    return float4(col, 1.0);
}
