#!/bin/zsh
# Builds the Mac App Store package: export, plist fix, re-sign, pkg.
#
#   tools/make_mas_pkg.sh
#
# Output: build/appstore/FlappyJonk-<version>.pkg — drop it in Transporter.
#
# Godot writes the minimum OS into the binary but not into Info.plist;
# App Store validation requires LSMinimumSystemVersion there (409 without
# it). Editing the plist breaks the signature, so the app is re-signed
# with the same identity and entitlements after the fix.
set -e
cd "$(dirname "$0")/.."

APP="build/appstore/Flappy Jonk.app"
IDENTITY="Apple Distribution: Lars-Erik Jonsson (4F49PY7FVQ)"
INSTALLER="3rd Party Mac Developer Installer: Lars-Erik Jonsson (4F49PY7FVQ)"
MIN_OS="11.0"

mkdir -p build/appstore
godot --headless --export-release "macOS" 2>&1 | grep -iE "^error" && exit 1

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_OS" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_OS" "$APP/Contents/Info.plist"
# only exempt encryption (the OS's own HTTPS) — skips the export
# compliance dialog on every upload; Godot sets this on iOS but not macOS
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :ITSAppUsesNonExemptEncryption false" "$APP/Contents/Info.plist"

# re-sign with the entitlements Godot used (plist edits void the signature)
codesign -d --entitlements :- "$APP" > /tmp/mas_entitlements.plist 2>/dev/null
codesign --force --timestamp --options runtime \
  --entitlements /tmp/mas_entitlements.plist --sign "$IDENTITY" "$APP"

PKG="build/appstore/FlappyJonk-$VERSION.pkg"
rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$INSTALLER" "$PKG"

codesign --verify --deep --strict "$APP" && echo "app signature OK"
pkgutil --check-signature "$PKG" | head -2
echo "ready: $PKG"
