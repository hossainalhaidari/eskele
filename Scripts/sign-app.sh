#!/usr/bin/env bash
# Signs Eskele.app from the inside out: Sparkle's helpers, then Sparkle, then the app.
#
#   Scripts/sign-app.sh <Eskele.app> <identity> [codesign options…]
#
# Not `codesign --deep`, which signs everything nested with the outer bundle's options and
# entitlements. Apple's advice, and Sparkle's, is to sign each piece of nested code on its own,
# innermost first. build-app.sh passes no options; package.sh passes --options runtime --timestamp,
# which notarisation requires of every piece here, not only of the app.
set -euo pipefail

APP="$1"
IDENTITY="$2"
shift 2
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

for NESTED in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
	codesign --force --sign "$IDENTITY" "$@" "$NESTED"
done

codesign --force --sign "$IDENTITY" "$@" \
	--entitlements "$ROOT/Resources/Eskele.entitlements" \
	"$APP"
