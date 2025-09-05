# 🧪 Core Data Migration Testing Guide

## Overview
Testing Core Data migration on actual devices is **critical** before production release. This ensures user data won't be lost during app updates.

## 📱 Required Test Devices

### Minimum Test Setup
- **2 physical iOS devices** (iPhone/iPad) - simulators don't test iCloud properly
- **Same iCloud account** signed in on both devices
- **Different iOS versions** if possible (e.g., iOS 17 & iOS 18)

### Recommended Test Setup  
- **3+ devices**: iPhone, iPad, and older device
- **Various storage states**: Low storage, full storage
- **Network conditions**: WiFi, cellular, offline

## 🔄 Migration Test Scenarios

### **Test 1: Fresh Install Migration**
Tests migration from UserDefaults/iCloud KVS to Core Data

#### Setup:
1. Install **previous version** of app (if available)
2. Create test data:
   - Add 5-10 weight entries
   - Add 5-10 workout entries  
   - Add 5-10 food entries
   - Create some goals and categories
3. Force quit app
4. Wait for iCloud sync (check Settings > iCloud)

#### Migration Test:
1. Install **new version** with Core Data
2. Launch app and check console logs
3. Verify all data appears correctly
4. Check that `coreDataLegacyMigrationDone` flag is set

#### Expected Results:
```
✅ All legacy data migrated to Core Data
✅ No data loss
✅ Migration flag set (prevents re-migration)
✅ iCloud sync working with new Core Data
```

### **Test 2: Core Data Schema Migration** 
Tests migration between Core Data model versions

#### Setup:
1. Install current version
2. Create substantial test data
3. Force app to background
4. Simulate schema change (if you have model updates)

#### Migration Test:
1. Update to new schema version
2. Launch app - should auto-migrate
3. Verify data integrity
4. Check migration logs

#### Expected Results:
```
✅ Automatic lightweight migration succeeds
✅ All data preserved
✅ New schema features work
✅ No corruption or loss
```

### **Test 3: iCloud Sync Across Devices**
Tests CloudKit integration

#### Setup:
1. Device A: Create data, wait for sync
2. Device B: Launch app, wait for sync
3. Verify data appears on both devices

#### Sync Test:
1. Device A: Add new entries
2. Wait 30-60 seconds
3. Device B: Pull to refresh or restart app
4. Verify new data appears

#### Expected Results:
```
✅ Data syncs between devices
✅ No conflicts or duplicates  
✅ Sync status shows correctly
✅ Remote change notifications work
```

## 📋 Step-by-Step Testing Protocol

### **Phase 1: Pre-Migration Setup**

#### Step 1: Prepare Test Data
```bash
# On Device 1:
1. Open app
2. Add test data:
   - Weight: 150 lbs (today)
   - Weight: 149 lbs (yesterday) 
   - Workout: "Morning Run" (today)
   - Workout: "Gym Session" (yesterday)
   - Food: "Breakfast" (today)
   - Food: "Lunch" (yesterday)
3. Force quit app (double-tap home, swipe up)
4. Wait 2-3 minutes for iCloud sync
```

#### Step 2: Verify iCloud Backup
```bash
# Check iCloud status:
1. Settings > [Your Name] > iCloud
2. Verify "Lotus Planner" is enabled
3. Check available iCloud storage
4. Note current data size
```

#### Step 3: Install on Second Device
```bash
# On Device 2:
1. Install same app version
2. Sign in with same iCloud account
3. Launch app
4. Verify data syncs from Device 1
5. Add one more entry to test bidirectional sync
```

### **Phase 2: Migration Testing**

#### Step 4: Deploy New Version
```bash
# Build and install new version:
1. Xcode > Product > Archive
2. Distribute to devices via TestFlight or direct install
3. Install on Device 1 first
```

#### Step 5: Monitor Migration
```bash
# On Device 1 (first migration):
1. Launch app
2. Watch Xcode console for migration logs:
   - "🔄 Migrating legacy storage..."
   - "✅ Migration completed"
   - "✅ Core Data store loaded successfully"
3. Verify all data is visible
4. Add one new entry
5. Force quit app
```

#### Step 6: Test Second Device
```bash
# On Device 2 (should sync from CloudKit):
1. Install new version
2. Launch app  
3. Should see all data (old + new entry from Device 1)
4. Check migration logs
5. Add another entry
```

#### Step 7: Cross-Device Verification
```bash
# Verify sync works both ways:
1. Device 1: Restart app, check for Device 2's new entry
2. Device 2: Restart app, check all entries present
3. Both devices should have identical data
```

### **Phase 3: Stress Testing**

#### Step 8: Large Data Migration
```bash
# Create substantial dataset:
1. Add 50+ weight entries across 3 months
2. Add 30+ workout entries
3. Add 40+ food entries
4. Create 10+ goal categories with 20+ goals
5. Test migration performance
```

#### Step 9: Network Stress Testing
```bash
# Test various network conditions:
1. Migration on WiFi (should be fastest)
2. Migration on cellular (slower)
3. Migration with poor connection
4. Migration while switching networks
```

#### Step 10: Storage Stress Testing
```bash
# Test with limited storage:
1. Fill device to ~90% capacity
2. Attempt migration
3. Monitor for storage errors
4. Verify graceful handling
```

## 🔍 Monitoring & Debugging

### **Console Logs to Watch For:**

#### Migration Success:
```
✅ Core Data store loaded successfully
🔄 Migrating legacy storage...
✅ Local data migration to iCloud completed
📡 CloudKit remote changes received
```

#### Migration Issues:
```
❌ Core Data Error: Failed to load persistent store
🔄 Migration required - incompatible version
💾 Store operation failed - check permissions/storage
⚠️ Failed to create preview data
```

#### iCloud Sync Status:
```
✅ iCloud available and signed in
📡 CloudKit remote changes received
✅ Force sync completed
⚠️ No iCloud account signed in
```

### **Settings UI Verification:**
1. Open Settings in app
2. Check "iCloud Sync" section shows:
   - ✅ Blue cloud icon (if available)
   - ✅ "iCloud sync enabled" status
   - ✅ "Sync Now" button works
   - ✅ Last sync timestamp updates

## 🚨 Common Issues & Solutions

### **Migration Fails:**
```bash
# If migration fails:
1. Check console for specific error
2. Verify iCloud account is signed in
3. Check device storage space
4. Try "Clear All Auth State" in Settings
5. Reinstall app if necessary
```

### **iCloud Sync Issues:**
```bash
# If sync doesn't work:
1. Check Settings > [Name] > iCloud > Lotus Planner enabled
2. Verify internet connection
3. Try manual "Sync Now" in app Settings
4. Check CloudKit Dashboard for errors
5. Sign out/in to iCloud if needed
```

### **Data Corruption:**
```bash
# If data appears corrupted:
1. Check Core Data model versions match
2. Verify CloudKit schema is correct
3. Use "Clear All Data" (last resort)
4. Restore from iCloud backup
```

## ✅ Success Criteria

### **Migration Must Pass:**
- [ ] All legacy data migrated correctly
- [ ] No data loss or corruption
- [ ] Migration completes within 30 seconds
- [ ] App remains responsive during migration
- [ ] iCloud sync works after migration

### **Multi-Device Must Pass:**
- [ ] Data syncs between all devices
- [ ] No duplicate entries
- [ ] Changes appear within 60 seconds
- [ ] Offline changes sync when online
- [ ] Conflicts resolve automatically

### **Performance Must Pass:**
- [ ] App launches within 5 seconds post-migration
- [ ] UI remains responsive during sync
- [ ] Large datasets (100+ entries) handle properly
- [ ] Memory usage stays reasonable

## 🎯 Production Readiness Checklist

Before releasing to App Store:

- [ ] **Tested on 3+ physical devices**
- [ ] **Tested with large datasets (100+ entries)**
- [ ] **Tested poor network conditions**
- [ ] **Tested low storage scenarios**
- [ ] **Verified iCloud sync works reliably**
- [ ] **Confirmed no data loss in any scenario**
- [ ] **Performance acceptable on oldest supported device**
- [ ] **Migration completes successfully 100% of the time**

## 🔧 Testing Commands

```bash
# Reset app data for fresh migration test:
# Settings > General > iPhone Storage > Lotus Planner > Offload App

# Clear iCloud data (use carefully):
# Settings > [Your Name] > iCloud > Manage Storage > Lotus Planner > Delete Data

# Monitor CloudKit:
# CloudKit Console: developer.apple.com/icloud/dashboard
```

---

**⚠️ CRITICAL**: Never test migration on production data. Always use test accounts and test data!
