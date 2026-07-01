#!/usr/bin/env bash
set -euo pipefail

# Build a universal Release AltTab.app, stamp the version, optionally code-sign
# with hardened runtime, then package a compressed .dmg (with an /Applications
# drag-symlink) and a SHA256 file.
#
# Usage: scripts/package-dmg.sh <version>          e.g. 1.1.1
# Optional env:
#   SIGN_IDENTITY  codesigning identity (SHA-1 or common name). If set, the app
#                  is signed with --options runtime before packaging. If empty,
#                  the app is left unsigned (Gatekeeper: right-click -> Open).
#   BUILD_NUMBER   CFBundleVersion value (defaults to a UTC timestamp).

VERSION="${1:?usage: scripts/package-dmg.sh <version>}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/AltTab/AltTab.xcodeproj"
SCHEME="AltTab"
DERIVED="$ROOT/build"
APP="$DERIVED/Build/Products/Release/AltTab.app"
ENTITLEMENTS="$ROOT/AltTab/AltTab/AltTab.entitlements"
DIST="$ROOT/dist"
DMG="$DIST/AltTab-$VERSION.dmg"

echo ">> Building universal Release (arm64 + x86_64)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  clean build

echo ">> Stamping version $VERSION (build $BUILD_NUMBER)..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo ">> Code-signing with hardened runtime ($SIGN_IDENTITY)..."
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo ">> SIGN_IDENTITY not set; leaving app unsigned."
fi

echo ">> Packaging DMG..."
mkdir -p "$DIST"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "AltTab" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo ">> Writing checksum..."
( cd "$DIST" && shasum -a 256 "AltTab-$VERSION.dmg" | tee "AltTab-$VERSION.dmg.sha256" )

echo ">> Architectures:"; lipo -info "$APP/Contents/MacOS/AltTab"
echo ">> Done: $DMG"
