#!/bin/zsh
# Skerry — a fork of Atoll (DynamicIsland)
# Copyright (C) 2026 amidamaru940 and Skerry contributors
# Licensed under the GNU General Public License v3.0 or later; see LICENSE.
#
# Builds the public release: Skerry.app signed ad-hoc (no Apple Developer
# account needed), packed into Skerry-<version>.dmg with a link to
# Applications, plus its SHA-256. Uses only Xcode and macOS tools.
#
# Usage: scripts/make-release.sh [output folder]   (default: build/release)
#   SKERRY_DERIVED   where Xcode builds (default: build/DerivedData-release)
#   SKERRY_PACKAGES  an already fetched SourcePackages folder, to build offline

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/release}"
DERIVED="${SKERRY_DERIVED:-build/DerivedData-release}"
PACKAGES=()
[[ -n "${SKERRY_PACKAGES:-}" ]] && PACKAGES=(-clonedSourcePackagesDirPath "$SKERRY_PACKAGES" -disableAutomaticPackageResolution)
VERSION="$(tr -d '[:space:]' < VERSION)"
APP_NAME="Skerry"
DMG="$OUT/$APP_NAME-$VERSION.dmg"

mkdir -p "$OUT"
# Source paths end up in the binary's debug info; map them, and strip the
# debug symbols below (their map names every object file in the build
# folder), so the release does not carry the builder's home. The code uses
# #fileID, not #file, for the same reason (tests/test_fork_configuration.py).
ROOT_ABS="$(pwd -P)"
SWIFT_MAP="-file-prefix-map $ROOT_ABS=. -file-prefix-map $HOME=~"
C_MAP="-ffile-prefix-map=$ROOT_ABS=. -ffile-prefix-map=$HOME=~"

echo "Building $APP_NAME $VERSION (Release, ad-hoc signed)…"
# The command line wins over Config/Local.xcconfig: a release is always
# ad-hoc, whatever team this Mac signs its own builds with.
xcodebuild build \
  -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Release \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$DERIVED" "${PACKAGES[@]}" \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual \
  MARKETING_VERSION="$VERSION" ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=debugging \
  OTHER_SWIFT_FLAGS="\$(inherited) $SWIFT_MAP" OTHER_CFLAGS="\$(inherited) $C_MAP" \
  | grep -E "error:|\*\* BUILD" || true

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
SIGNATURE="$(codesign -dv "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Signature=adhoc"* ]] || { echo "Not ad-hoc signed" >&2; exit 1; }
# The released app keeps the app's own entitlements: Apple Events for the
# music players and Notes, and no camera (Skerry has none).
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
[[ "$ENTITLEMENTS" == *"com.apple.security.automation.apple-events"* ]] || { echo "Apple Events entitlement missing" >&2; exit 1; }
[[ "$ENTITLEMENTS" != *"com.apple.security.device.camera"* ]] || { echo "The camera entitlement must not ship" >&2; exit 1; }

# Nothing in the app may name the builder's home folder.
if grep -rlaF "$HOME/" "$APP" >/dev/null; then
  echo "The app still contains paths under $HOME:" >&2
  grep -rlaF "$HOME/" "$APP" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
# Only the file name in the checksum line: it is published next to the DMG.
(cd "$OUT" && shasum -a 256 "${DMG:t}") | tee "$DMG.sha256"
echo "Done: $DMG"
