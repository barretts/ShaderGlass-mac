#!/bin/zsh
# Build + run the IRenderBackend conformance test (MetalBackend). Headless.
set -e
cd "$(dirname "$0")"
mkdir -p .logs
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  -framework Metal -framework Foundation \
  MetalBackend.mm backend_test.mm -o backend_test

./backend_test ../spike/passthrough.metal
