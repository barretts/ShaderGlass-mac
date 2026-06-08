#!/bin/zsh
# Build the live ShaderGlass.app bundle and (optionally) run its headless selftest.
#   ./build.sh           -> build + assemble + sign the .app
#   ./build.sh selftest  -> also run the offscreen golden render
set -e
cd "$(dirname "$0")"
mkdir -p .logs build
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

APP="build/ShaderGlass.app"
BIN="$APP/Contents/MacOS/ShaderGlass"
RES="$APP/Contents/Resources"

# ---- compile ----
SRC=(
  main.mm SGAppDelegate.mm SGMetalView.mm LivePipeline.mm
  ../backend/MetalBackend.mm ../backend/sg_image.mm
  ../capture/SCKCapture.mm
)
FRAMEWORKS=(
  -framework Cocoa -framework Metal -framework QuartzCore
  -framework Foundation -framework CoreVideo -framework CoreMedia
  -framework ScreenCaptureKit -framework CoreGraphics -framework ImageIO
)
mkdir -p "$APP/Contents/MacOS" "$RES"
clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  "${FRAMEWORKS[@]}" \
  "${SRC[@]}" -o "$BIN"

# ---- assemble bundle ----
cp Info.plist "$APP/Contents/Info.plist"
cp ../spike/passthrough.metal ../spike/crt_demo.metal "$RES/"
cp ../../images/screen6.png "$RES/"

# ---- sign: persistent cert if present (grant survives rebuilds), else ad-hoc ----
# Use `-p codesigning` WITHOUT `-v`: a self-signed cert is usable for signing (stable
# cdhash, which is all TCC needs) even though it lists as not-chain-trusted, so it
# never appears under "valid identities only".
if security find-identity -p codesigning 2>/dev/null | grep -q "ShaderGlassDev"; then
  echo "signing with ShaderGlassDev (stable cdhash -> Screen Recording grant survives rebuilds)"
  codesign --force --sign "ShaderGlassDev" "$APP"
else
  echo "ShaderGlassDev cert not found -> ad-hoc sign (Screen Recording grant resets each rebuild)"
  echo "  run ./make-signing-cert.sh once to fix this."
  codesign --force --sign - "$APP"
fi
codesign --verify --verbose=2 "$APP" 2>&1 | tail -2 || echo "WARN: codesign verify reported issues"

echo "built $APP"
if [ "$1" = "selftest" ]; then
  echo "=== selftest (offscreen golden) ==="
  "$BIN" --selftest "$PWD/build/selftest.png"
fi
