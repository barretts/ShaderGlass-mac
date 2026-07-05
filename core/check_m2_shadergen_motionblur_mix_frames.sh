#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

bin="${TMPDIR:-/tmp}/check_m2_shadergen_bin_motionblur"
log=".logs/check-m2-shadergen-motionblur-build.log"
runlog=".logs/check-m2-shadergen-motionblur.log"
preset_def="../ShaderGlass/Shaders/RetroArch/motionblur/MotionblurMix_framesPresetDef.h"
shader_def="../ShaderGlass/Shaders/RetroArch/motionblur/shaders/MotionblurShadersMix_framesShaderDef.h"

clang++ -std=c++20 -fdeclspec \
  -I../ShaderGen \
  -I../ShaderGC \
  -I../ShaderGen/include \
  -I../ShaderGC/include \
  ../ShaderGen/ShaderGen.cpp \
  ../ShaderGC/ShaderGC.cpp \
  ../ShaderGC/GLSL.cpp \
  ../ShaderGC/SPIRV.cpp \
  ../ShaderGC/ShaderCache.cpp \
  ../ShaderGC/sha256.cpp \
  deps/SPIRV-Cross/build/libspirv-cross-core.a \
  deps/SPIRV-Cross/build/libspirv-cross-glsl.a \
  deps/SPIRV-Cross/build/libspirv-cross-hlsl.a \
  deps/SPIRV-Cross/build/libspirv-cross-msl.a \
  deps/SPIRV-Cross/build/libspirv-cross-reflect.a \
  deps/glslang/build/glslang/libglslang.a \
  deps/glslang/build/glslang/libMachineIndependent.a \
  deps/glslang/build/glslang/libGenericCodeGen.a \
  deps/glslang/build/glslang/libglslang-default-resource-limits.a \
  deps/glslang/build/glslang/OSDependent/Unix/libOSDependent.a \
  deps/glslang/build/SPIRV/libSPIRV.a \
  deps/glslang/build/SPIRV/libSPVRemapper.a \
  -o "$bin" >"$log" 2>&1

"$bin" -force motionblur/mix_frames.slangp >"$runlog" 2>&1

test -f "$preset_def"
test -f "$shader_def"
grep -q '35,105,110,99,108,117' "$shader_def"
grep -q 'AddSampler("OriginalHistory1", 3);' "$shader_def"
grep -q 'ShaderDefs.push_back(MotionblurShadersMix_framesShaderDef()' "$preset_def"
if grep -q '68,88,66,67' "$shader_def"; then
  echo "FAIL: generated motionblur/mix_frames shader header still appears to contain DXBC magic" >&2
  exit 1
fi

echo "OK: ShaderGen generated motionblur/mix_frames preset and shader headers with MSL-shaped payload bytes and OriginalHistory1 metadata"
