//
// Hand-ported CRT demo shader (M2). Uses the SAME constant layout as passthrough
// (UBO{MVP} at buffer 0, Push{SourceSize,OriginalSize,OutputSize,FrameCount} at
// buffer 1, Source tex/sampler at slot 2) so it drops into the verified pipeline
// with no host changes. Effect: scanlines + RGB-ish mask + barrel curvature +
// vignette -- a recognizable CRT look, not a 1:1 RetroArch port.
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
                     constant UBO&  ubo  [[buffer(0)]],
                     constant Push& push [[buffer(1)]]) {
    VSOut o;
    o.position  = ubo.MVP * in.position;   // row-major-bytes -> column-major: verified no-transpose
    o.vTexCoord = in.texcoord;
    return o;
}

// barrel distortion around center
static float2 curve(float2 uv) {
    uv = uv * 2.0 - 1.0;
    float2 off = abs(uv.yx) / float2(6.0, 5.0);
    uv = uv + uv * off * off;
    return uv * 0.5 + 0.5;
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source        [[texture(2)]],
                        sampler          Source_sampler [[sampler(2)]]) {
    float2 uv = curve(in.vTexCoord);

    // outside the curved screen -> black bezel
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return float4(0.0, 0.0, 0.0, 1.0);

    float3 col = Source.sample(Source_sampler, uv).rgb;

    // scanlines: darken every other source row
    float scan = sin(uv.y * push.SourceSize.y * 3.14159) * 0.5 + 0.5;
    col *= mix(1.0, mix(0.65, 1.0, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));

    // aperture-grille-ish RGB mask by output column
    float m = fract(in.position.x / 3.0);
    float3 mask = float3(m < 0.33 ? 1.0 : 0.7,
                         (m >= 0.33 && m < 0.66) ? 1.0 : 0.7,
                         m >= 0.66 ? 1.0 : 0.7);
    col *= mix(float3(1.0), mask, clamp(push.SGMaskStrength, 0.0, 1.0));

    // vignette
    float2 v = uv * (1.0 - uv) * 15.0;
    col *= pow(v.x * v.y, 0.25);

    // a little gain to offset the darkening
    float luma = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(luma), col, 0.25 + clamp(push.SGColorBoost, 0.0, 1.5) * 0.75);
    col = clamp(col * 1.25 * push.SGIntensity, 0.0, 1.0);
    return float4(col, 1.0);
}
