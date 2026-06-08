#!/bin/zsh
# Build + run the capture-path seam test (CVToMetal + WrapNativeFrame). Headless,
# no screen-recording permission needed. Compiles SCKCapture.mm (incl. the SCStream
# wrapper if ScreenCaptureKit is present) + MetalBackend.mm + the test.
set -e
cd "$(dirname "$0")"
mkdir -p .logs
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

FRAMEWORKS=(-framework Metal -framework QuartzCore -framework Foundation -framework CoreVideo -framework CoreMedia)
# Link ScreenCaptureKit only if present (it is on 12.3+); the .mm guards its use.
if [ -d "$SDK/System/Library/Frameworks/ScreenCaptureKit.framework" ]; then
  FRAMEWORKS+=(-framework ScreenCaptureKit -framework CoreGraphics)
fi

clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  "${FRAMEWORKS[@]}" \
  ../backend/MetalBackend.mm SCKCapture.mm capture_test.mm -o capture_test

./capture_test ../spike/passthrough.metal
