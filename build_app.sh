#!/bin/zsh
set -e

PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"

echo "1. Checking AppIcon.icns..."
if [ ! -f "Assets/AppIcon.icns" ] && [ -f "Assets/source_icon.png" ]; then
    mkdir -p Assets/AppIcon.iconset
    for size in 16 32 128 256 512; do
        sips -z $size $size Assets/source_icon.png --out "Assets/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double Assets/source_icon.png --out "Assets/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
    echo "   -> Generated Assets/AppIcon.icns"
else
    echo "   -> Using existing Assets/AppIcon.icns"
fi

echo "2. Building Swift executable (tranandroi)..."
export PKG_CONFIG_PATH="/opt/homebrew/opt/libmtp/lib/pkgconfig:/opt/homebrew/opt/libusb/lib/pkgconfig:$PKG_CONFIG_PATH"
swift build -c release

echo "3. Creating self-contained macOS App Bundle (tranandroi.app)..."
APP_BUNDLE="$PROJECT_DIR/tranandroi.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp ".build/release/tranandroi" "$APP_BUNDLE/Contents/MacOS/tranandroi"
if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Bundle libmtp and libusb inside tranandroi.app/Contents/Frameworks so other users don't need Homebrew
cp "/opt/homebrew/opt/libmtp/lib/libmtp.9.dylib" "$APP_BUNDLE/Contents/Frameworks/libmtp.9.dylib"
cp "/opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib" "$APP_BUNDLE/Contents/Frameworks/libusb-1.0.0.dylib"
chmod 644 "$APP_BUNDLE/Contents/Frameworks/libmtp.9.dylib" "$APP_BUNDLE/Contents/Frameworks/libusb-1.0.0.dylib"

install_name_tool -id "@executable_path/../Frameworks/libusb-1.0.0.dylib" "$APP_BUNDLE/Contents/Frameworks/libusb-1.0.0.dylib"
install_name_tool -id "@executable_path/../Frameworks/libmtp.9.dylib" "$APP_BUNDLE/Contents/Frameworks/libmtp.9.dylib"
install_name_tool -change "/opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib" "@executable_path/../Frameworks/libusb-1.0.0.dylib" "$APP_BUNDLE/Contents/Frameworks/libmtp.9.dylib"
install_name_tool -change "/opt/homebrew/opt/libmtp/lib/libmtp.9.dylib" "@executable_path/../Frameworks/libmtp.9.dylib" "$APP_BUNDLE/Contents/MacOS/tranandroi"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>tranandroi</string>
    <key>CFBundleExecutable</key>
    <string>tranandroi</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.lamud.tranandroi</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>tranandroi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_BUNDLE"

echo "4. Creating distributable packages (tranandroi-macOS.zip and tranandroi.dmg)..."
rm -f "$PROJECT_DIR/tranandroi-macOS.zip" "$PROJECT_DIR/tranandroi.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$PROJECT_DIR/tranandroi-macOS.zip"

DMG_STAGING="$PROJECT_DIR/.build/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/tranandroi.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "tranandroi" -srcfolder "$DMG_STAGING" -ov -format UDZO "$PROJECT_DIR/tranandroi.dmg" >/dev/null
rm -rf "$DMG_STAGING"

echo "5. Updating /Applications/tranandroi.app..."
rm -rf "/Applications/tranandroi.app"
cp -R "$APP_BUNDLE" "/Applications/tranandroi.app"

echo "Done! Ready to distribute:"
echo "  - $PROJECT_DIR/tranandroi-macOS.zip"
echo "  - $PROJECT_DIR/tranandroi.dmg"
