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
REQUIRED_SIGN_IDENTITY="${SG_REQUIRE_SIGNING_IDENTITY:-}"
MODE="${1:-build}"
if [ "$MODE" = "selftest" ] && [ -z "${SG_INSTALL+x}" ]; then
  SG_INSTALL=0
fi

# ---- compile ----
SRC=(
  main.mm SGAppDelegate.mm SGMetalView.mm LivePipeline.mm EngineBridge.mm
  ../backend/MetalBackend.mm ../backend/sg_clock.mm ../backend/sg_image.mm
  ../../ShaderGlass/Shader.cpp ../../ShaderGlass/Texture.cpp
  ../../ShaderGlass/Preset.cpp ../../ShaderGlass/ShaderPass.cpp
  ../../ShaderGlass/CursorEmulator.cpp ../../ShaderGlass/ShaderGlass.cpp
  ../capture/SCKCapture.mm
)
FRAMEWORKS=(
  -framework Cocoa -framework Metal -framework QuartzCore
  -framework Foundation -framework CoreVideo -framework CoreMedia
  -framework ScreenCaptureKit -framework CoreGraphics -framework ImageIO
  -framework UniformTypeIdentifiers
)
# Clean the bundle first so a partial/interrupted prior sign (e.g. a leftover
# *.cstemp from a concurrent build) can't corrupt the signature of this one.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
clang++ -std=c++20 -fobjc-arc -arch arm64 -mmacosx-version-min=12.3 \
  -isysroot "$SDK" \
  -I.. -I../../ShaderGlass -I../../ShaderGC \
  "${FRAMEWORKS[@]}" \
  "${SRC[@]}" -o "$BIN"

# ---- assemble bundle ----
cp Info.plist "$APP/Contents/Info.plist"
cp ../spike/passthrough.metal ../spike/crt_demo.metal ../spike/crt_pro.metal "$RES/"
cp ../spike/lcd_grid.metal ../spike/amber_mono.metal ../spike/vhs_soft.metal "$RES/"
cp ../spike/green_mono.metal ../spike/pixel_grid.metal ../spike/bloom_soft.metal "$RES/"
cp ../spike/pvm_slots.metal ../spike/noir_film.metal ../spike/thermal_pop.metal "$RES/"
cp ../spike/dream_blur.metal ../spike/cyber_glow.metal ../spike/amber_crt.metal "$RES/"
cp ../../images/screen6.png "$RES/"
cp Assets/ShaderGlass.icns "$RES/"

# ---- sign: persistent cert if present (grant survives rebuilds), else ad-hoc ----
# Detect with `-p codesigning` WITHOUT `-v`: a self-signed cert is usable for signing
# (stable cdhash, which is all TCC needs) even though it lists as not-chain-trusted, so
# it never appears under "valid identities only".
#
# The cert's private key is imported scoped to codesign (`-T`, NOT `-A` -- REVIEW S2),
# so on a machine that has not granted codesign keychain access, `codesign --sign
# ShaderGlassDev` BLOCKS on a GUI prompt (it would wedge headless builds).
#
# Default is now the persistent cert (stable cdhash -> Screen Recording grant survives
# rebuilds). To stay non-interactive we bound the cert-sign with a timeout when one is
# available: if codesign blocks on a keychain prompt, we kill it and fall back to ad-hoc
# instead of wedging the build. Set SG_SIGN_CERT=0 to force ad-hoc.
#
# To grant codesign access to the key ONCE (so it never prompts again):
#   security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
#       -k <login-password> ~/Library/Keychains/login.keychain-db
rm -f "$BIN.cstemp"   # clear any leftover from a previously-killed cert-sign attempt
# Pick a timeout wrapper if present (homebrew coreutils provides gtimeout); else none.
TIMEOUT_BIN=""
for t in timeout gtimeout; do command -v "$t" >/dev/null 2>&1 && { TIMEOUT_BIN="$t"; break; }; done
sign_adhoc() { echo "ad-hoc sign (grant won't survive rebuilds)"; codesign --force --sign - "$APP"; }
sign_identity() {
  local identity="$1"
  echo "signing with $identity (stable cdhash -> Screen Recording grant survives rebuilds)"
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" 20 codesign --force --sign "$identity" "$APP"
  else
    # No timeout wrapper: cert sign may block on a GUI prompt the first time.
    codesign --force --sign "$identity" "$APP"
  fi
}

if [ -n "$REQUIRED_SIGN_IDENTITY" ]; then
  if [ "${SG_SIGN_CERT:-1}" = "0" ]; then
    echo "ERROR: SG_SIGN_CERT=0 conflicts with required signing identity '$REQUIRED_SIGN_IDENTITY'." >&2
    exit 1
  fi
  if ! security find-identity -p codesigning 2>/dev/null | grep -q "$REQUIRED_SIGN_IDENTITY"; then
    echo "ERROR: required signing identity '$REQUIRED_SIGN_IDENTITY' is not available." >&2
    exit 1
  fi
  if ! sign_identity "$REQUIRED_SIGN_IDENTITY"; then
    echo "ERROR: required signing identity '$REQUIRED_SIGN_IDENTITY' failed or blocked." >&2
    echo "Grant codesign key access once to fix; see header of build.sh." >&2
    exit 1
  fi
elif [ "${SG_SIGN_CERT:-1}" != "0" ] && security find-identity -p codesigning 2>/dev/null | grep -q "ShaderGlassDev"; then
  if ! sign_identity "ShaderGlassDev"; then
    echo "WARN: cert sign failed/blocked (keychain prompt?) -- falling back to ad-hoc." >&2
    echo "  Grant codesign key access once to fix; see header of build.sh." >&2
    sign_adhoc
  fi
else
  [ "${SG_SIGN_CERT:-1}" = "0" ] && echo "ad-hoc sign (SG_SIGN_CERT=0 set)." \
    || echo "ad-hoc sign: no ShaderGlassDev cert. Run ./make-signing-cert.sh for a persistent grant."
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

# ---- install to ~/Applications so Spotlight/cmd-space launches this build ----
# Spotlight only indexes apps in standard locations and does not reliably treat a
# symlink as a launchable app, so we copy. ~/Applications needs no sudo. The copy is
# refreshed every build, so cmd-space always opens the current cert-signed binary.
# Set SG_INSTALL=0 to skip.
if [ "${SG_INSTALL:-1}" != "0" ]; then
  DEST="$HOME/Applications/ShaderGlass.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "installed -> $DEST (cmd-space: \"ShaderGlass\")"
fi

if [ "$MODE" = "selftest" ]; then
  echo "=== selftest (offscreen golden) ==="
  "$BIN" --selftest "$PWD/build/selftest.png"
  echo "=== selftest (split compare) ==="
  "$BIN" --selftest-split "$PWD/build/selftest-split.png"
fi
