#!/bin/bash
set -euo pipefail

# Build script for Claude Sessions
# Creates a proper macOS .app bundle from the Swift Package build

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WIDGET_DIR="$PROJECT_ROOT/widget"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="Claude Sessions"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BUNDLE_ID="com.caiopizzol.claude-sessions"
VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.0.0")
BUILD_NUMBER="1"

echo "Building Claude Sessions..."

# Build the Swift executable
echo "Compiling Swift..."
cd "$WIDGET_DIR"
swift build -c release

# Create app bundle structure
echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$WIDGET_DIR/.build/release/ClaudeSessions" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy hooks to Resources (for installation)
mkdir -p "$APP_BUNDLE/Contents/Resources/hooks"
cp "$PROJECT_ROOT/hooks/"*.sh "$APP_BUNDLE/Contents/Resources/hooks/"

# Copy app icon
cp "$WIDGET_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Claude Sessions needs to control windows to focus your Claude Code terminal sessions.</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code sign (required for app to run on modern macOS)
echo "Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build complete!"
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run: open \"$APP_BUNDLE\""
echo ""
echo "Note: First run may require allowing the app in System Preferences > Privacy & Security."
