//
// Curated single-pass CRT shader for the thin macOS live path.
// Same binding contract as passthrough.metal:
// UBO at buffer 0, Push at buffer 1, Source texture/sampler at slot 2.
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

static float2 crtCurve(float2 uv) {
    float2 p = uv * 2.0 - 1.0;
    float2 warp = p.yx * p.yx;
    p += p * warp * float2(0.055, 0.075);
    return p * 0.5 + 0.5;
}

static float3 sampleSharp(texture2d<float> tex, sampler samp, float2 uv, float2 texel) {
    float3 c = tex.sample(samp, uv).rgb;
    float3 l = tex.sample(samp, uv - float2(texel.x, 0.0)).rgb;
    float3 r = tex.sample(samp, uv + float2(texel.x, 0.0)).rgb;
    float3 u = tex.sample(samp, uv - float2(0.0, texel.y)).rgb;
    float3 d = tex.sample(samp, uv + float2(0.0, texel.y)).rgb;
    return clamp(c * 1.55 - (l + r + u + d) * 0.135, 0.0, 1.0);
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]],
                        sampler Source_sampler [[sampler(2)]]) {
    float2 uv = crtCurve(in.vTexCoord);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return float4(0.0, 0.0, 0.0, 1.0);

    float2 texel = push.SourceSize.zw;
    float3 col = sampleSharp(Source, Source_sampler, uv, texel);

    float line = sin((uv.y * push.SourceSize.y + 0.20) * 3.14159265);
    float scan = mix(0.58, 1.06, line * 0.5 + 0.5);

    float phase = fract(in.position.x / 3.0);
    float3 mask = phase < 0.333 ? float3(1.10, 0.78, 0.78) :
                  phase < 0.666 ? float3(0.78, 1.08, 0.78) :
                                  float3(0.78, 0.82, 1.12);

    float2 centered = uv * 2.0 - 1.0;
    float vignette = smoothstep(1.45, 0.22, dot(centered, centered));
    float glow = max(max(col.r, col.g), col.b);

    col = col * mix(float3(1.0), mask, clamp(push.SGMaskStrength, 0.0, 1.0)) *
          mix(1.0, scan, clamp(push.SGScanlineStrength, 0.0, 1.0));
    col += glow * float3(0.045, 0.035, 0.055);
    col *= mix(0.72, 1.03, vignette);
    float luma = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(luma), col, 0.25 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.75);
    col = pow(clamp(col * push.SGIntensity, 0.0, 1.0), float3(0.94));
    return float4(col, 1.0);
}
