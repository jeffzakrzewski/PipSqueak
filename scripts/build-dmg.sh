#!/usr/bin/env bash
# Builds PipSqueak.dmg with a drag-to-Applications layout, custom volume icon,
# and a background image with an arrow pointing at the Applications shortcut.
#
# Requires: xcodegen, xcodebuild, hdiutil, sips, iconutil, tiffutil, osascript.
# All ship with macOS / Xcode except xcodegen (`brew install xcodegen`).
#
# Output: dist/PipSqueak-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="PipSqueak"
VOL_NAME="PipSqueak"

BUILD_DIR="$ROOT/build"
DMG_ASSETS="$BUILD_DIR/dmg-assets"
STAGE_DIR="$BUILD_DIR/dmg-stage"
DIST_DIR="$ROOT/dist"
DMG_TMP="$BUILD_DIR/${APP_NAME}-tmp.dmg"
APP_BUILT="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"

# Window size (logical points) — must match the rendered background size in
# scripts/render-assets.swift.
WIN_W=660
WIN_H=440
ICON_Y=220
APP_X=170
APPS_X=490

echo "==> Rendering icon + background assets"
swift "$ROOT/scripts/render-assets.swift"

echo "==> Generating Xcode project"
xcodegen generate

# project.yml is the source of truth for the version; xcodegen writes it into
# Info.plist. Read it now that the plist is fresh.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/$APP_NAME/Info.plist")"
DMG_FINAL="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> Building $APP_NAME ($VERSION) Release"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

[ -d "$APP_BUILT" ] || { echo "Build did not produce $APP_BUILT"; exit 1; }

echo "==> Building VolumeIcon.icns"
ICONSET="$DMG_ASSETS/VolumeIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# iconutil expects this exact set of names.
sips -z 16 16     "$DMG_ASSETS/VolumeIcon-512.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$DMG_ASSETS/VolumeIcon-512.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$DMG_ASSETS/VolumeIcon-512.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$DMG_ASSETS/VolumeIcon-512.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$DMG_ASSETS/VolumeIcon-512.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$DMG_ASSETS/VolumeIcon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$DMG_ASSETS/VolumeIcon-1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$DMG_ASSETS/VolumeIcon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$DMG_ASSETS/VolumeIcon-1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$DMG_ASSETS/VolumeIcon-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$DMG_ASSETS/VolumeIcon.icns"

echo "==> Building combined 1x/2x background TIFF"
tiffutil -cathidpicheck \
  "$DMG_ASSETS/background.png" \
  "$DMG_ASSETS/background@2x.png" \
  -out "$DMG_ASSETS/background.tiff" >/dev/null

echo "==> Staging DMG contents"
# Note: .VolumeIcon.icns is intentionally NOT staged here. Finder's layout
# step deletes hidden files like that during `update without registering
# applications`, so we copy the volume icon onto the mounted DMG *after*
# the AppleScript runs.
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/.background"
cp -R "$APP_BUILT" "$STAGE_DIR/"
cp "$DMG_ASSETS/background.tiff" "$STAGE_DIR/.background/background.tiff"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating writable DMG"
mkdir -p "$DIST_DIR"
rm -f "$DMG_TMP" "$DMG_FINAL"
hdiutil create \
  -srcfolder "$STAGE_DIR" \
  -volname "$VOL_NAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size 96m \
  "$DMG_TMP" >/dev/null

echo "==> Mounting DMG to apply window layout"
MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP")"
DEV_NODE="$(echo "$MOUNT_OUTPUT" | awk '/^\/dev\// {print $1; exit}')"
MOUNT_POINT="/Volumes/$VOL_NAME"

# Give Finder a moment to register the volume.
sleep 2

echo "==> Volume contents after mount:"
ls -la "$MOUNT_POINT/" | sed 's/^/    /'

echo "==> Applying Finder layout"
# Newer Finders reject some legacy properties (toolbar visible, etc.) — wrap
# those in a try block so a single failure doesn't abort the whole layout.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        delay 1
        try
            set current view of container window to icon view
        end try
        try
            set toolbar visible of container window to false
        end try
        try
            set statusbar visible of container window to false
        end try
        try
            set sidebar width of container window to 0
        end try
        set the bounds of container window to {200, 150, 200 + $WIN_W, 150 + $WIN_H}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        try
            set background picture of viewOptions to file ".background:background.tiff"
        end try
        set position of item "$APP_NAME.app" of container window to {$APP_X, $ICON_Y}
        set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

echo "==> Volume contents after layout:"
ls -la "$MOUNT_POINT/" | sed 's/^/    /'

# Finder writes .DS_Store lazily after the window closes. Give it time to
# flush, then verify the file is on disk before we proceed — without it, the
# layout will not survive into the final read-only DMG.
echo "==> Waiting for .DS_Store to flush"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -f "$MOUNT_POINT/.DS_Store" ]; then
        break
    fi
    sleep 1
done
sync
sleep 2

if [ ! -f "$MOUNT_POINT/.DS_Store" ]; then
    echo "WARNING: .DS_Store not present — Finder layout may not have persisted."
fi

# Copy the volume icon onto the DMG now that Finder is done meddling, then
# flag the volume to use a custom icon.
echo "==> Installing volume icon"
cp "$DMG_ASSETS/VolumeIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true

echo "==> Ejecting via Finder (forces flush)"
# Eject via Finder rather than hdiutil so all pending writes land on disk.
osascript -e "tell application \"Finder\" to eject disk \"$VOL_NAME\"" 2>/dev/null || true
# Wait until the device node is actually gone.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! diskutil info "$DEV_NODE" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
# Belt-and-suspenders: if Finder eject didn't take, fall back to hdiutil detach.
if diskutil info "$DEV_NODE" >/dev/null 2>&1; then
    hdiutil detach "$DEV_NODE" >/dev/null || hdiutil detach "$DEV_NODE" -force >/dev/null
fi

echo "==> Converting to compressed read-only DMG"
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" >/dev/null
rm -f "$DMG_TMP"

echo
echo "Done: $DMG_FINAL"
ls -lh "$DMG_FINAL"
