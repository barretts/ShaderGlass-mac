#!/bin/zsh
# Build the live ShaderGlass.app bundle and (optionally) run its headless selftest.
#   ./build.sh           -> build + assemble + sign the .app
#   ./build.sh selftest  -> also run the offscreen golden render
set -e
cd "$(dirname "$0")"
mkdir -p .logs build
# Resolve the SDK via xcrun rather than hardcoding the Xcode path (survives Xcode
# moves/updates/CLT-only machines; REVIEW B1).
SDK="$(xcrun --sdk macosx --show-sdk-path)"

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
# Clean the bundle first so a partial/interrupted prior sign (e.g. a leftover
# *.cstemp from a concurrent build) can't corrupt the signature of this one.
rm -rf "$APP"
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
# Detect with `-p codesigning` WITHOUT `-v`: a self-signed cert is usable for signing
# (stable cdhash, which is all TCC needs) even though it lists as not-chain-trusted, so
# it never appears under "valid identities only".
#
# The cert's private key is imported scoped to codesign (`-T`, NOT `-A` -- REVIEW S2),
# so on a machine that has not granted codesign keychain access, `codesign --sign
# ShaderGlassDev` BLOCKS on a GUI prompt (it wedges headless builds). We therefore make
# the persistent-cert path OPT-IN via SG_SIGN_CERT=1, and default to ad-hoc (which the
# live app runs fine under -- the cert only buys a TCC grant that survives rebuilds).
#
# To use the cert non-interactively, grant codesign access to the key ONCE:
#   security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
#       -k <login-password> ~/Library/Keychains/login.keychain-db
# then build with: SG_SIGN_CERT=1 ./build.sh
rm -f "$BIN.cstemp"   # clear any leftover from a previously-killed cert-sign attempt
if [ "${SG_SIGN_CERT:-0}" = "1" ] && security find-identity -p codesigning 2>/dev/null | grep -q "ShaderGlassDev"; then
  echo "signing with ShaderGlassDev (stable cdhash -> Screen Recording grant survives rebuilds)"
  codesign --force --sign "ShaderGlassDev" "$APP"
else
  echo "ad-hoc sign (default). For a Screen Recording grant that survives rebuilds: run"
  echo "  ./make-signing-cert.sh, grant codesign keychain access, then SG_SIGN_CERT=1 ./build.sh"
  codesign --force --sign - "$APP"
fi
# Verify the signature and FAIL the build if it is bad. The old `| tail -2 || echo`
# masked failures: in a pipeline $? is tail's (always 0), so a broken signature -- which
# silently resets the TCC grant -- read as success (REVIEW S3). Persist full output to
# .logs/ (non-destructive-logging) and check codesign's own status.
if ! codesign --verify --verbose=2 "$APP" 2>.logs/codesign-verify.log; then
  echo "ERROR: codesign --verify failed:" >&2
  cat .logs/codesign-verify.log >&2
  exit 1
fi

echo "built $APP"
if [ "$1" = "selftest" ]; then
  echo "=== selftest (offscreen golden) ==="
  "$BIN" --selftest "$PWD/build/selftest.png"
fi
