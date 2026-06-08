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

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
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

# Import cert+key; allow codesign to use the key without prompting.
security import "$WORK/id.p12" -k "$LOGIN_KC" -P "$P12PASS" -T /usr/bin/codesign -A

# Trust the cert for code signing (user-level; may pop a Keychain auth dialog once).
security add-trusted-cert -r trustAsRoot -p codeSign -k "$LOGIN_KC" "$WORK/cert.pem" || \
  echo "NOTE: add-trusted-cert needs a one-time Keychain confirmation; if it failed, open Keychain Access, find '$NAME', and set 'Code Signing: Always Trust'."

echo "=== identities now available ==="
security find-identity -v -p codesigning 2>&1 | grep "$NAME" || \
  echo "WARN: '$NAME' not yet listed as valid — trust may need the manual Keychain step above."
