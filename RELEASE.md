# Fullbright Release Guide

## Quick Start - Creating a Release

### 1. Using VSCode (Recommended)
```bash
# Open VSCode in project directory
code .

# Run the release task:
# Press: Cmd+Shift+P
# Type: "Tasks: Run Task"
# Select: "🚀 Release Fullbright"
```

### 2. Using Terminal
```bash
cd /Users/angolli/Programming/Swift/Fullbright
./scripts/release-local.sh
```

The script will guide you through:
1. **Version Selection** - Keep current, bump patch/minor/major, or custom
2. **Building** - Automatic archive and export with Developer ID
3. **DMG Creation** - Signed disk image
4. **Notarization** (Optional) - Apple verification
5. **Appcast Generation** - With EdDSA signatures and delta updates
6. **Deployment** (Optional) - Upload to your server

## Testing Updates

### Using the Debug Testing Window

1. **Open Testing Window**
   - Run app in Debug mode
   - Click menu bar icon → **Developer** → **Open Sparkle Testing...**

2. **Version Simulation**
   The testing window lets you simulate different app versions without rebuilding:
   - **Quick Versions Menu**: Select preset versions (0.0.1, 0.9.0, etc.)
   - **Custom Version**: Enter any version to simulate
   - **Apply Version**: Makes app appear as that version to Sparkle
   - **Reset to Actual**: Returns to real version

3. **Testing Actions**
   - **Check for Updates**: Triggers visible update check
   - **Check Silently**: Background check (no UI unless update found)
   - **View Appcast**: Shows raw appcast XML from server
   - **Reset Cycle**: Resets update check timer
   - **Clear All Settings**: Wipes all Sparkle preferences

4. **Debug Output**
   Real-time log showing:
   - Version changes
   - Update check results
   - Server status
   - Settings changes
   - Errors and warnings

### Testing Workflow

#### Test Against Production Server
```bash
# 1. Deploy your update to production
./scripts/release-local.sh
# Choose to deploy when prompted

# 2. In Debug app, open Sparkle Testing window

# 3. Simulate an older version:
#    - Click "Quick Versions" → "0.9.0 (Older)"
#    - Or enter custom version and click "Apply Version"

# 4. Check for updates:
#    - Click "Check for Updates"
#    - You should see the update dialog

# 5. View debug output for details
```

#### Test Without Deploying
```bash
# 1. Build release locally (don't deploy)
./scripts/release-local.sh
# Choose 'n' when asked to deploy

# 2. Manually upload just appcast for testing
scp releases/appcast.xml ubuntu@51.79.69.34:/var/www/updates.fullbright.app/html/appcast-test.xml

# 3. Test against test appcast (modify debug window to use appcast-test.xml)
```

## How Users See Updates

### Automatic Update Check (Default)
Users will see this flow:

1. **Background Check** (every 24 hours)
   - App silently checks for updates
   - If found, shows notification

2. **Update Available Dialog**
   ```
   ┌─────────────────────────────────────┐
   │  A new version of Fullbright is     │
   │  available!                         │
   │                                     │
   │  Version 2.0.0 is now available     │
   │  (You have 1.0.0)                   │
   │                                     │
   │  [Release Notes]                    │
   │  • New XDR preset support           │
   │  • Improved performance             │
   │  • Bug fixes                        │
   │                                     │
   │  [Remind Me Later] [Skip] [Install] │
   └─────────────────────────────────────┘
   ```

3. **Download Progress**
   ```
   ┌─────────────────────────────────────┐
   │  Downloading Update...              │
   │  ████████████░░░░░░░  60%           │
   │  3.2 MB of 5.4 MB                   │
   └─────────────────────────────────────┘
   ```

4. **Installation**
   ```
   ┌─────────────────────────────────────┐
   │  Ready to Install                   │
   │                                     │
   │  Fullbright will restart to         │
   │  complete the update.               │
   │                                     │
   │  [Install and Relaunch]             │
   └─────────────────────────────────────┘
   ```

### Manual Update Check
Users can also check manually:
1. Click menu bar icon
2. Click **"Check for Updates..."**
3. Same flow as above

### Developer Menu (Debug builds only)
For testing, the Developer menu shows:
- Open Sparkle Testing window
- Simulate update available
- Reset all settings

## Step-by-Step First Release

### 1. Prepare Your First Release
```bash
# Ensure you're in the project directory
cd /Users/angolli/Programming/Swift/Fullbright

# Check your current version
grep MARKETING_VERSION Fullbright/Fullbright.xcodeproj/project.pbxproj

# Run the release script
./scripts/release-local.sh
```

### 2. Script Prompts You'll See

**Version Selection:**
```
Current version: 1.0.0 (1)

Do you want to update the version?
1) Keep current version (1.0.0)
2) Bump patch version → 1.0.1
3) Bump minor version → 1.1.0
4) Bump major version → 2.0.0
5) Enter custom version
Choice [1-5]: 2
```

**Notarization (Optional):**
```
Do you want to notarize the DMG? (requires Apple ID)
Notarize? [y/N]: y
Apple ID: your@email.com
[Enter app-specific password when prompted]
```

**Deployment:**
```
Deploy to update server at 51.79.69.34?
Deploy? [y/N]: y
```

### 3. Verify Deployment
```bash
# Check if appcast is live
curl -I https://updates.fullbright.app/appcast.xml

# View appcast content
curl https://updates.fullbright.app/appcast.xml
```

## Common Scenarios

### Releasing a Bug Fix
```bash
# Quick patch release
./scripts/release-local.sh
# Choose option 2 (bump patch) → 1.0.1
# Skip notarization for faster release
# Deploy to server
```

### Major Update with Release Notes
1. Create release notes file:
```html
<!-- releases/notes-2.0.0.html -->
<h2>Fullbright 2.0</h2>
<ul>
  <li><b>New:</b> Multiple XDR presets</li>
  <li><b>New:</b> Keyboard shortcuts</li>
  <li><b>Improved:</b> 50% faster switching</li>
  <li><b>Fixed:</b> Memory leak on sleep</li>
</ul>
```

2. Run release:
```bash
./scripts/release-local.sh
# Choose option 4 (major version)
# Include notarization for major release
# Deploy
```

### Testing Before Production
```bash
# 1. Build test version locally
./scripts/release-local.sh
# Don't deploy yet

# 2. Start local test server
./scripts/test-local-update.sh

# 3. Test with older app version
# 4. If all good, deploy:
./scripts/deploy.sh releases/Fullbright-2.0.0.dmg 2.0.0
```

## Update Server Status

### Check Server Health
```bash
# VSCode: Cmd+Shift+P → "🌐 Check Update Server"

# Or manually:
curl -I https://updates.fullbright.app/appcast.xml

# Check what's deployed:
ssh ubuntu@51.79.69.34 "ls -la /var/www/updates.fullbright.app/html/releases/"
```

### View Release History
```bash
# VSCode: Cmd+Shift+P → "📊 View Release History"

# Or manually:
ls -lah releases/
```

## Troubleshooting

### Update Not Showing
1. **Check version numbers:**
   ```bash
   # Your current app version
   grep MARKETING_VERSION Fullbright/Fullbright.xcodeproj/project.pbxproj

   # Version in appcast
   curl -s https://updates.fullbright.app/appcast.xml | grep sparkle:version
   ```

2. **Clear Sparkle cache (in app):**
   - Menu → Developer → Reset All Sparkle Settings

3. **Force check:**
   - Menu → Check for Updates...

### Notarization Issues
```bash
# If notarization fails, check status:
xcrun notarytool history --apple-id your@email.com

# Get details on specific submission:
xcrun notarytool log [submission-id] --apple-id your@email.com
```

### Server Connection Issues
```bash
# Test SSH connection
ssh ubuntu@51.79.69.34 "echo 'Connected successfully'"

# Check nginx status
ssh ubuntu@51.79.69.34 "sudo systemctl status nginx"
```

## Security Checklist

Before each release:
- [ ] Version number is higher than current
- [ ] DMG is code-signed
- [ ] EdDSA signature generated (automatic)
- [ ] HTTPS certificate valid
- [ ] Test update works locally first

## Quick Commands Reference

```bash
# Release new version
./scripts/release-local.sh

# Test updates locally
./scripts/test-local-update.sh

# Check deployed version
curl https://updates.fullbright.app/appcast.xml | grep sparkle:version

# View your EdDSA public key
./Fullbright/Fullbright/bin/generate_keys

# Sign update manually (if needed)
./Fullbright/Fullbright/bin/sign_update releases/Fullbright-1.0.0.dmg

# SSH to server
ssh ubuntu@51.79.69.34

# View server logs
ssh ubuntu@51.79.69.34 "tail -f /var/log/nginx/updates.access.log"
```

## Update Feed URL

Your production appcast is at:
```
https://updates.fullbright.app/appcast.xml
```

This is already configured in your app's Info.plist.