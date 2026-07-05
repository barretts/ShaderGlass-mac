//
// Green monochrome phosphor with CRT curvature, slot mask, scanlines, and glow.
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
    uv = uv * 2.0 - 1.0;
    float2 off = abs(uv.yx) / float2(5.9, 4.9);
    uv = uv + uv * off * off;
    return uv * 0.5 + 0.5;
}

fragment float4 fs_main(VSOut in [[stage_in]], constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]], sampler Source_sampler [[sampler(2)]]) {
    float2 uv = curve(in.vTexCoord);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 src = Source.sample(Source_sampler, uv).rgb;
    float luma = dot(src, float3(0.299, 0.587, 0.114));

    float scan = sin(uv.y * push.SourceSize.y * 3.14159265) * 0.5 + 0.5;
    float scanStrength = clamp(push.SGScanlineStrength, 0.0, 1.0);
    float phosphor = mix(1.0, mix(0.58, 1.13, scan), scanStrength);

    float m = fract(in.position.x / 3.0);
    float slot = (m < 0.33) ? 0.84 : ((m < 0.66) ? 1.12 : 0.92);
    float mask = mix(1.0, slot, clamp(push.SGMaskStrength, 0.0, 1.0));

    float2 v = uv * (1.0 - uv) * 15.0;
    float vignette = pow(max(v.x * v.y, 0.0), 0.25);

    float colorBoost = clamp(push.SGColorBoost, 0.0, 1.5);
    float3 green = float3(0.16, 1.0, 0.30) * pow(luma, 0.84);
    green += luma * luma * float3(0.03, 0.30, 0.08);
    green = mix(float3(dot(green, float3(0.3333))), green, 0.38 + colorBoost * 0.55);
    green *= phosphor * mask * vignette;

    float bloom = smoothstep(0.70, 1.0, luma) * 0.12 * scanStrength;
    green += float3(0.10, 0.72, 0.18) * bloom;

    return float4(clamp(green * 1.16 * push.SGIntensity, 0.0, 1.0), 1.0);
}
