//
// Subtle cyan-magenta glow around bright UI edges with preserved source detail.
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
    float3 blur = float3(0.0);
    blur += Source.sample(Source_sampler, uv + px * float2( 1.5,  0.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2(-1.5,  0.0)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 0.0,  1.5)).rgb;
    blur += Source.sample(Source_sampler, uv + px * float2( 0.0, -1.5)).rgb;
    blur *= 0.25;
    float bright = smoothstep(0.55, 1.0, max(max(blur.r, blur.g), blur.b));
    float wave = sin(uv.x * 8.0 + uv.y * 11.0 + float(push.FrameCount) * 0.025) * 0.5 + 0.5;
    float3 plasma = mix(float3(0.0, 0.78, 1.0), float3(1.0, 0.14, 0.78), wave);
    float glow = bright * (0.16 + 0.18 * clamp(push.SGMaskStrength, 0.0, 1.0));
    float3 col = src * 0.94 + plasma * glow;
    float sat = clamp(push.SGColorBoost, 0.0, 1.5);
    col = mix(float3(dot(col, float3(0.299, 0.587, 0.114))), col, 0.78 + sat * 0.14);
    return float4(clamp(col * push.SGIntensity, 0.0, 1.0), 1.0);
}
