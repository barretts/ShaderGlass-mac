#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

bin="${TMPDIR:-/tmp}/check_m2_shadergen_bin_film"
log=".logs/check-m2-shadergen-film-build.log"
runlog=".logs/check-m2-shadergen-film.log"
preset_def="../ShaderGlass/Shaders/RetroArch/film/FilmTechnicolorPresetDef.h"
lut_shader_def="../ShaderGlass/Shaders/RetroArch/reshade/shaders/LUT/ReshadeShadersLUTLUTShaderDef.h"
lut_texture_def="../ShaderGlass/Shaders/RetroArch/reshade/shaders/LUT/ReshadeShadersLUTCmyk16TextureDef.h"
film_shader_def="../ShaderGlass/Shaders/RetroArch/film/shaders/FilmShadersFilm_noiseShaderDef.h"
film_texture_def="../ShaderGlass/Shaders/RetroArch/film/resources/FilmResourcesFilm_noise1TextureDef.h"

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

"$bin" -force film/technicolor.slangp >"$runlog" 2>&1

test -f "$preset_def"
test -f "$lut_shader_def"
test -f "$lut_texture_def"
test -f "$film_shader_def"
test -f "$film_texture_def"
if ! grep -q '35,105,110,99,108,117' "$lut_shader_def" && ! grep -q '35,112,114,97,103,109' "$lut_shader_def"; then
  echo "FAIL: generated film/technicolor LUT shader header did not expose an obvious MSL text marker" >&2
  exit 1
fi
if ! grep -q '35,105,110,99,108,117' "$film_shader_def" && ! grep -q '35,112,114,97,103,109' "$film_shader_def"; then
  echo "FAIL: generated film/technicolor film_noise shader header did not expose an obvious MSL text marker" >&2
  exit 1
fi
grep -q 'TextureDefs.push_back(ReshadeShadersLUTCmyk16TextureDef()' "$preset_def"
grep -q 'TextureDefs.push_back(FilmResourcesFilm_noise1TextureDef()' "$preset_def"
grep -q '.Param("name", "SamplerLUT")' "$preset_def"
grep -q '.Param("name", "noise1")' "$preset_def"
if grep -q '68,88,66,67' "$lut_shader_def" || grep -q '68,88,66,67' "$film_shader_def"; then
  echo "FAIL: generated film/technicolor shader headers still appear to contain DXBC magic" >&2
  exit 1
fi

echo "OK: ShaderGen generated film/technicolor preset, shader, and texture headers with MSL-shaped payload bytes and static-texture metadata"
