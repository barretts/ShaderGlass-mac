//
// crt-geom-style approximation: stronger curvature, phosphor mask, scanlines, vignette.
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

static float2 curve(float2 uv) {
    float2 p = uv * 2.0 - 1.0;
    float r2 = dot(p, p);
    p *= 1.0 + r2 * 0.075;
    return p * 0.5 + 0.5;
}

fragment float4 fs_main(VSOut in [[stage_in]], constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]], sampler Source_sampler [[sampler(2)]]) {
    float2 uv = curve(in.vTexCoord);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 col = Source.sample(Source_sampler, uv).rgb;
    float scan = sin(uv.y * push.SourceSize.y * 3.14159265) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.60, 1.08, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));

    float slot = fract(in.position.x / 3.0);
    float3 mask = slot < 0.333 ? float3(1.12, 0.82, 0.82) :
                  slot < 0.666 ? float3(0.84, 1.08, 0.84) :
                                  float3(0.86, 0.88, 1.14);
    col *= mix(float3(1.0), mask, clamp(push.SGMaskStrength, 0.0, 1.0));

    float2 v = uv * (1.0 - uv) * 15.0;
    col *= pow(max(v.x * v.y, 0.0), 0.28);
    float l = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(l), col, 0.48 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.40);
    col += smoothstep(0.80, 1.0, l) * 0.04;
    return float4(clamp(col * 1.18 * push.SGIntensity, 0.0, 1.0), 1.0);
}
