#!/bin/zsh
# Build + run the IRenderBackend conformance test (MetalBackend). Headless.
set -e
cd "$(dirname "$0")"
mkdir -p .logs
SDK="$(xcrun --sdk macosx --show-sdk-path)"   # resolve via xcrun, not a hardcoded path (REVIEW B1)

clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  -framework Metal -framework QuartzCore -framework CoreGraphics -framework Foundation \
  MetalBackend.mm backend_test.mm -o backend_test

./backend_test ../spike/passthrough.metal
