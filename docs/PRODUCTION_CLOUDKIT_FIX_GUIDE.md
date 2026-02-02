# Production CloudKit Sync Fix Guide

## The Problem

CloudKit has **two separate environments**:
- **Development** - Used when running from Xcode
- **Production** - Used when installed from TestFlight or App Store

Your schema must be **deployed** to Production, not just downloaded. This is likely why sync works in dev but not in production.

---

## Step 1: Deploy CloudKit Schema to Production

### 1.1 Go to CloudKit Dashboard
1. Open [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
2. Sign in with your Apple Developer account
3. Select your container: `iCloud.com.chenchungwan.LotusPlannerV3`

### 1.2 Check Current Environment
- At the top of the page, you'll see a dropdown: **Development** or **Production**
- Switch between them to see the difference

### 1.3 Deploy Schema from Development → Production
1. Make sure you're viewing the **Development** environment
2. Go to **Schema** section (left sidebar)
3. Look for a button that says **"Deploy Schema Changes"** or **"Deploy to Production"**
4. Click it and follow the prompts
5. This will copy all your record types (CD_Goal, CD_TaskTimeWindow, etc.) to Production

**IMPORTANT**: Downloading the schema to a file does NOT deploy it. You must use the "Deploy to Production" button in the CloudKit Dashboard.

### 1.4 Verify Deployment
1. Switch to **Production** environment in the dropdown
2. Go to **Schema** → **Record Types**
3. Verify you see all these record types:
   - `CD_Goal`
   - `CD_GoalCategory`
   - `CD_WeightLog`
   - `CD_WorkoutLog`
   - `CD_FoodLog`
   - `CD_WaterLog`
   - `CD_SleepLog`
   - `CD_CustomLogItem`
   - `CD_CustomLogEntry`
   - `CD_TaskTimeWindow`

If you don't see these in Production, the schema hasn't been deployed yet.

---

## Step 2: Build and Test with Logging Enabled

I've just updated your code to enable production logging. Now let's build and test:

### 2.1 Build a New Version
```bash
cd /Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3

# Archive for TestFlight/App Store
xcodebuild -project LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -configuration Release \
  archive \
  -archivePath ./LotusPlannerV3.xcarchive

# Export for TestFlight
xcodebuild -exportArchive \
  -archivePath ./LotusPlannerV3.xcarchive \
  -exportPath ./TestFlightExport \
  -exportOptionsPlist ExportOptions.plist
```

### 2.2 Install via TestFlight
1. Upload the build to TestFlight (via App Store Connect)
2. Wait for processing to complete
3. Install on your test device from TestFlight

**Why TestFlight?** Because TestFlight builds use the Production CloudKit environment, same as App Store builds.

---

## Step 3: Enable Verbose Logging in Production

On your test device with the TestFlight build:

1. Open the app
2. Go to **Settings**
3. Under **Diagnostics**, toggle **ON** "Verbose Console Logging"
4. Notice it now shows "Environment: Production"
5. Tap **"Run CloudKit Diagnostics"**

---

## Step 4: Check Logs in Console.app

### 4.1 Connect Device and Open Console
1. Connect your iPhone/iPad via USB to your Mac
2. Open **Console.app** (in /Applications/Utilities/)
3. Select your device in the left sidebar
4. In the search bar, type: `LotusPlannerV3`

### 4.2 Look for These Log Messages

**Good Signs (✅):**
```
✅ iCloud available and signed in
☁️ Persistence: CloudKit container: iCloud.com.chenchungwan.LotusPlannerV3
☁️ Persistence: CloudKit event: import - ✅ Success
✅ Core Data store loaded successfully
```

**Bad Signs (❌):**
```
❌ iCloud access restricted
❌ Core Data Error: Failed to load persistent store
⚠️ Persistence: CloudKit is NOT enabled for this store!
CKError: Account not available
CKError: Zone not found
CKError: Unknown item
```

### 4.3 Common Error Messages and Fixes

| Error Message | Cause | Fix |
|--------------|-------|-----|
| "Zone not found" | Schema not deployed to Production | Deploy schema (Step 1) |
| "Account not available" | User not signed into iCloud | Check Settings → Apple ID |
| "Unknown item" | Record type doesn't exist in Production | Deploy schema (Step 1) |
| "Access restricted" | App doesn't have iCloud permission | Settings → Privacy → Your App → iCloud |

---

## Step 5: Test Sync Between Devices

Once logging looks good:

### 5.1 On Device A (with TestFlight build)
1. Create a new Goal: "Test Sync A"
2. Wait 15-30 seconds
3. Check Console.app for:
   ```
   ☁️ Persistence: CloudKit event: export - ✅ Success
   ```

### 5.2 On Device B (with TestFlight build, same iCloud account)
1. Open the app
2. Go to Settings → iCloud Sync → Tap "Sync Now"
3. Check Console.app for:
   ```
   ☁️ Persistence: CloudKit event: import - ✅ Success
   🔍 DIAGNOSTICS: Found 1 Goal records in CloudKit
   ```
4. Go to Goals view
5. Pull down to refresh
6. "Test Sync A" should appear

---

## Step 6: Verify Production Environment is Actually Being Used

### Add Launch Argument (Optional, for extra verification)
1. In Xcode, go to Product → Scheme → Edit Scheme
2. Run → Arguments → Arguments Passed On Launch
3. Add: `-com.apple.CoreData.CloudKitDebug 1`
4. This will show detailed CloudKit logs

### Check Build Configuration
Run this command to verify your Release build uses Production:
```bash
cd /Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3
xcodebuild -showBuildSettings -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -configuration Release | grep -i "cloudkit\|debug"
```

Expected output should show `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` (NOT "dwarf" alone, which is dev)

---

## Changes I Made to Your Code

### 1. DevLogger.swift
- **Enabled production logging**: Errors and warnings always logged, info/debug logged if verbose enabled
- **Removed `#if DEBUG` blocks**: Logging now works in both dev and production builds
- Production users can enable verbose logging via Settings

### 2. SettingsView.swift
- **Added "Run CloudKit Diagnostics" button**: Logs CloudKit setup to Console.app
- **Added environment indicator**: Shows "Development" or "Production" based on build config
- **Shows CloudKit container ID**: For verification

---

## Troubleshooting

### "I deployed the schema but sync still doesn't work"
- Wait 5-10 minutes after deployment for changes to propagate
- Reset CloudKit data: Settings → Apple ID → iCloud → Manage Storage → Lotus Planner → Delete Data
- Reinstall the app
- Make sure BOTH devices are on the TestFlight build (not one dev, one prod)

### "Console.app doesn't show any logs"
- Make sure "Verbose Console Logging" is ON in Settings
- Make sure you're filtering for "LotusPlannerV3"
- Try clicking "Start" in Console.app toolbar
- Check the search is set to "Any" not "Process"

### "Logs show 'CloudKit is NOT enabled for this store'"
- This means the entitlements aren't being applied
- Verify Xcode → Target → Signing & Capabilities → iCloud is enabled
- Regenerate provisioning profiles in Apple Developer Portal
- Clean build folder: Xcode → Product → Clean Build Folder

### "Still not working after everything"
The nuclear option:
1. CloudKit Dashboard → Production → Admin → "Reset Production Environment"
2. This **deletes ALL production CloudKit data**
3. Only do this if you have no production users yet
4. After reset, redeploy schema
5. Fresh start with clean database

---

## Quick Reference Commands

### View Console Logs on Device
```bash
# Real-time logs from connected device
xcrun devicectl device info logs --device <DEVICE_ID> --filter "LotusPlannerV3"
```

### Build and Archive
```bash
cd /Users/christinechen/Developer/LotusPlannerV3/LotusPlannerV3

# Clean build
xcodebuild clean -project LotusPlannerV3.xcodeproj -scheme LotusPlannerV3 -configuration Release

# Archive
xcodebuild archive \
  -project LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -configuration Release \
  -archivePath ./LotusPlannerV3.xcarchive

# Export for TestFlight
xcodebuild -exportArchive \
  -archivePath ./LotusPlannerV3.xcarchive \
  -exportPath ./TestFlightExport \
  -exportOptionsPlist ExportOptions.plist
```

---

## Summary Checklist

- [ ] Deploy CloudKit schema from Development → Production in CloudKit Dashboard
- [ ] Verify record types exist in Production environment
- [ ] Build new version with updated logging code
- [ ] Upload to TestFlight
- [ ] Install on test device from TestFlight (NOT from Xcode)
- [ ] Enable "Verbose Console Logging" in Settings
- [ ] Run "CloudKit Diagnostics" in Settings
- [ ] Check Console.app for errors
- [ ] Test sync between two devices
- [ ] Verify both devices show same data after sync

---

## Need More Help?

If you've followed all steps and sync still doesn't work, check:
1. Console.app logs - what specific errors appear?
2. CloudKit Dashboard → Production → Data → Browse records - do records appear after creating them?
3. Settings app on device → Apple ID → iCloud → Show All → Is your app listed and enabled?

Share the Console.app logs and I can help diagnose further.
