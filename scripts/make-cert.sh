#!/bin/bash
# Creates a STABLE self-signed code-signing identity in a dedicated keychain.
# A stable identity (vs. ad-hoc) keeps the macOS Accessibility permission across
# reinstalls — TCC tracks signed apps by signing identity, not by binary hash.
# Fully non-interactive: the dedicated keychain has its own password, so this
# never prompts for your login password.
set -euo pipefail

IDENTITY="DockSnap Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/docksnap-signing.keychain-db"
KC_PASS="docksnap-local"
P12_PASS="docksnap"

# Already created? Nothing to do. (Use find-certificate, not `find-identity -p
# codesigning`, because a self-signed cert is untrusted and hidden from the
# latter — which would cause duplicate identities and a codesign "ambiguous".)
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Signing identity '$IDENTITY' already exists."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

echo "Generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -config "$WORK/cert.cnf" >/dev/null 2>&1

# Bundle key+cert into a PKCS12 using the legacy SHA1/3DES algorithms that
# macOS's Security framework can import (LibreSSL's modern default fails MAC).
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -name "$IDENTITY" -passout "pass:$P12_PASS" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1

# Dedicated keychain (own password — no login keychain involvement).
if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KC_PASS" "$KEYCHAIN"
fi
security set-keychain-settings "$KEYCHAIN"            # disable auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"

# Import as a single identity; pre-authorize codesign to use the key.
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1

# codesign resolves identities from the user search list — add our keychain
# (preserving the existing entries) so `codesign -s "$IDENTITY"` finds it.
CURRENT=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
if ! echo "$CURRENT" | grep -qF "$KEYCHAIN"; then
    security list-keychains -d user -s "$KEYCHAIN" $CURRENT
fi

echo "Created signing identity '$IDENTITY' in $KEYCHAIN"
