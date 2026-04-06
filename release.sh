#!/bin/bash

# Fullbright Release Script - For pre-built, signed app
set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

# Configuration
TEAM_ID="3NT3PH4U3S"
SIGNING_IDENTITY="Developer ID Application: Andrei Golli (3NT3PH4U3S)"
SERVER_USER="ubuntu"
SERVER_HOST="51.79.69.34"
SERVER_PATH="/var/www/updates.fullbright.app/html"

# Install sshpass if not present
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass..."
    brew install hudochenkov/sshpass/sshpass
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Fullbright Release Assistant     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════╝${NC}"
echo ""

# Check if Fullbright.app exists in releases directory
if [ ! -d "releases/Fullbright.app" ]; then
    echo -e "${RED}❌ Fullbright.app not found in releases folder!${NC}"
    echo ""
    echo "Instructions:"
    echo "  1. Build and sign your app in Xcode"
    echo "  2. Export it (Archive → Distribute App → Developer ID)"
    echo "  3. Place Fullbright.app in the releases/ directory"
    echo "  4. Run this script again"
    exit 1
fi

echo -e "${GREEN}✓ Found Fullbright.app in releases folder${NC}"

# Get version from the app
PLIST_PATH="releases/Fullbright.app/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST_PATH")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST_PATH")

echo -e "${YELLOW}Version: $VERSION (Build $BUILD)${NC}"
echo ""

# Release notes - use parameter or default
if [ -n "$1" ]; then
    RELEASE_NOTES="$1"
    echo "Using release notes: $1"
else
    RELEASE_NOTES="General bug fixes and improvements"
    echo "Using default release notes: General bug fixes and improvements"
fi

# Create releases directory
mkdir -p releases

# Create DMG with custom background
echo -e "${YELLOW}💿 Creating DMG with custom background...${NC}"

# Create temp directory structure
DMG_TEMP="dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP/.background"

# Copy app and background
cp -R releases/Fullbright.app "$DMG_TEMP/"
if [ -f "scripts/dmg-assets/fullbright-dmg-background.png" ]; then
    cp "scripts/dmg-assets/fullbright-dmg-background.png" "$DMG_TEMP/.background/"
fi

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG with custom settings
DMG_NAME="Fullbright-$VERSION.dmg"
DMG_TEMP_NAME="Fullbright-temp.dmg"

# Clean up any existing temp files
rm -f "$DMG_TEMP_NAME" Fullbright.dmg

# Create initial DMG
hdiutil create -size 50m -volname "Fullbright" -fs HFS+ -fsargs "-c c=64,a=16,e=16" "$DMG_TEMP_NAME"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP_NAME" | grep -E '^/dev/' | awk 'NR==1{print $1}')

# Copy contents to DMG
cp -R "$DMG_TEMP/"* "/Volumes/Fullbright/"
cp -R "$DMG_TEMP/.background" "/Volumes/Fullbright/" 2>/dev/null || true

# Set DMG window properties using AppleScript
echo '
tell application "Finder"
    tell disk "Fullbright"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 920, 440}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set background picture of viewOptions to file ".background:fullbright-dmg-background.png"
        set position of item "Fullbright.app" of container window to {150, 170}
        set position of item "Applications" of container window to {370, 170}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
' | osascript

# Set window properties
sync

# Unmount and convert to compressed DMG
hdiutil detach "$DEVICE" -quiet

# Remove existing DMG if it exists to avoid convert errors
rm -f "releases/$DMG_NAME"

hdiutil convert "$DMG_TEMP_NAME" -format UDZO -imagekey zlib-level=9 -o "releases/$DMG_NAME"
rm -f "$DMG_TEMP_NAME"

# Clean up temp directory
rm -rf "$DMG_TEMP"

# Sign the DMG
echo -e "${YELLOW}✍️  Signing DMG...${NC}"
codesign --force --sign "$SIGNING_IDENTITY" "releases/$DMG_NAME"

# Ask if user wants to notarize the DMG
echo ""
read -p "Notarize the DMG? (recommended for distribution) [y/N]: " NOTARIZE
if [[ $NOTARIZE =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🔐 Notarizing DMG...${NC}"
    echo "You'll need your Apple ID and app-specific password"
    read -p "Apple ID email: " APPLE_ID
    read -s -p "App-specific password: " APP_PASSWORD
    echo ""

    echo "Submitting for notarization..."
    xcrun notarytool submit "releases/$DMG_NAME" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    echo "Stapling notarization..."
    xcrun stapler staple "releases/$DMG_NAME"
    echo -e "${GREEN}✅ DMG notarized and stapled${NC}"
fi

# Create release notes HTML
echo -e "${YELLOW}📝 Creating release notes...${NC}"
cat > "releases/notes-$VERSION.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
        }
        h2 {
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        .version-badge {
            background: #3498db;
            color: white;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 12px;
            margin-left: 10px;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #e0e0e0;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <h2>Fullbright <span class="version-badge">v$VERSION</span></h2>
    <p>$(echo -e "$RELEASE_NOTES" | sed 's/$/\\<br\\>/')</p>
    <div class="footer">
        Released on $(date +"%B %d, %Y")
    </div>
</body>
</html>
EOF

# Generate appcast with signatures
echo -e "${YELLOW}📋 Generating appcast...${NC}"
cd releases
../Fullbright/Fullbright/bin/generate_appcast .

# Fix appcast URLs to include /releases/ path for DMG files
echo "Fixing appcast URLs..."
sed -i '' 's|url="https://updates.fullbright.app/Fullbright-|url="https://updates.fullbright.app/releases/Fullbright-|g' appcast.xml
sed -i '' 's|url="https://updates.fullbright.app/Fullbright|url="https://updates.fullbright.app/releases/Fullbright|g' appcast.xml

cd ..

echo -e "${GREEN}✅ Release package ready!${NC}"
echo ""

# Ask if user wants to deploy
echo "═══════════════════════════════════════"
echo -e "${GREEN}Ready to deploy version $VERSION${NC}"
echo "═══════════════════════════════════════"
echo ""
echo "Files to deploy:"
echo "  • $DMG_NAME ($(du -h releases/$DMG_NAME | awk '{print $1}'))"
echo "  • appcast.xml (with signatures)"
echo "  • Release notes"
echo ""
# Auto-deploy unless --no-deploy flag is passed
if [[ "$*" == *"--no-deploy"* ]]; then
    DEPLOY="n"
    echo "Skipping deployment (--no-deploy flag)"
else
    DEPLOY="y"
    echo "Auto-deploying to https://updates.fullbright.app"
fi

if [[ $DEPLOY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🚀 Deploying to server...${NC}"

    # Create directories on server
    ssh -i ~/.ssh/id_fullbright -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_HOST" "sudo mkdir -p $SERVER_PATH/releases $SERVER_PATH/notes"

    # Upload files to home directory first, then move with sudo
    echo "Uploading DMG..."
    scp -i ~/.ssh/id_fullbright -o StrictHostKeyChecking=no "releases/$DMG_NAME" "$SERVER_USER@$SERVER_HOST:~/"

    echo "Uploading appcast..."
    scp -i ~/.ssh/id_fullbright -o StrictHostKeyChecking=no "releases/appcast.xml" "$SERVER_USER@$SERVER_HOST:~/"

    echo "Uploading release notes..."
    scp -i ~/.ssh/id_fullbright -o StrictHostKeyChecking=no "releases/notes-$VERSION.html" "$SERVER_USER@$SERVER_HOST:~/"

    # Move files to correct locations with proper permissions
    ssh -i ~/.ssh/id_fullbright -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_HOST" "
        sudo mv ~/$DMG_NAME $SERVER_PATH/releases/ && \
        sudo mv ~/appcast.xml $SERVER_PATH/ && \
        sudo mv ~/notes-$VERSION.html $SERVER_PATH/notes/ && \
        sudo chown -R www-data:www-data $SERVER_PATH/ && \
        sudo chmod 644 $SERVER_PATH/appcast.xml $SERVER_PATH/releases/* $SERVER_PATH/notes/*
    "

    # Upload delta updates if any
    if ls releases/*.delta 2>/dev/null; then
        echo "Uploading delta updates..."
        for delta in releases/*.delta; do
            scp -i ~/.ssh/id_fullbright -o StrictHostKeyChecking=no "$delta" "$SERVER_USER@$SERVER_HOST:~/"
            delta_name=$(basename "$delta")
            ssh -i ~/.ssh/id_fullbright -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_HOST" "
                sudo mv ~/$delta_name $SERVER_PATH/releases/ && \
                sudo chown www-data:www-data $SERVER_PATH/releases/$delta_name
            "
        done
    fi

    # Auto clean up local app after successful deployment
    rm -rf releases/Fullbright.app
    echo -e "${YELLOW}✓ Cleaned up releases/Fullbright.app${NC}"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     🎉 Release Complete! 🎉        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Version $VERSION is now live!${NC}"
    echo "Users will automatically receive the update."
    echo ""
else
    echo ""
    echo -e "${YELLOW}Deployment skipped. Files are ready in releases/ folder.${NC}"
    echo "To deploy manually later:"
    echo "  scp releases/$DMG_NAME $SERVER_USER@$SERVER_HOST:$SERVER_PATH/releases/"
    echo "  scp releases/appcast.xml $SERVER_USER@$SERVER_HOST:$SERVER_PATH/"
fi