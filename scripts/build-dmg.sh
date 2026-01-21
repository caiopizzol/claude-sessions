#!/bin/bash
set -euo pipefail

# Build script for creating a distributable DMG
# Requires: build-app.sh to have been run first

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="Claude Sessions"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="ClaudeSessions"
VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.0.0")
DMG_PATH="$BUILD_DIR/$DMG_NAME-$VERSION.dmg"
DMG_TEMP="$BUILD_DIR/dmg-temp"

# First, build the app
echo "Building app..."
"$SCRIPT_DIR/build-app.sh"

echo ""
echo "Creating DMG..."

# Clean up any previous DMG build
rm -rf "$DMG_TEMP"
rm -f "$DMG_PATH"

# Create temp directory for DMG contents
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create README file
cat > "$DMG_TEMP/README.txt" << 'EOF'
Claude Sessions

Installation:
1. Drag "Claude Sessions" to the Applications folder
2. Open the app from Applications
3. Follow the setup wizard to configure hooks and permissions

First Run:
- The app will guide you through installing jq (if needed)
- It will automatically configure Claude Code hooks
- You'll need to grant Accessibility permission for window focusing

Note: On first launch, macOS may warn about an "unidentified developer".
Right-click the app and select "Open" to bypass this warning.

For more information, visit:
https://github.com/caiopizzol/claude-sessions
EOF

# Calculate size needed (add 10MB buffer)
SIZE_KB=$(du -sk "$DMG_TEMP" | cut -f1)
SIZE_KB=$((SIZE_KB + 10240))

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Clean up
rm -rf "$DMG_TEMP"

echo ""
echo "DMG created successfully!"
echo "Output: $DMG_PATH"
echo ""
echo "To distribute:"
echo "1. Upload to GitHub releases"
echo "2. Users can download, open DMG, and drag app to Applications"
