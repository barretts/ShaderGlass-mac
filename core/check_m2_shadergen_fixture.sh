#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

bin="${TMPDIR:-/tmp}/check_m2_shadergen_bin"
log=".logs/check-m2-shadergen-fixture-build.log"
runlog=".logs/check-m2-shadergen-fixture.log"
shader_def="../ShaderGlass/Shaders/RetroArch/fixture/FixtureM2LocalShaderDef.h"
preset_def="../ShaderGlass/Shaders/RetroArch/fixture/FixtureM2LocalPresetDef.h"

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

"$bin" -force fixture/m2-local.slangp >"$runlog" 2>&1

test -f "$shader_def"
test -f "$preset_def"
grep -q '35,105,110,99,108,117' "$shader_def"
grep -q 'AddParam("MVP", 0, 0, 64' "$shader_def"
if grep -q '68,88,66,67' "$shader_def"; then
  echo "FAIL: generated shader header still appears to contain DXBC magic" >&2
  exit 1
fi

echo "OK: ShaderGen fixture produced $shader_def and $preset_def with MSL-shaped payload bytes and MVP metadata"
