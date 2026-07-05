//
// Blue-white CRT curvature and mask, tuned for readable desktop capture.
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
    float2 off = abs(uv.yx) / float2(6.2, 5.2);
    uv = uv + uv * off * off;
    return uv * 0.5 + 0.5;
}

fragment float4 fs_main(VSOut in [[stage_in]], constant Push& push [[buffer(1)]],
                        texture2d<float> Source [[texture(2)]], sampler Source_sampler [[sampler(2)]]) {
    float2 uv = curve(in.vTexCoord);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return float4(0.0, 0.0, 0.0, 1.0);
    float3 src = Source.sample(Source_sampler, uv).rgb;
    float l = dot(src, float3(0.299, 0.587, 0.114));
    float3 cold = mix(src, float3(l) * float3(0.78, 0.94, 1.20), 0.42);
    float scan = sin(uv.y * push.SourceSize.y * 3.14159265) * 0.5 + 0.5;
    cold *= mix(1.0, mix(0.68, 1.08, scan), clamp(push.SGScanlineStrength, 0.0, 1.0));
    float m = fract(in.position.x / 3.0);
    float3 mask = m < 0.33 ? float3(0.86, 0.96, 1.12) : (m < 0.66 ? float3(0.92, 1.06, 1.05) : float3(1.02, 0.96, 1.14));
    cold *= mix(float3(1.0), mask, clamp(push.SGMaskStrength, 0.0, 1.0));
    float2 v = uv * (1.0 - uv) * 15.0;
    cold *= pow(max(v.x * v.y, 0.0), 0.25);
    cold += float3(0.10, 0.30, 0.55) * smoothstep(0.72, 1.0, l) * clamp(push.SGColorBoost, 0.0, 1.5) * 0.08;
    return float4(clamp(cold * 1.12 * push.SGIntensity, 0.0, 1.0), 1.0);
}
