#!/bin/zsh
# Build the visible demo and render passthrough + CRT over a real screenshot.
set -e
cd "$(dirname "$0")"
mkdir -p .logs out
SDK="$(xcrun --sdk macosx --show-sdk-path)"   # resolve via xcrun, not a hardcoded path (REVIEW B1)

clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  -framework Metal -framework QuartzCore -framework Foundation -framework ImageIO -framework CoreGraphics \
  ../backend/MetalBackend.mm ../backend/sg_image.mm demo.mm -o demo

IN="../../images/screen6.png"
# passthrough at native size (proves correct decode + render + readback)
./demo "$IN" ../spike/passthrough.metal out/passthrough.png
# CRT effect, upscaled 2x so scanlines/curvature are visible
./demo "$IN" ../spike/crt_demo.metal out/crt.png 1920 1546
echo "outputs:"; ls -la out/*.png | awk '{print $NF, $5}'
