#!/bin/zsh
# M-1 spike build + run. Headless; exits 0 only if passthrough reproduces input.
set -e
cd "$(dirname "$0")"
mkdir -p .logs
SDK="$(xcrun --sdk macosx --show-sdk-path)"   # resolve via xcrun, not a hardcoded path (REVIEW B1)

clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  -framework Metal -framework Foundation \
  main.mm -o spike

./spike passthrough.metal
