#!/bin/zsh
# Build, gate, sign, package, and describe a private ShaderGlass macOS release.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p .logs dist release

ALLOW_DIRTY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    *)
      echo "usage: $0 [--allow-dirty]" >&2
      exit 2
      ;;
  esac
  shift
done

if [ "${SG_ALLOW_DIRTY_RELEASE:-0}" = "1" ]; then
  ALLOW_DIRTY=1
fi

if [ "$ALLOW_DIRTY" != "1" ] && [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: worktree is dirty; commit or stash changes before running a private release." >&2
  echo "Override only for local verification with --allow-dirty or SG_ALLOW_DIRTY_RELEASE=1." >&2
  exit 1
fi

IDENTITY="${SG_REQUIRE_SIGNING_IDENTITY:-ShaderGlassDev}"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
MAC_ROOT="$PWD"
LOG_DIR="$MAC_ROOT/.logs"
DIST_DIR="$MAC_ROOT/dist"
APP_DIR="$MAC_ROOT/app"
APP_BUNDLE="$APP_DIR/build/ShaderGlass.app"
PACKAGED_APP="$DIST_DIR/ShaderGlass.app"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

rm -rf "$PACKAGED_APP"

run_gate() {
  local name="$1"
  shift
  local log="$LOG_DIR/release-${STAMP}-${name}.log"
  echo "==> $name"
  if ! "$@" >"$log" 2>&1; then
    echo "ERROR: gate '$name' failed. See $log" >&2
    exit 1
  fi
}

run_gate core-build ./core/build_core.sh
run_gate backend-test ./backend/build_test.sh
run_gate capture-test ./capture/build_test.sh
run_gate demo-build ./demo/build.sh
run_gate spike-build ./spike/build.sh
run_gate app-selftest env SG_INSTALL=0 SG_REQUIRE_SIGNING_IDENTITY="$IDENTITY" ./app/build.sh selftest

VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
BUNDLE_ID="$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
MIN_MACOS="$("$PLIST_BUDDY" -c 'Print :LSMinimumSystemVersion' "$APP_BUNDLE/Contents/Info.plist")"
GIT_SHA="$(git rev-parse --short=12 HEAD)"
GIT_SHA_FULL="$(git rev-parse HEAD)"
ARTIFACT_BASENAME="ShaderGlass-mac-${VERSION}-${GIT_SHA}"
ARTIFACT_ZIP="$DIST_DIR/${ARTIFACT_BASENAME}.zip"
MANIFEST_PATH="$DIST_DIR/manifest.json"
CHECKSUMS_PATH="$DIST_DIR/checksums.txt"
RELEASE_NOTES_PATH="$DIST_DIR/release-notes.txt"
DATE_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

rm -f "$ARTIFACT_ZIP" "$MANIFEST_PATH" "$CHECKSUMS_PATH" "$RELEASE_NOTES_PATH"
cp -R "$APP_BUNDLE" "$PACKAGED_APP"
ditto -c -k --keepParent "$PACKAGED_APP" "$ARTIFACT_ZIP"

CODESIGN_VERIFY_LOG="$LOG_DIR/release-${STAMP}-codesign-verify.log"
CODESIGN_DV_LOG="$LOG_DIR/release-${STAMP}-codesign-dv.log"
SPCTL_LOG="$LOG_DIR/release-${STAMP}-spctl.log"

if ! codesign --verify --verbose=2 "$PACKAGED_APP" >"$CODESIGN_VERIFY_LOG" 2>&1; then
  echo "ERROR: packaged app failed codesign verification. See $CODESIGN_VERIFY_LOG" >&2
  exit 1
fi
codesign -dv "$PACKAGED_APP" >"$CODESIGN_DV_LOG" 2>&1 || true
if spctl --assess --type execute "$PACKAGED_APP" >"$SPCTL_LOG" 2>&1; then
  SPCTL_STATUS="accepted"
else
  SPCTL_STATUS="rejected"
fi

ARTIFACT_SHA="$(shasum -a 256 "$ARTIFACT_ZIP" | awk '{print $1}')"
MANIFEST_TMP="$(mktemp "$TMPDIR/shaderglass-manifest.XXXXXX")"
cat >"$MANIFEST_TMP" <<EOF
{
  "schema_version": 1,
  "name": "ShaderGlass",
  "channel": "private",
  "version": "$VERSION",
  "git_sha": "$GIT_SHA_FULL",
  "build_date_utc": "$DATE_ISO",
  "bundle_id": "$BUNDLE_ID",
  "minimum_macos": "$MIN_MACOS",
  "signing_identity": "$IDENTITY",
  "artifact": {
    "path": "dist/${ARTIFACT_BASENAME}.zip",
    "sha256": "$ARTIFACT_SHA"
  },
  "logs": {
    "core_build": ".logs/release-${STAMP}-core-build.log",
    "backend_test": ".logs/release-${STAMP}-backend-test.log",
    "capture_test": ".logs/release-${STAMP}-capture-test.log",
    "demo_build": ".logs/release-${STAMP}-demo-build.log",
    "spike_build": ".logs/release-${STAMP}-spike-build.log",
    "app_selftest": ".logs/release-${STAMP}-app-selftest.log",
    "codesign_verify": ".logs/release-${STAMP}-codesign-verify.log",
    "codesign_dv": ".logs/release-${STAMP}-codesign-dv.log",
    "spctl": ".logs/release-${STAMP}-spctl.log"
  },
  "gate_results": {
    "core_build": "passed",
    "backend_test": "passed",
    "capture_test": "passed",
    "demo_build": "passed",
    "spike_build": "passed",
    "app_selftest": "passed"
  },
  "spctl_status": "$SPCTL_STATUS",
  "notarization": {
    "status": "not_performed"
  }
}
EOF
mv "$MANIFEST_TMP" "$MANIFEST_PATH"

MANIFEST_SHA="$(shasum -a 256 "$MANIFEST_PATH" | awk '{print $1}')"
cat >"$CHECKSUMS_PATH" <<EOF
$ARTIFACT_SHA  $(basename "$ARTIFACT_ZIP")
$MANIFEST_SHA  $(basename "$MANIFEST_PATH")
EOF

cat >"$RELEASE_NOTES_PATH" <<EOF
ShaderGlass private macOS build

Version: $VERSION
Git SHA: $GIT_SHA_FULL
Artifact: $(basename "$ARTIFACT_ZIP")

This is a private signed build for direct tester distribution.
It is not notarized.
Screen Recording permission is still required for live capture paths.
If Gatekeeper or spctl rejects this build, that result is expected for a private self-signed distribution and is recorded in dist/manifest.json.
EOF

echo "private release complete:"
echo "  artifact: $ARTIFACT_ZIP"
echo "  manifest: $MANIFEST_PATH"
echo "  checksums: $CHECKSUMS_PATH"
echo "  notes: $RELEASE_NOTES_PATH"
echo "  spctl: $SPCTL_STATUS (see $SPCTL_LOG)"
