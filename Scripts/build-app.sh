#!/usr/bin/env bash
# Assembles Kagami.app. SwiftPM produces a bare executable; Sparkle, the icon and the About panel's
# licences only exist for a real bundle.
#
# A release is built with KAGAMI_VERSION and KAGAMI_BUILD set, which the release workflow takes
# from the tag and from the commit count on main. Without them this is a development build: it
# keeps the placeholder version in Resources/Info.plist and has no update feed.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Swift Build, SwiftPM's default backend since Swift 6.4, links through swiftc, which gives clang
# --sysroot rather than -isysroot and no SDKROOT in the environment. clang reads the SDK's version
# from nowhere else, so the binary records its deployment target as its SDK, and the system
# frameworks treat it as built against that old SDK. Handing the linker driver -isysroot restores
# the real one.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
LINK_SDK=(-Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK")

# KAGAMI_BUILD_SYSTEM=native builds the way a toolchain older than Swift 6.4 does, which is how
# to reproduce the release runner's build on a newer Mac.
BUILD_SYSTEM=()
[[ -n "${KAGAMI_BUILD_SYSTEM:-}" ]] && BUILD_SYSTEM=(--build-system "$KAGAMI_BUILD_SYSTEM")

# Build chatter goes to stderr so the caller can capture the bundle path from stdout.
swift build -c "$CONFIG" ${BUILD_SYSTEM[@]+"${BUILD_SYSTEM[@]}"} "${LINK_SDK[@]}" >&2
BIN="$(swift build -c "$CONFIG" ${BUILD_SYSTEM[@]+"${BUILD_SYSTEM[@]}"} --show-bin-path 2>/dev/null)"
APP="$BIN/Kagami.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Kagami" "$APP/Contents/MacOS/Kagami"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Sparkle decides what is newer by CFBundleVersion, so a release's build number has to go up every
# time; the commit count on main does, since main is only ever added to. A development build loses
# its feed instead: the published release always has a higher build number than the placeholder,
# so it would offer to replace itself with it — and with Install Automatically on, would do so
# the next time it quit.
PLIST="$APP/Contents/Info.plist"
if [[ -n "${KAGAMI_VERSION:-}" ]]; then
	: "${KAGAMI_BUILD:?KAGAMI_BUILD must be set with KAGAMI_VERSION}"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $KAGAMI_VERSION" "$PLIST"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $KAGAMI_BUILD" "$PLIST"
else
	/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST"
fi

# Sparkle. SwiftPM links it but, knowing nothing of bundles, leaves it beside the binary, where
# only a binary run from .build finds it. The bundle's copy goes where macOS apps keep theirs, and
# the executable is told to look there.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN/Sparkle.framework" "$SPARKLE"
# Its XPC services exist for sandboxed apps, which Kagami cannot be (it needs raw disk access);
# headers and modules are for compiling against it. None of it runs, and every piece shipped is one
# more to sign and notarise.
for UNUSED in XPCServices Headers PrivateHeaders Modules; do
	rm -rf "${SPARKLE:?}/$UNUSED" "${SPARKLE:?}/Versions/B/$UNUSED"
done
# It warns that this breaks the linker's signature, which is true and fixed by the signing below.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Kagami" 2>/dev/null

# Both icon products ship: Tahoe reads Assets.car (CFBundleIconName) and renders the
# layers as Liquid Glass, everything older reads AppIcon.icns (CFBundleIconFile).
# Scripts/make-icon.sh regenerates them; they are committed so building needs no Xcode.
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/Assets.car"   "$APP/Contents/Resources/Assets.car"

# The licences travel inside the app. Sparkle's MIT terms want its notice in every copy, and so do
# the licences of what Sparkle bundles — bsdiff, sais-lite, ed25519 — which its LICENSE carries
# after its own. The file comes from the same SwiftPM artifact as the framework, so it always
# matches the Sparkle that ships.
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/Kagami.txt"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Licenses/Sparkle.txt"

# Signing identity decides whether macOS treats each rebuild as the same app.
#
# An ad-hoc signature's designated requirement is the binary's own cdhash, so every rebuild is a
# *different application* to macOS. Any real certificate gives a requirement based on the
# identifier and the leaf certificate instead, which survives rebuilding.
#
# Apple Development first. The two kinds make different requirements — Apple Development names the
# certificate, Developer ID the team — so a Mac holding both would otherwise sign with whichever
# `find-identity` happened to list first. Developer ID is the fallback for a machine with nothing
# else, such as the release runner; package.sh re-signs with it either way.
IDENTITY="${KAGAMI_SIGN_IDENTITY:-}"
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
fi

echo "$APP"
