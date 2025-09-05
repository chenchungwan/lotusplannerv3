# 🔧 Xcode Environment Variables Setup

## 🎯 Quick Fix for Blank Screen

Your app is launching successfully but shows blank content because Google credentials aren't configured. Here's how to fix it:

## 📋 Step-by-Step Setup

### 1. Open Scheme Editor
```
1. In Xcode, go to: Product → Scheme → Edit Scheme...
2. Select "Run" in the left sidebar
3. Click on "Arguments" tab
4. Look for "Environment Variables" section
```

### 2. Add Required Variables
Click the "+" button and add these **2 environment variables**:

| Name | Value |
|------|-------|
| `GOOGLE_CLIENT_ID` | `1079954098512-aahk5s97468gvetqdoog6ccsmfkaf04c.apps.googleusercontent.com` |
| `GOOGLE_REVERSED_CLIENT_ID` | `com.googleusercontent.apps.1079954098512-aahk5s97468gvetqdoog6ccsmfkaf04c` |

### 3. Save and Run
```
1. Click "Close" to save the scheme
2. Run your app (Cmd+R)
3. Check console - should now show:
   ✅ Google Client ID configured: true
   ✅ Configuration validation passed
```

## 🎉 Expected Results

After setting environment variables:

### Console Output:
```
✅ Core Data store loaded successfully
🔧 Configuration Manager Status:
Environment: development
Google Client ID configured: true
Google Reversed Client ID configured: true
Validation passes: true
✅ Configuration validation passed
```

### App Behavior:
- ✅ **Cover image appears** (blue gradient with "Lotus Planner")
- ✅ **Auto-dismisses after 2 seconds** or swipe left
- ✅ **Main app interface loads** showing calendar view
- ✅ **Google authentication works** in Settings

## 🚨 If Still Issues

### Console Still Shows "false" for Client ID:
1. **Double-check spelling** of environment variable names
2. **Restart Xcode** after setting variables
3. **Clean build folder** (Cmd+Shift+K)

### App Still Blank:
1. **Check Xcode console** for error messages
2. **Try simulator vs device** 
3. **Check iOS deployment target** (currently set to 18.5)

---

**This should completely resolve the blank screen issue!** 🚀
