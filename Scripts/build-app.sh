#!/usr/bin/env bash
# Assembles Eskele.app. SwiftPM produces a bare executable; the agent behaviour we need
# (LSUIElement, a status item, Automation consent) only exists for a real bundle.
#
# A release is built with ESKELE_VERSION and ESKELE_BUILD set, which the release workflow takes
# from the tag and from the commit count on main. Without them this is a development build: it
# keeps the placeholder version in Resources/Info.plist and has no update feed.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Swift Build, SwiftPM's default backend since Swift 6.4, links through swiftc, which gives clang
# --sysroot rather than -isysroot and no SDKROOT in the environment. clang reads the SDK's version
# from nowhere else, so the binary records its deployment target as its SDK (`vtool -show-build`
# says sdk 15.0), and the system frameworks treat it as built against that old SDK. Handing the
# linker driver -isysroot restores the real one.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
LINK_SDK=(-Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK")

# Build chatter goes to stderr so the caller can capture the bundle path from stdout.
swift build -c "$CONFIG" "${LINK_SDK[@]}" >&2
BIN="$(swift build -c "$CONFIG" --show-bin-path 2>/dev/null)"
APP="$BIN/Eskele.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Eskele" "$APP/Contents/MacOS/Eskele"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Sparkle decides what is newer by CFBundleVersion, so a release's build number has to go up every
# time; the commit count on main does, since main is only ever added to. A development build loses
# its feed instead: the published release always has a higher build number than the placeholder,
# so it would offer to replace itself with it — and with Install Automatically on, would do so
# the next time it quit.
PLIST="$APP/Contents/Info.plist"
if [[ -n "${ESKELE_VERSION:-}" ]]; then
	: "${ESKELE_BUILD:?ESKELE_BUILD must be set with ESKELE_VERSION}"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ESKELE_VERSION" "$PLIST"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ESKELE_BUILD" "$PLIST"
else
	/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST"
fi

# Sparkle. SwiftPM links it but, knowing nothing of bundles, leaves it beside the binary, where
# only a binary run from .build finds it. The bundle's copy goes where macOS apps keep theirs, and
# the executable is told to look there.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN/Sparkle.framework" "$SPARKLE"
# Its XPC services exist for sandboxed apps, which Eskele cannot be (ARCHITECTURE.md §9); headers
# and modules are for compiling against it. None of it runs, and every piece shipped is one more
# to sign and notarise.
for UNUSED in XPCServices Headers PrivateHeaders Modules; do
	rm -rf "${SPARKLE:?}/$UNUSED" "${SPARKLE:?}/Versions/B/$UNUSED"
done
# It warns that this breaks the linker's signature, which is true and fixed by the signing below.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Eskele" 2>/dev/null

# Both icon products ship: Tahoe reads Assets.car (CFBundleIconName) and renders the
# layers as Liquid Glass, everything older reads AppIcon.icns (CFBundleIconFile).
# Scripts/make-icon.sh regenerates them; they are committed so building needs no Xcode.
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/Assets.car"   "$APP/Contents/Resources/Assets.car"

# Every language, copied whole. They go straight into Contents/Resources rather than into a SwiftPM
# resource bundle because SwiftUI resolves a `LocalizedStringKey` against `Bundle.main` and nothing
# else: a catalogue anywhere but here would translate the AppKit half of the app and silently leave
# the settings window in English. `defaultLocalization` is not set in Package.swift for the same
# reason — SwiftPM would then build a bundle that nothing reads.
#
# Adding a language means adding a directory; nothing here needs to know its name.
for LPROJ in "$ROOT"/Resources/*.lproj; do
	[[ -d "$LPROJ" ]] || continue
	cp -R "$LPROJ" "$APP/Contents/Resources/"
done

# The licences travel inside the app. Sparkle's MIT terms want its notice in every copy, and so do
# the licences of what Sparkle bundles — bsdiff, sais-lite, ed25519 — which its LICENSE carries
# after its own. The file comes from the same SwiftPM artifact as the framework, so it always
# matches the Sparkle that ships.
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/Eskele.txt"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Licenses/Sparkle.txt"

# Signing identity decides whether macOS remembers this app between builds.
#
# An ad-hoc signature's designated requirement is the binary's own cdhash, so every rebuild is a
# *different application* as far as TCC is concerned — permissions granted in System Settings stop
# applying the moment you rebuild. Any real certificate gives a requirement based on the identifier
# and the leaf certificate instead, which survives rebuilding.
#
# Apple Development first. The two kinds make different requirements — Apple Development names the
# certificate, Developer ID the team — so a Mac holding both would otherwise sign with whichever
# `find-identity` happened to list first, and a build that switched would lose its grants just the
# same. Developer ID is the fallback for a machine with nothing else, such as the release runner;
# package.sh re-signs with it either way.
IDENTITY="${ESKELE_SIGN_IDENTITY:-}"
for KIND in "Apple Development" "Developer ID Application"; do
	[[ -z "$IDENTITY" ]] || break
	IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
		| awk -v kind="\"$KIND:" 'index($0, kind) {print $2; exit}')"
done

if [[ -n "$IDENTITY" ]]; then
	"$ROOT/Scripts/sign-app.sh" "$APP" "$IDENTITY" >/dev/null 2>&1
else
	"$ROOT/Scripts/sign-app.sh" "$APP" - >/dev/null 2>&1
	echo "warning: no signing certificate found; signed ad-hoc." >&2
	echo "         macOS will forget Accessibility and Automation grants on every rebuild." >&2
fi

echo "$APP"
