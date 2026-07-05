#!/bin/zsh
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
mac_root=$(cd "$script_dir/.." && pwd)
repo_root=$(cd "$mac_root/.." && pwd)
build_dir="$script_dir/build"
out_bin="$build_dir/check_m2_generate_msl"
fixture="$mac_root/deps/SPIRV-Cross/tests-other/msl_resource_binding.spv"

mkdir -p "$build_dir"

clang++ -std=c++20 \
  -I"$repo_root/ShaderGC" \
  -I"$repo_root/ShaderGC/include" \
  -I"$mac_root/deps/SPIRV-Cross" \
  "$script_dir/check_m2_generate_msl.cpp" \
  "$repo_root/ShaderGC/SPIRV.cpp" \
  "$mac_root/deps/SPIRV-Cross/build/libspirv-cross-core.a" \
  "$mac_root/deps/SPIRV-Cross/build/libspirv-cross-glsl.a" \
  "$mac_root/deps/SPIRV-Cross/build/libspirv-cross-hlsl.a" \
  "$mac_root/deps/SPIRV-Cross/build/libspirv-cross-msl.a" \
  "$mac_root/deps/SPIRV-Cross/build/libspirv-cross-reflect.a" \
  -o "$out_bin"

"$out_bin" "$fixture"
