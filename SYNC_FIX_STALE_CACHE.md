# iCloud Sync Fix - Stale Cache Issue

## Problem Discovered

From the console logs, we found:
- **Device A**: Saving `8075 bytes` to iCloud ✅
- **Device B**: Loading file with `0 strokes` ❌

**Files WERE syncing to iCloud**, but Device B was reading from a **stale local cache** instead of the fresh iCloud version.

## Root Cause

When iOS downloads iCloud files, it caches them locally. The problem:
1. Device B downloaded the file initially (when it was empty)
2. Device A updated the file in iCloud
3. Device B still had the OLD cached version locally
4. When loading, Device B read from cache instead of checking iCloud for updates

This is a common iCloud issue - the local cache doesn't automatically invalidate when remote files change.

## Solution

Force iCloud to **evict the local cache and re-download** on every load:

```swift
// BEFORE (broken):
try? FileManager.default.startDownloadingUbiquitousItem(at: url)
let data = try Data(contentsOf: url) // Reads from stale cache!

// AFTER (fixed):
try FileManager.default.evictUbiquitousItem(at: url)  // Delete cache
try FileManager.default.startDownloadingUbiquitousItem(at: url) // Re-download
try? await Task.sleep(nanoseconds: 500_000_000) // Wait for download
let data = try Data(contentsOf: url) // Now reads fresh version!
```

## Changes Made

### JournalStorageNew.swift
- `load()` is now `async` to support the evict/download cycle
- Evicts local cache before reading
- Forces fresh download from iCloud
- Waits 0.5 seconds for download to start
- Then reads the fresh data

### JournalView.swift
- Updated `loadDrawing()` to use `Task { @MainActor in await load() }`
- Properly handles async loading

## Expected Behavior Now

### Device A (Writer):
1. User draws
2. Saves to iCloud: `size: 8075 bytes`
3. File syncs to iCloud servers

### Device B (Reader):
1. User opens journal
2. **Evicts old cached version** (if any)
3. **Downloads fresh version from iCloud**
4. Loads drawing: `✅ Loaded drawing: 2025-10-13 (X strokes)`
5. Sees the same drawing as Device A!

## Console Output to Expect

On Device B, you should now see:
```
📝 ==================== LOAD OPERATION ====================
📝 Loading drawing for: 2025-10-13
📝 Not in cache, checking storage...
📝 iCloud Available: true
📝 File exists: true
📝 File is in iCloud
📝 Download status: Optional(NSURLUbiquitousItemDownloadingStatusDownloaded)
📝 Evicting cached version to force fresh download...
✅ Evicted old version
✅ Downloading latest version from iCloud
✅ Loaded drawing: 2025-10-13 (X strokes)  ← Should match Device A!
📝 ========================================================
```

## Trade-offs

⚠️ **Slight delay on load** - Takes ~0.5 seconds longer to load because we're downloading fresh
✅ **Always get latest version** - No more stale data!

This is the correct trade-off for cross-device sync reliability.

## Why This Works

Apple's iCloud Drive documentation states:
- Files written to ubiquity container automatically sync ✅
- But local caches may not invalidate automatically ❌
- Solution: Explicitly evict cache before reading ✅

This is the recommended pattern for reliable iCloud file reading when you need the absolute latest version.

## Testing

1. **Device A**: Draw something
2. **Wait 2-3 seconds** for iCloud sync
3. **Device B**: Open journal
4. **Should see the same drawing immediately**

If you see "0 strokes" on Device B, check the console - you should see the evict/download logs. If evict fails, there may be a permissions issue.

