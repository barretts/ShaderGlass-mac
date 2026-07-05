#!/bin/zsh
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
mac_root=$(cd "$script_dir/.." && pwd)
repo_root=$(cd "$mac_root/.." && pwd)
retro_root="$repo_root/ShaderGlass/Shaders/RetroArch"
commit="a4f3aeec04fcb2624ec6df5dd17e38f9b575eab9"

fail() {
  echo "m2-manifest-check: $*" >&2
  exit 1
}

check_file_contains() {
  local path="$1"
  local pattern="$2"
  if ! /usr/bin/grep -F -q "$pattern" "$path"; then
    fail "missing pattern '$pattern' in $path"
  fi
}

check_count() {
  local path="$1"
  local pattern="$2"
  local expected="$3"
  local actual
  actual=$(/usr/bin/grep -F -c "$pattern" "$path")
  if [[ "$actual" != "$expected" ]]; then
    fail "expected $expected matches for '$pattern' in $path, found $actual"
  fi
}

pal_preset="$retro_root/pal/PalPalSinglepassPresetDef.h"
ntsc_preset="$retro_root/ntsc/NtscNtscAdaptive4xPresetDef.h"
film_preset="$retro_root/film/FilmTechnicolorPresetDef.h"
mix_preset="$retro_root/motionblur/MotionblurMix_framesPresetDef.h"
mix_shader="$retro_root/motionblur/shaders/MotionblurShadersMix_framesShaderDef.h"

for path in "$pal_preset" "$ntsc_preset" "$film_preset" "$mix_preset" "$mix_shader"; do
  [[ -f "$path" ]] || fail "expected file not found: $path"
done

for path in "$pal_preset" "$ntsc_preset" "$film_preset" "$mix_preset"; do
  check_file_contains "$path" "$commit"
done

check_file_contains "$pal_preset" 'ShaderDefs.push_back(PalShadersPalSinglepassShaderDef()'
check_file_contains "$pal_preset" '.Param("scale_type", "source"))'

check_count "$ntsc_preset" 'ShaderDefs.push_back(' 4
check_file_contains "$ntsc_preset" '.Param("alias", "PrePass0")'
check_file_contains "$ntsc_preset" '.Param("alias", "NPass1")'
check_file_contains "$ntsc_preset" '.Param("float_framebuffer", "true")'
check_file_contains "$ntsc_preset" '.Param("wrap_mode", "clamp_to_border")'

check_count "$film_preset" 'TextureDefs.push_back(' 2
check_file_contains "$film_preset" '.Param("name", "SamplerLUT")'
check_file_contains "$film_preset" '.Param("name", "noise1")'

check_file_contains "$mix_preset" 'ShaderDefs.push_back(MotionblurShadersMix_framesShaderDef()'
check_file_contains "$mix_shader" 'AddSampler("OriginalHistory1", 3);'

echo "m2-manifest-check: OK"
echo "  single-pass: pal/pal-singlepass"
echo "  alias+float: ntsc/ntsc-adaptive-4x"
echo "  static-texture: film/technicolor"
echo "  history: motionblur/mix_frames"
