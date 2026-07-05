#!/bin/zsh
# Build libsgcore.a and run the mac shared-engine resource core test.
set -e
cd "$(dirname "$0")"
mkdir -p .logs build
SDK="$(xcrun --sdk macosx --show-sdk-path)"

./check_m2_shadergen_fixture.sh > .logs/build-core-fixture-gen.log 2>&1
./check_m2_shadergen_pal_singlepass.sh > .logs/build-core-pal-gen.log 2>&1
./check_m2_shadergen_ntsc_adaptive_4x.sh > .logs/build-core-ntsc-gen.log 2>&1
./check_m2_manifest.sh > .logs/build-core-manifest.log 2>&1
./check_m2_shadergen_film_technicolor.sh > .logs/build-core-film-gen.log 2>&1
./check_m2_shadergen_motionblur_mix_frames.sh > .logs/build-core-motionblur-gen.log 2>&1

COMMON_FLAGS=(-std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3
  -isysroot "$SDK"
  -I.. -I../../ShaderGlass -I../../ShaderGC)
FRAMEWORKS=(-framework Metal -framework QuartzCore -framework CoreGraphics -framework Foundation -framework ImageIO)
CORE_SRC=(
  ../backend/MetalBackend.mm
  ../backend/sg_clock.mm
  ../backend/sg_image.mm
  ../../ShaderGlass/Shader.cpp
  ../../ShaderGlass/Texture.cpp
  ../../ShaderGlass/Preset.cpp
  ../../ShaderGlass/ShaderPass.cpp
  ../../ShaderGlass/CursorEmulator.cpp
  ../../ShaderGlass/ShaderGlass.cpp
  SGCoreEngine.mm
)

rm -f build/*.o(N) build/libsgcore.a
for src in "${CORE_SRC[@]}"; do
  obj="build/$(basename "$src").o"
  clang++ "${COMMON_FLAGS[@]}" -c "$src" -o "$obj"
done

ar rcs build/libsgcore.a build/*.o

if nm -u build/libsgcore.a | grep -E '(_D3D|_DXGI|_CreateDXGI|_Direct3D|_Windows|_winrt|_GetTickCount64|_PostMessage|_CreateWindow|_Dwm)' >/dev/null; then
  echo "ERROR: libsgcore.a has Windows/D3D unresolved symbols" >&2
  nm -u build/libsgcore.a | grep -E '(_D3D|_DXGI|_CreateDXGI|_Direct3D|_Windows|_winrt|_GetTickCount64|_PostMessage|_CreateWindow|_Dwm)' >&2
  exit 1
fi

clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  -I.. -I../../ShaderGlass -I../../ShaderGC \
  "${FRAMEWORKS[@]}" \
  core_test.mm build/libsgcore.a -o build/core_test

./build/core_test ../spike/passthrough.metal ../../images/screen6.png build/core_passthrough.png
