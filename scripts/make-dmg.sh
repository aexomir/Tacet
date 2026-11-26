#!/bin/sh
# Builds Tacet.app (universal) and packs it into dist/Tacet-<version>.dmg.
# Used by the release workflow and for local builds: scripts/make-dmg.sh 0.1.0
set -eu
VERSION="${1:?usage: scripts/make-dmg.sh <version>}"
cd "$(dirname "$0")/.."

ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/Tacet"

rm -rf dist && mkdir -p dist/stage
APP=dist/stage/Tacet.app
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Tacet"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.aexomir.Tacet</string>
    <key>CFBundleName</key><string>Tacet</string>
    <key>CFBundleExecutable</key><string>Tacet</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# shortcut: ad-hoc signature only, so Gatekeeper asks the first time; switch to a Developer ID
# signature plus notarization once there's an Apple Developer account.
codesign --force --sign - "$APP"

ln -s /Applications dist/stage/Applications
hdiutil create -volname Tacet -srcfolder dist/stage -ov -format UDZO "dist/Tacet-$VERSION.dmg"
rm -rf dist/stage
echo "dist/Tacet-$VERSION.dmg"
