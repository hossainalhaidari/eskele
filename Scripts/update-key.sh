#!/usr/bin/env bash
# One-time setup for auto-update: makes the EdDSA key pair Sparkle signs releases with, and writes
# the public half into Resources/Info.plist as SUPublicEDKey.
#
# The private half stays in your login Keychain, under the account "eskele", where Sparkle's
# generate_keys keeps it. Run this again and it finds that key rather than making another — a
# second key would be one that no installed copy trusts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift package resolve >/dev/null
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
ACCOUNT=eskele

# Makes the key, or prints the one already there. Either way macOS may ask to allow Keychain access.
"$TOOLS/generate_keys" --account "$ACCOUNT" >/dev/null
KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
if [[ ! "$KEY" =~ ^[A-Za-z0-9+/=]+$ ]]; then
	echo "error: generate_keys printed something that is not a key: $KEY" >&2
	exit 1
fi

# By substitution rather than PlistBuddy, which would rewrite the file and drop its comments.
perl -0pi -e "s|(<key>SUPublicEDKey</key>\\s*<string>)[^<]*(</string>)|\${1}${KEY}\${2}|" Resources/Info.plist
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)" != "$KEY" ]]; then
	echo "error: could not write SUPublicEDKey into Resources/Info.plist" >&2
	exit 1
fi

cat <<EOF
SUPublicEDKey is $KEY — commit Resources/Info.plist.

The private key is in your login Keychain (account "$ACCOUNT"). Keep a copy somewhere safe, and
give one to the release workflow:

  $TOOLS/generate_keys --account $ACCOUNT -x eskele-update.key
  gh secret set SPARKLE_PRIVATE_KEY --env release < eskele-update.key
  rm -P eskele-update.key

Lose it and installed copies can only be moved to a new key by a release signed with the same
Developer ID as the last one.
EOF
