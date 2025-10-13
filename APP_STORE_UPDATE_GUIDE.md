# How to Update Your App Store Build

## Current Version Info
- **Version:** 1.0
- **Build:** 1

## Quick Update Process

### Option 1: Quick Update (Same Version, New Build)
Use this for bug fixes without changing the version number.

```bash
# This will increment build to 2, keeping version at 1.0
```

### Option 2: New Version Update
Use this for feature updates or major releases.

## Step-by-Step Guide

### Step 1: Increment Build Number

You need to increment the build number for each submission to App Store Connect.

**In Xcode:**
1. Open your project in Xcode
2. Select the **LotusPlannerV3** project in the navigator
3. Select the **LotusPlannerV3** target
4. Go to **General** tab
5. Under **Identity** section:
   - **Version:** 1.0 (change to 1.1, 2.0, etc. for feature updates)
   - **Build:** Change from **1** to **2** (must be higher than previous)

**Or edit directly in project.pbxproj:**
- Change `CURRENT_PROJECT_VERSION = 1;` to `CURRENT_PROJECT_VERSION = 2;`
- Optionally change `MARKETING_VERSION = 1.0;` to `1.1` or `2.0`

### Step 2: Archive Your App

1. In Xcode, select **Any iOS Device** or **Any Mac (Designed for iPad)** as the build destination
   - Menu: **Product > Destination > Any iOS Device**

2. Clean the build folder:
   - Menu: **Product > Clean Build Folder**
   - Or press: **Shift + Command + K**

3. Create an archive:
   - Menu: **Product > Archive**
   - Or press: **Command + Shift + B** (after selecting device)
   - Wait for the archive to complete (may take a few minutes)

4. The **Organizer** window should open automatically
   - If not, go to **Window > Organizer**

### Step 3: Upload to App Store Connect

In the **Organizer** window:

1. Select your new archive
2. Click **Distribute App**
3. Select **App Store Connect**
4. Click **Next**
5. Select **Upload**
6. Click **Next**
7. Choose distribution options:
   - ✅ **Upload your app's symbols** (recommended for crash reports)
   - ✅ **Manage Version and Build Number** (let Xcode handle it)
8. Click **Next**
9. Review the app information
10. Click **Upload**
11. Wait for upload to complete (may take 5-15 minutes)

### Step 4: Process and Test (App Store Connect)

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Sign in with your Apple ID
3. Go to **My Apps** > **LotusPlannerV3**
4. Wait for the build to process (10-60 minutes)
   - You'll receive an email when processing is complete
   - Status changes from "Processing" to "Ready to Submit"

### Step 5: Submit for Review (If Needed)

#### For First Release or Major Updates:
1. In App Store Connect, click on your app
2. Go to **App Store** tab
3. Click on the version (e.g., 1.0)
4. Under **Build**, click **(+)** to add your new build
5. Select the build you just uploaded
6. Fill in **What's New in This Version**
7. Save changes
8. Click **Submit for Review**

#### For Bug Fix Updates to Existing Version:
1. In App Store Connect, click on your app
2. If the current version is "Ready for Sale":
   - Click **(+) Version or Platform**
   - Select **iOS** (or all platforms)
   - Enter new version number (e.g., 1.0.1)
   - Add the new build
   - Describe changes in "What's New"
   - Submit for review

### Step 6: Release Options

After approval, you can:

1. **Automatic Release:** App goes live immediately after approval
2. **Manual Release:** You release it when ready
3. **Scheduled Release:** Set a specific date/time

## Version Numbering Guidelines

### Marketing Version (User-Facing)
- **Major update:** 1.0 → 2.0 (significant new features)
- **Minor update:** 1.0 → 1.1 (new features, improvements)
- **Patch update:** 1.0.0 → 1.0.1 (bug fixes)

### Build Number (Internal)
- **Must increase** for each upload: 1 → 2 → 3 → 4...
- Can reset when changing marketing version
- Example: 1.0 (build 5) → 1.1 (build 1) is valid

## Common Issues & Solutions

### ❌ "Build already exists"
**Solution:** Increment the build number higher

### ❌ "Invalid Provisioning Profile"
**Solution:** 
1. Go to Xcode > Settings > Accounts
2. Select your Apple ID
3. Download Manual Profiles

### ❌ "Export Failed"
**Solution:**
1. Check your signing certificates are valid
2. Verify your App ID is registered in Developer Portal
3. Try cleaning build folder and rebuilding

### ❌ "Missing Compliance"
**Solution:** After upload, answer export compliance questions in App Store Connect

### ⚠️ Build stuck in "Processing"
**Solution:** Wait up to 60 minutes. Check for email from Apple about any issues.

## Automated Build Number Increment

To automatically increment build numbers, add this to your build phases:

1. Select your target in Xcode
2. Go to **Build Phases**
3. Click **(+)** > **New Run Script Phase**
4. Add this script:

```bash
buildNumber=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${PROJECT_DIR}/${INFOPLIST_FILE}")
buildNumber=$(($buildNumber + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "${PROJECT_DIR}/${INFOPLIST_FILE}"
```

## TestFlight Distribution

For beta testing before App Store release:

1. Follow Steps 1-3 above
2. In **Distribute App**, select **TestFlight Only**
3. Add testers in App Store Connect
4. They can install via TestFlight app

## What Changed in Your Latest Build

Based on your recent merge, your new build includes:

✅ **Fixed:** iCloud sync on macOS
✅ **Improved:** Platform-specific haptic feedback handling
✅ **Added:** Better sync reliability across devices
✅ **Updated:** Various UI improvements

**Suggested "What's New" text:**
```
- Fixed iCloud sync issues on Mac
- Improved cross-device synchronization
- Enhanced stability and performance
- Various bug fixes and improvements
```

## Quick Reference Commands

```bash
# Check current version/build
grep -A1 "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" \
  LotusPlannerV3/LotusPlannerV3.xcodeproj/project.pbxproj

# Create archive from command line
xcodebuild archive \
  -project LotusPlannerV3/LotusPlannerV3.xcodeproj \
  -scheme LotusPlannerV3 \
  -archivePath ./build/LotusPlannerV3.xcarchive

# Export for App Store
xcodebuild -exportArchive \
  -archivePath ./build/LotusPlannerV3.xcarchive \
  -exportPath ./build \
  -exportOptionsPlist ExportOptions.plist
```

## Next Steps

1. ✅ Update build number (1 → 2)
2. ✅ Archive the app
3. ✅ Upload to App Store Connect
4. ⏳ Wait for processing
5. ✅ Submit for review
6. ⏳ Wait for approval (typically 1-3 days)
7. 🚀 Release to users

---

**Need Help?**
- [App Store Connect Help](https://developer.apple.com/app-store-connect/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [TestFlight Documentation](https://developer.apple.com/testflight/)


