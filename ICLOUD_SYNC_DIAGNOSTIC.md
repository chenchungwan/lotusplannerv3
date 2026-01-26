# iCloud Sync Diagnostic Guide

## Issue: Sync works in Dev but NOT in Production (App Store)

This guide will help diagnose why iCloud sync works during development but fails in production builds distributed through the App Store.

---

## Common Causes

### 1. CloudKit Container Environment Mismatch

**Problem**: Development builds use the **Development** CloudKit environment, but production builds use the **Production** CloudKit environment. These are completely separate databases.

**Check**:
1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
2. Sign in with your Apple Developer account
3. Select your app's container: `iCloud.com.chenchungwan.LotusPlannerV3`
4. Check if Production environment is **deployed**

**Fix**:
- In CloudKit Dashboard, deploy your schema to Production:
  1. Go to Schema section
  2. Click "Deploy Schema Changes"
  3. Deploy from Development → Production
  4. Confirm deployment

---

### 2. Provisioning Profile Missing CloudKit Entitlement

**Problem**: The App Store provisioning profile might not include CloudKit capabilities.

**Check**:
1. Open Xcode
2. Select your project → Target → Signing & Capabilities
3. Verify "iCloud" capability is present with:
   - ☑ CloudKit
   - ☑ CloudDocuments
   - Container: `iCloud.com.chenchungwan.LotusPlannerV3`

**Fix**:
1. In [Apple Developer Portal](https://developer.apple.com/account)
2. Go to Certificates, Identifiers & Profiles
3. Select your App ID: `com.chenchungwan.LotusPlannerV3`
4. Ensure "iCloud" capability is enabled
5. Regenerate and download provisioning profiles
6. In Xcode: Preferences → Accounts → Download Manual Profiles

---

### 3. CloudKit Record Indexes Not Deployed

**Problem**: Core Data + CloudKit requires specific indexes in production.

**Check**:
1. CloudKit Dashboard → Schema → Indexes
2. Verify these record types exist in Production:
   - `CD_Goal`
   - `CD_GoalCategory`
   - `CD_WeightLog`
   - `CD_WorkoutLog`
   - `CD_FoodLog`
   - `CD_SleepLog`
   - `CD_WaterLog`
   - `CD_CustomLogItem`
   - `CD_CustomLogEntry`
   - `CD_TaskTimeWindow`

**Fix**:
- Deploy schema changes from Development to Production (see #1)

---

### 4. User Not Signed Into iCloud

**Problem**: Production users might not be signed into iCloud on their devices.

**Check** (in production app):
1. Open Settings app
2. Tap on Apple ID at top
3. Verify iCloud is enabled
4. Tap iCloud → Show All
5. Verify your app is listed and enabled

**User Instructions**:
- Add an in-app alert showing iCloud status
- See: `iCloudManager.shared.syncStatus`

---

### 5. CloudKit Quota Exceeded

**Problem**: Free tier CloudKit has limits on storage and requests.

**Check**:
1. CloudKit Dashboard → Usage
2. Check Production environment usage:
   - Storage: < 1GB free tier
   - Requests: < 40 requests/second
   - Users: Unlimited

**Fix**:
- If over quota, implement data cleanup or upgrade plan

---

## Testing Production CloudKit Locally

To test the **Production** CloudKit environment before submitting to App Store:

### Option 1: Archive Build with Production Profile

```bash
# 1. Archive the app
xcodebuild archive \
  -project LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -archivePath ./LotusPlannerV3.xcarchive

# 2. Export with App Store profile (uses Production CloudKit)
xcodebuild -exportArchive \
  -archivePath ./LotusPlannerV3.xcarchive \
  -exportPath ./Export \
  -exportOptionsPlist ExportOptions.plist

# 3. Install on physical device via Xcode
# Xcode → Window → Devices and Simulators → Install .ipa
```

### Option 2: TestFlight

1. Submit build to TestFlight
2. Install on test device
3. This uses Production CloudKit environment
4. Check sync behavior

---

## Debugging Production Sync Issues

### Enable Verbose Logging

Add this to see CloudKit sync events in production:

```swift
// In LotusPlannerV3App.swift init()
#if DEBUG
UserDefaults.standard.set(true, forKey: "verboseLoggingEnabled")
#else
// Enable for production debugging (remove after fixing)
UserDefaults.standard.set(true, forKey: "verboseLoggingEnabled")
#endif
```

Then check logs in Console.app:
1. Connect iPhone via USB
2. Open Console.app on Mac
3. Select your device
4. Filter for: `LotusPlannerV3`
5. Look for logs with:
   - `☁️ Persistence: CloudKit`
   - `✅/❌ Core Data`
   - `🔄 Syncing`

### Check CloudKit Sync Status in App

Add a debug screen to check sync status:

```swift
// In SettingsView.swift
Section("CloudKit Debug") {
    Text("iCloud Available: \(iCloudManager.shared.iCloudAvailable ? "✅" : "❌")")
    Text("Sync Status: \(iCloudManager.shared.syncStatus.description)")
    if let lastSync = iCloudManager.shared.lastSyncDate {
        Text("Last Sync: \(lastSync.formatted())")
    }

    Button("Force Sync") {
        iCloudManager.shared.forceSyncToiCloud()
    }
}
```

---

## Verifying the Fix

### Before Fix
- Goals and Goal Categories had `userId = "default"`
- This prevented CloudKit from syncing them properly
- Each device saw different goals

### After Fix (Version 2.2.5+)
- Goals and Goal Categories now use `userId = "icloud-user"`
- Migration automatically updates existing data
- All devices see the same goals

### Testing Sync

1. **Install v2.2.5+ on Device A**
   - Create a new goal "Test Goal A"
   - Wait 10-15 seconds for CloudKit sync

2. **Install v2.2.5+ on Device B** (same iCloud account)
   - Open app
   - Wait 10-15 seconds for CloudKit import
   - Pull down to refresh Goals view
   - "Test Goal A" should appear

3. **Edit on Device B**
   - Change title to "Test Goal B"
   - Wait 10-15 seconds

4. **Check Device A**
   - Pull down to refresh
   - Title should update to "Test Goal B"

---

## Quick Checklist

- [ ] CloudKit container deployed to Production
- [ ] App ID has iCloud capability enabled
- [ ] Provisioning profile includes CloudKit entitlement
- [ ] Schema deployed from Development → Production
- [ ] Core Data record types exist in Production
- [ ] Indexes created in Production environment
- [ ] Test device signed into iCloud
- [ ] App installed from TestFlight or App Store
- [ ] App has permission to use iCloud (Settings → Privacy)
- [ ] Version 2.2.5+ installed (includes userId fix)

---

## Still Not Working?

If sync still fails after checking everything above:

1. **Reset CloudKit Development Data**
   ```bash
   # This clears local cache
   # Settings → Your Name → iCloud → Manage Storage → Lotus Planner → Delete Data
   ```

2. **Check Core Data + CloudKit Logs**
   ```bash
   # In Xcode, add these launch arguments:
   # Product → Scheme → Edit Scheme → Run → Arguments
   -com.apple.CoreData.CloudKitDebug 1
   -com.apple.CoreData.Logging.stderr 1
   ```

3. **File a Radar with Apple**
   - If CloudKit is fundamentally broken
   - Include sysdiagnose logs
   - Reference: [Apple Bug Reporter](https://feedbackassistant.apple.com)

---

## Related Files

- [`Persistence.swift`](LotusPlannerV3/LotusPlannerV3/Persistence.swift) - Core Data + CloudKit setup
- [`iCloudManager.swift`](LotusPlannerV3/LotusPlannerV3/iCloudManager.swift) - Sync coordination
- [`GoalsManager.swift`](LotusPlannerV3/LotusPlannerV3/GoalsManager.swift) - Goals CRUD with userId fix
- [`LotusPlannerV3.entitlements`](LotusPlannerV3/LotusPlannerV3/LotusPlannerV3.entitlements) - iCloud entitlements

---

## Summary

✅ **CloudKit schema IS deployed to Production** (verified via schema export)

The code fix (userId "default" → "icloud-user") is now in place for Goals and Goal Categories in version 2.2.5+.

### The Real Issue: Existing Production Data

The problem is that **CloudKit already has Goals records with userId="default"** from previous app versions. When devices sync:

1. App installs v2.2.5 with migration
2. Migration updates local Core Data: "default" → "icloud-user"
3. Migration triggers CloudKit sync to push changes
4. BUT CloudKit might still have old records from other devices
5. Those old records sync DOWN and can cause conflicts

### Recommended Solution Path

**For apps already in production with users:**

1. **Deploy v2.2.5** to App Store (migration is already in the code)
2. **All devices must update** to v2.2.5 for sync to work
3. **Migration runs automatically** on each device
4. **Wait 24-48 hours** for all CloudKit records to migrate
5. **Old devices** (not updated) will continue using userId="default" and won't sync

**For development/testing or fresh start:**

If you have no users yet or want a clean slate:
1. Go to CloudKit Dashboard → Production → Admin
2. Click "Reset Production Environment"
3. This deletes all CloudKit data
4. Deploy v2.2.5 - all new data will use "icloud-user"
5. Perfect sync from day one

### Manual Migration for Existing Users

If users report sync issues after updating to v2.2.5:

1. **Have user sign out and back into iCloud** (Settings → Apple ID → Sign Out → Sign In)
2. **Delete and reinstall the app** (this clears local Core Data)
3. **CloudKit will re-download** all data
4. **Migration runs** on fresh data
5. **Verify** in app that Goals appear

### Verification Steps

After deploying v2.2.5:

1. Install on Device A from TestFlight/App Store
2. Create a new Goal "Test Sync"
3. Wait 30 seconds
4. Install on Device B (same iCloud account)
5. Open app, wait 30 seconds
6. Pull to refresh Goals view
7. "Test Sync" should appear ✅

If it doesn't appear, check:
- Both devices on v2.2.5+
- Both signed into same iCloud account
- iCloud enabled in Settings → Apple ID → iCloud → Lotus Planner
- Wait longer (CloudKit can take 2-3 minutes)
