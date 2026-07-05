//
// M-1 spike: hand-ported MSL for the ShaderGlass "passthrough" shader.
//
// Mirrors ShaderGlass/Shaders/PassthroughShaderDef.h exactly:
//   UBO  (register b0 -> [[buffer(0)]]): row_major float4x4 global_MVP   (64 bytes)
//   Push (register    -> [[buffer(1)]]): SourceSize@0, OriginalSize@16,
//                                        OutputSize@32, FrameCount@48
//   Source texture/sampler at t2/s2 -> [[texture(2)]]/[[sampler(2)]]
//   vertex: TEXCOORD0 float4 position (off 0), TEXCOORD1 float2 uv (off 16), stride 24
//
// MVP equivalence (the M1 gate):
//   HLSL does `mul(Position, row_major global_MVP)` (row vector on the left):
//     result[j] = sum_i Position[i] * m[i][j]
//   The engine uploads the raw row-major `float m[4][4]` bytes via memcpy.
//   Loading those identical bytes into an MSL float4x4 (column-major) makes
//   MSL columns[c] == HLSL row c, so `MVP * Position` computes:
//     result[r] = sum_c columns[c][r] * Position[c] = sum_c m[c][r] * Position[c]
//   which equals the HLSL result. => NO transpose, bytes stay valid as-is.
//

#include <metal_stdlib>
using namespace metal;

struct UBO {
    float4x4 MVP;       // 64 bytes, loaded raw from engine's row-major m[4][4]
};

struct Push {
    float4 SourceSize;   // offset 0
    float4 OriginalSize; // offset 16
    float4 OutputSize;   // offset 32
    uint   FrameCount;   // offset 48
    float  SGIntensity;
    float  SGScanlineStrength;
    float  SGMaskStrength;
    float  SGColorBoost;
};

struct VSIn {
    float4 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float2 vTexCoord;
};

// Geometry buffer pinned to index 30 (plan N2: must not alias UBO=0/Push=1).
vertex VSOut vs_main(VSIn in [[stage_in]],
                     constant UBO&  ubo  [[buffer(0)]],
                     constant Push& push [[buffer(1)]])
{
    VSOut out;
    out.position  = ubo.MVP * in.position;   // == HLSL mul(Position, row_major MVP)
    out.vTexCoord = in.texcoord;
    return out;
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant Push& push [[buffer(1)]],
                        texture2d<float> Source        [[texture(2)]],
                        sampler          Source_sampler [[sampler(2)]])
{
    float3 col = Source.sample(Source_sampler, in.vTexCoord).xyz;
    float line = sin((in.vTexCoord.y * push.OutputSize.y + 0.15) * 3.14159265) * 0.5 + 0.5;
    float phase = fract(in.position.x / 3.0);
    float3 mask = phase < 0.333 ? float3(1.10, 0.88, 0.88) :
                  phase < 0.666 ? float3(0.88, 1.08, 0.88) :
                                  float3(0.88, 0.92, 1.10);
    float luma = dot(col, float3(0.299, 0.587, 0.114));
    float colorMix = clamp(push.SGColorBoost, 0.0, 1.5);
    float maskMix = clamp((push.SGMaskStrength - 0.70) / 0.80, 0.0, 1.0);
    float scanMix = clamp((push.SGScanlineStrength - 0.65) / 0.85, 0.0, 1.0);
    col = mix(float3(luma), col, colorMix);
    col *= mix(float3(1.0), mask, maskMix);
    col *= mix(1.0, mix(0.62, 1.0, line), scanMix);
    col *= push.SGIntensity;
    return float4(clamp(col, 0.0, 1.0), 1.0);
}
