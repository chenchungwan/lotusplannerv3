# New Simple Journal Storage Plan

## Problem with Old Implementation
- Complex NSFilePresenter causing constant refresh loops
- Multiple layers of caching and sync coordinators
- setUbiquitous() calls that were unreliable
- Too many moving parts causing performance issues

## New Simple Approach

### Core Principles
1. **Direct writes** - Write directly to iCloud container path
2. **No monitoring** - No NSFilePresenter, no metadata queries
3. **Simple cache** - In-memory cache only, no disk cache
4. **Manual refresh** - User can manually refresh if needed
5. **Debounced saves** - Save after 1 second of no drawing changes

### New Components

#### 1. JournalStorageNew.swift
- Simple save/load API
- Writes directly to iCloud container (or local fallback)
- In-memory caching only
- No notifications, no file monitoring
- ~180 lines vs 831 lines

#### 2. JournalDrawingManagerNew.swift  
- Debounces drawing changes (1 second delay)
- Saves immediately on app background or date switch
- No complex retry logic
- ~70 lines vs 227 lines

### Migration Steps
1. ✅ Create new simplified storage classes
2. Update JournalView to use new classes
3. Remove old complex classes:
   - JournalSyncCoordinator.swift
   - JournalCache.swift
   - JournalFilePresenter.swift
   - Most of JournalManager.swift (keep only background PDF methods)

### Benefits
- Fast and responsive drawing
- No refresh loops
- Simple to understand and debug
- Reliable iCloud sync (files written to container auto-sync)
- User stays in control

### Trade-offs
- No automatic refresh when other device makes changes
- User needs to reopen journal or manually refresh to see changes from other devices
- This is acceptable - most users edit journal on one device at a time

