# TestFlight Setup Guide - iCloud Sync Testing

## Overview
This guide will help you set up TestFlight testing specifically to diagnose and fix iCloud sync issues in production builds. TestFlight builds use the **Production** CloudKit environment, which is separate from the Development environment used during local testing.

---

## Part 1: Pre-Flight Checklist

### 1. Verify CloudKit Schema is Deployed to Production

**Why:** Development builds use the Development CloudKit environment, but TestFlight/App Store builds use Production. The schema MUST be deployed to Production for sync to work.

**Steps:**
1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
2. Sign in with your Apple Developer account
3. Select container: `iCloud.com.chenchungwan.LotusPlannerV3`
4. Check the environment dropdown (top right) - switch to **Production**
5. Go to **Schema** section
6. Verify these record types exist in Production:
   - `CD_Goal`
   - `CD_GoalCategory`
   - `CD_WeightLog`
   - `CD_WorkoutLog`
   - `CD_FoodLog`
   - `CD_WaterLog`
   - `CD_CustomLogItem`
   - `CD_CustomLogEntry`
   - `CD_TaskTimeWindow`
   - `CD_SleepLog`

**If record types are missing in Production:**
1. Switch environment to **Development**
2. Go to **Schema** section
3. Click **Deploy Schema Changes**
4. Select: Deploy from **Development** → **Production**
5. Confirm deployment (this can take 5-10 minutes)

### 2. Verify Entitlements

Your entitlements file looks correct. It should contain:
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.chenchungwan.LotusPlannerV3</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
    <string>CloudDocuments</string>
</array>
```

✅ Your file at `LotusPlannerV3/LotusPlannerV3/LotusPlannerV3.entitlements` is correct.

### 3. Verify App ID Capabilities

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to: **Certificates, Identifiers & Profiles** → **Identifiers**
3. Select your App ID: `com.chenchungwan.LotusPlannerV3`
4. Ensure these capabilities are enabled:
   - ☑ **iCloud** (with CloudKit and iCloud Documents checked)
5. If you made changes, click **Save**

### 4. Add Diagnostic UI to Your App (Recommended)

This will help you debug sync issues in TestFlight. Add this to `SettingsView.swift`:

```swift
// Add to SettingsView body, inside a Section
Section("iCloud Diagnostics") {
    VStack(alignment: .leading, spacing: 8) {
        Text("iCloud Available: \(iCloudManager.shared.iCloudAvailable ? "✅ Yes" : "❌ No")")
        Text("Status: \(iCloudManager.shared.syncStatus.description)")
        if let lastSync = iCloudManager.shared.lastSyncDate {
            Text("Last Sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
        } else {
            Text("Last Sync: Never")
        }

        // Show CloudKit environment indicator
        #if DEBUG
        Text("Environment: 🔧 Development")
            .foregroundColor(.orange)
        #else
        Text("Environment: 🚀 Production")
            .foregroundColor(.green)
        #endif
    }
    .font(.caption)

    Button("Force Sync") {
        iCloudManager.shared.forceCompleteSync()
    }

    Button("Run Diagnostics") {
        Task {
            await iCloudManager.shared.diagnoseCloudKitData()
        }
    }
}
```

### 5. Enable Verbose Logging for TestFlight (Optional but Recommended)

To see detailed logs in Console.app when testing:

Edit `LotusPlannerV3App.swift` init():
```swift
init() {
    // Enable verbose logging for TestFlight builds
    #if DEBUG
    UserDefaults.standard.set(true, forKey: "verboseLoggingEnabled")
    #else
    // Enable for TestFlight debugging (disable after fixing)
    UserDefaults.standard.set(true, forKey: "verboseLoggingEnabled")
    #endif

    // ... rest of init
}
```

---

## Part 2: Build for TestFlight

### Step 1: Increment Build Number

```bash
cd LotusPlannerV3
agvtool next-version -all
```

This increments the build number. Each TestFlight upload must have a unique build number.

### Step 2: Clean Build Folder

```bash
# Clean any previous builds
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Step 3: Archive the App

**Option A: Using Xcode (Recommended for first-timers)**

1. Open the project in Xcode:
   ```bash
   open LotusPlannerV3.xcodeproj
   ```

2. Select target device: **Any iOS Device (arm64)**

3. Go to: **Product** → **Archive**

4. Wait for archive to complete (5-10 minutes)

5. Xcode Organizer will open automatically

**Option B: Using Command Line**

```bash
cd LotusPlannerV3

xcodebuild clean archive \
  -project LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -configuration Release \
  -archivePath ./build/LotusPlannerV3.xcarchive \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=M39PXKFX82
```

### Step 4: Upload to App Store Connect

**Option A: Via Xcode Organizer (Recommended)**

1. In Xcode Organizer (Window → Organizer → Archives)
2. Select your archive
3. Click **Distribute App**
4. Choose: **App Store Connect**
5. Choose: **Upload**
6. Select: **Automatically manage signing**
7. Review app information
8. Click **Upload**
9. Wait for upload to complete (5-15 minutes depending on connection)

**Option B: Via Command Line**

```bash
cd LotusPlannerV3

xcodebuild -exportArchive \
  -archivePath ./build/LotusPlannerV3.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ../ExportOptions.plist \
  -allowProvisioningUpdates
```

Then upload the IPA:
```bash
xcrun altool --upload-app \
  --type ios \
  --file ./build/export/LotusPlannerV3.ipa \
  --username "your-apple-id@email.com" \
  --password "@keychain:AC_PASSWORD"
```

**Note:** You'll need an app-specific password stored in Keychain:
```bash
# Generate app-specific password at appleid.apple.com
xcrun altool --store-password-in-keychain-item "AC_PASSWORD" \
  --username "your-apple-id@email.com" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Step 5: Wait for Processing

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select **My Apps** → **LotusPlannerV3**
3. Go to **TestFlight** tab
4. Wait for "Processing" to complete (usually 10-30 minutes)
5. You'll receive an email when processing is complete

---

## Part 3: Set Up TestFlight Testing

### Step 1: Add Yourself as Internal Tester

1. In App Store Connect → TestFlight tab
2. Click **Internal Testing** in left sidebar
3. Click the **+** button next to "Testers"
4. Select your Apple ID
5. Click **Add**
6. **Enable Automatic Distribution** (optional - new builds auto-deploy to internal testers)

### Step 2: Create External Testing Group (Optional)

For testing with other people:

1. Click **External Testing** in left sidebar
2. Click **+** to create a new group
3. Name it: "iCloud Sync Testing"
4. Add testers by email
5. Select the build to test
6. Click **Submit for Review** (Apple reviews external TestFlight builds, takes 24-48 hours)

### Step 3: Install TestFlight App

On your test device:
1. Install [TestFlight from App Store](https://apps.apple.com/app/testflight/id899247664)
2. Open TestFlight
3. Sign in with your Apple ID
4. You'll see LotusPlannerV3 listed
5. Tap **Install**

---

## Part 4: Test iCloud Sync in Production

### Test Scenario 1: Fresh Install Sync

**Device A (iPhone):**
1. Install from TestFlight
2. Sign in to iCloud (Settings → Apple ID)
3. Open LotusPlannerV3
4. Go to Settings → iCloud Diagnostics
5. Verify: "iCloud Available: ✅ Yes"
6. Verify: "Environment: 🚀 Production"
7. Create a new Goal: "TestFlight Test 1"
8. Wait 30 seconds
9. Tap "Force Sync" in Settings
10. Wait 15 seconds

**Device B (iPad):**
1. Install from TestFlight (same Apple ID)
2. Open LotusPlannerV3
3. Wait 30 seconds for CloudKit to import
4. Go to Goals view
5. Pull down to refresh
6. **Check:** Does "TestFlight Test 1" appear? ✅/❌

### Test Scenario 2: Bidirectional Sync

**Device B:**
1. Edit "TestFlight Test 1" → rename to "TestFlight Modified"
2. Wait 30 seconds
3. Tap "Force Sync"

**Device A:**
1. Wait 30 seconds
2. Go to Goals view
3. Pull down to refresh
4. **Check:** Does title update to "TestFlight Modified"? ✅/❌

### Test Scenario 3: Task Time Windows

**Device A:**
1. Go to Calendar/Timebox view
2. Create a time window for a task (drag/drop a task into timeline)
3. Wait 30 seconds
4. Force Sync

**Device B:**
1. Wait 45 seconds
2. Go to Calendar/Timebox view
3. **Check:** Does the task time window appear? ✅/❌

---

## Part 5: Debugging TestFlight Issues

### View Live Logs

**On Mac (with device connected via USB):**

1. Connect test device to Mac via USB
2. Open **Console.app** (in Applications → Utilities)
3. Select your device in left sidebar
4. In search box, filter by: `LotusPlannerV3`
5. Look for logs with these prefixes:
   - `✅/❌` - Success/Error indicators
   - `☁️` - iCloud/CloudKit operations
   - `🔄` - Sync operations
   - `🔍 DIAGNOSTICS` - Diagnostic output

**Common log patterns to look for:**

```
✅ iCloudManager: Complete sync finished
✅ iCloud available and signed in
🔄 Starting complete sync...
```

**Error patterns:**

```
❌ iCloud account not available
❌ CloudKit query failed
⚠️ No iCloud account signed in
```

### Run CloudKit Diagnostics

In the app:
1. Go to Settings → iCloud Diagnostics
2. Tap "Run Diagnostics"
3. Check Console.app logs for output like:
   ```
   🔍 DIAGNOSTICS: Found X TaskTimeWindow records in CloudKit
   🔍 DIAGNOSTICS: Found Y TaskTimeWindow records in local Core Data
   ```

If CloudKit count = 0 but local Core Data count > 0:
- ☝️ **Schema not deployed to Production**

If CloudKit count > 0 but local Core Data count = 0:
- ☝️ **Import not working** (CloudKit → Core Data)

### Check CloudKit Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
2. Select: `iCloud.com.chenchungwan.LotusPlannerV3`
3. Switch to: **Production** environment
4. Go to: **Data** → **Records**
5. Select record type: `CD_TaskTimeWindow` (or any entity)
6. **Check:** Do you see records? ✅/❌

If no records in Production but you've created data:
- ☝️ **Export not working** (Core Data → CloudKit)

### Common Issues & Fixes

#### Issue: "iCloud Available: ❌ No"

**Causes:**
- Not signed into iCloud on device
- iCloud Drive disabled
- App not authorized for iCloud

**Fix:**
1. Settings → [Your Name] → iCloud
2. Enable **iCloud Drive**
3. Scroll down to **LotusPlannerV3** → Enable

#### Issue: Sync works in Dev, not in TestFlight

**Cause:** CloudKit schema not deployed to Production

**Fix:**
1. CloudKit Dashboard → Development environment
2. Schema → Deploy Schema Changes
3. Deploy to Production
4. Wait 5-10 minutes
5. Rebuild and upload new TestFlight build

#### Issue: Data syncs only one direction

**Possible causes:**
- Merge policy conflicts
- Core Data validation errors
- CloudKit quota exceeded

**Fix:**
Check Console.app logs for merge errors:
```
❌ Failed to merge CloudKit changes
NSValidationError
```

#### Issue: Sync is very slow (> 2 minutes)

**Cause:** CloudKit throttling or large dataset

**Check:**
- CloudKit Dashboard → Usage → Check request rate
- Number of records in CloudKit

**Fix:**
- Implement batching for large syncs
- Add pagination for fetches

---

## Part 6: Release to App Store

Once TestFlight testing confirms iCloud sync works:

### Step 1: Prepare App Store Listing

1. Go to App Store Connect → My Apps → LotusPlannerV3
2. Click **App Store** tab (not TestFlight)
3. Under **iOS App**, click **+** next to version
4. Enter version number (e.g., 2.1.0)
5. Fill in "What's New in This Version"
6. Upload screenshots (required)
7. Fill in app description, keywords, etc.

### Step 2: Select Build

1. Under **Build** section, click **Select a build**
2. Choose the TestFlight build you tested
3. Fill in export compliance questions

### Step 3: Submit for Review

1. Complete all required fields
2. Click **Add for Review**
3. Click **Submit to App Review**
4. Review typically takes 24-48 hours

---

## Quick Reference Commands

```bash
# Increment build number
cd LotusPlannerV3 && agvtool next-version -all

# Clean build
rm -rf ~/Library/Developer/Xcode/DerivedData

# Archive (Xcode UI)
# Product → Archive

# Check current versions
agvtool what-version              # Build number
agvtool what-marketing-version    # Version number

# Set version number (if needed)
agvtool new-marketing-version 2.1.0
```

---

## Troubleshooting Checklist

Before uploading each TestFlight build, verify:

- [ ] CloudKit schema deployed to Production
- [ ] iCloud capability enabled in App ID
- [ ] Entitlements file includes CloudKit
- [ ] Build number incremented
- [ ] Code signed with App Store profile
- [ ] Diagnostic UI added to Settings (recommended)
- [ ] Verbose logging enabled (optional)

---

## Testing Checklist

For each TestFlight build, test:

- [ ] Fresh install on Device A
- [ ] iCloud status shows "✅ Yes"
- [ ] Environment shows "🚀 Production"
- [ ] Create test data on Device A
- [ ] Install on Device B (same iCloud account)
- [ ] Test data appears on Device B within 60 seconds
- [ ] Modify data on Device B
- [ ] Changes appear on Device A within 60 seconds
- [ ] Check Console.app logs for errors
- [ ] Run CloudKit diagnostics

---

## Support Resources

- [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
- [App Store Connect](https://appstoreconnect.apple.com)
- [Apple Developer Portal](https://developer.apple.com/account)
- [TestFlight Documentation](https://developer.apple.com/testflight/)

---

## Summary

1. **Deploy CloudKit schema to Production** (most common issue)
2. **Archive and upload** to App Store Connect
3. **Add yourself as internal tester** in TestFlight
4. **Install from TestFlight** on 2 devices
5. **Test sync** between devices
6. **Check Console.app logs** if sync fails
7. **Run diagnostics** in app to see CloudKit data
8. **Fix issues** and upload new build
9. Repeat until sync works reliably
10. **Submit to App Store** once confirmed working

**Key Insight:** The main difference between Dev and Production is the CloudKit environment. Make sure your schema is deployed to Production and verify it in the CloudKit Dashboard before testing.
