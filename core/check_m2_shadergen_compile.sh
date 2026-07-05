#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

obj="${TMPDIR:-/tmp}/check_m2_shadergen.o"
log=".logs/check-m2-shadergen-compile.log"

clang++ -std=c++20 -fdeclspec \
  -I../ShaderGen \
  -I../ShaderGC \
  -I../ShaderGen/include \
  -I../ShaderGC/include \
  -c ../ShaderGen/ShaderGen.cpp \
  -o "$obj" >"$log" 2>&1

echo "OK: ShaderGen.cpp compiled to $obj"
