#!/bin/zsh
# M-1 spike build + run. Headless; exits 0 only if passthrough reproduces input.
set -e
cd "$(dirname "$0")"
mkdir -p .logs
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  -framework Metal -framework Foundation \
  main.mm -o spike

./spike passthrough.metal
