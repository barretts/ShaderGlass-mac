#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

bin="${TMPDIR:-/tmp}/check_m2_shadergen_bin_ntsc"
log=".logs/check-m2-shadergen-ntsc-build.log"
runlog=".logs/check-m2-shadergen-ntsc.log"
preset_def="../ShaderGlass/Shaders/RetroArch/ntsc/NtscNtscAdaptive4xPresetDef.h"
pass1_def="../ShaderGlass/Shaders/RetroArch/crt/shaders/guest/advanced/ntsc/CrtShadersGuestAdvancedNtscNtscPass1ShaderDef.h"
pass2_def="../ShaderGlass/Shaders/RetroArch/crt/shaders/guest/advanced/ntsc/CrtShadersGuestAdvancedNtscNtscPass2ShaderDef.h"
pass3_def="../ShaderGlass/Shaders/RetroArch/crt/shaders/guest/advanced/ntsc/CrtShadersGuestAdvancedNtscNtscPass3ShaderDef.h"

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

"$bin" -force ntsc/ntsc-adaptive-4x.slangp >"$runlog" 2>&1

test -f "$preset_def"
test -f "$pass1_def"
test -f "$pass2_def"
test -f "$pass3_def"
grep -q '35,105,110,99,108,117' "$pass1_def"
grep -q '35,105,110,99,108,117' "$pass2_def"
grep -q '35,105,110,99,108,117' "$pass3_def"
grep -q '.Param("alias", "PrePass0")' "$preset_def"
grep -q '.Param("alias", "NPass1")' "$preset_def"
grep -q '.Param("float_framebuffer", "true")' "$preset_def"
grep -q 'AddSampler("PrePass0", 4);' "$pass3_def"
grep -q 'AddSampler("NPass1", 3);' "$pass3_def"
if grep -q '68,88,66,67' "$pass1_def" || grep -q '68,88,66,67' "$pass2_def" || grep -q '68,88,66,67' "$pass3_def"; then
  echo "FAIL: generated ntsc-adaptive-4x shader headers still appear to contain DXBC magic" >&2
  exit 1
fi

echo "OK: ShaderGen generated ntsc-adaptive-4x preset and pass headers with MSL-shaped payload bytes, aliases, and float-pass metadata"
