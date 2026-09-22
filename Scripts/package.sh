#!/usr/bin/env bash
# Produces a signed, notarised, stapled Eskele-<version>.dmg in .build.
#
# Requires a Developer ID:
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#
# and one of two ways to reach the notary service. A stored profile, for a Mac of your own:
#   xcrun notarytool store-credentials EskeleNotary \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#   export NOTARY_PROFILE=EskeleNotary
#
# or an App Store Connect API key, which is what the release workflow uses:
#   export NOTARY_KEY=/path/to/AuthKey_XXXXXXXXXX.p8 NOTARY_KEY_ID=XXXXXXXXXX NOTARY_ISSUER=<uuid>
#
# ESKELE_VERSION and ESKELE_BUILD are passed through to build-app.sh. Without them the DMG holds a
# development build, which has no update feed and so never updates itself.
#
# Without a Developer ID it stops before signing rather than producing something undistributable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STAGE="$ROOT/.build/package"
APP_NAME="Eskele"

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"

if [[ -z "${ESKELE_VERSION:-}" ]]; then
	echo "warning: ESKELE_VERSION is unset; packaging a development build that will not update itself." >&2
fi

echo "==> Building ${APP_NAME}"
APP="$(Scripts/build-app.sh release)"
# From the built bundle rather than Resources/Info.plist, which a release overrides.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/.build/${APP_NAME}-${VERSION}.dmg"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
STAGED_APP="$STAGE/${APP_NAME}.app"

echo "==> Signing ${VERSION} with Hardened Runtime"
# --options runtime is what makes the Automation entitlement meaningful, and is required for
# notarisation. --timestamp is likewise mandatory. Both apply to Sparkle's helpers as much as to the
# app, which is why this goes through sign-app.sh rather than one codesign call.
Scripts/sign-app.sh "$STAGED_APP" "$SIGN_IDENTITY" --options runtime --timestamp

codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

echo "==> Building disk image"
rm -f "$DMG"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

if [[ -n "${NOTARY_KEY:-}" ]]; then
	NOTARY_AUTH=(
		--key "$NOTARY_KEY"
		--key-id "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID with NOTARY_KEY}"
		--issuer "${NOTARY_ISSUER:?Set NOTARY_ISSUER with NOTARY_KEY}"
	)
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
	NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
else
	echo "==> Neither NOTARY_PROFILE nor NOTARY_KEY is set — skipping notarisation."
	echo "    $DMG is signed but Gatekeeper will refuse it on other Macs."
	exit 0
fi

echo "==> Notarising (this waits for Apple)"
xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "==> Done: $DMG"
