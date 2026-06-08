#!/bin/zsh
# One-time: create a persistent self-signed code-signing identity "ShaderGlassDev"
# in the login keychain so the TCC Screen Recording grant survives rebuilds.
# Reversible: delete the "ShaderGlassDev" cert in Keychain Access to undo.
set -e
cd "$(dirname "$0")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
NAME="ShaderGlassDev"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

# Detect with `-p codesigning` WITHOUT `-v`: a self-signed cert is usable for signing
# but never lists under "valid identities only" (it is not chain-trusted). This MUST
# match build.sh's detection or a re-run would duplicate-import (B2).
if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "identity '$NAME' already present — nothing to do"
  exit 0
fi

# Use the SYSTEM openssl (LibreSSL) for both steps: Homebrew OpenSSL 3.x emits a
# PKCS12 MAC that macOS `security import` rejects ("MAC verification failed"), even
# with -legacy. LibreSSL's default p12 imports cleanly.
SSL=/usr/bin/openssl
echo "generating self-signed code-signing cert '$NAME' (using $SSL)..."
"$SSL" req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -nodes -subj "/CN=$NAME" \
  -extensions codesign \
  -config <(printf '[req]\ndistinguished_name=dn\n[dn]\n[codesign]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n')

P12PASS="shaderglass"
"$SSL" pkcs12 -export -out "$WORK/id.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout pass:"$P12PASS"

# Import cert+key, scoped to codesign only via `-T` (NOT `-A`, which would grant EVERY
# app access to the signing key -- over-broad, REVIEW S2). TCC keys on the cdhash, which
# only needs the identity present + usable for signing; chain trust is irrelevant, so we
# deliberately do NOT install a trusted root (REVIEW S1 -- add-trusted-cert -r trustAsRoot
# would expand the user's trust store for no benefit here).
security import "$WORK/id.p12" -k "$LOGIN_KC" -P "$P12PASS" -T /usr/bin/codesign

echo "=== identity now present (lists as not-chain-trusted; that is expected and fine) ==="
security find-identity -p codesigning 2>&1 | grep "$NAME" || \
  echo "WARN: '$NAME' did not import; check the security import output above."

cat <<'NOTE'
Done. build.sh will sign with "ShaderGlassDev" (stable cdhash -> Screen Recording grant
survives rebuilds). If codesign ever prompts for keychain access, run:
  security set-key-partition-list -S apple-tool:,apple: -s -k "<login-password>" "$HOME/Library/Keychains/login.keychain-db"
(scoped to the signing tools -- do NOT re-add -A).
NOTE
