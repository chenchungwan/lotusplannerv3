# Security Setup Guide for LotusPlannerV3

## Overview
This guide explains how to securely configure the LotusPlannerV3 app for production deployment. The app now uses secure storage practices and environment-based configuration.

## 🔐 Security Improvements Implemented

### 1. Keychain Storage
- **Before**: Tokens stored in UserDefaults (insecure)
- **After**: Tokens stored in iOS Keychain with automatic migration

### 2. Secure Configuration
- **Before**: API keys hardcoded in tracked files
- **After**: Environment-based configuration with secure fallbacks

### 3. Production Environment
- **Before**: Development environment configuration
- **After**: Production-ready environment settings

## 📋 Setup Instructions

### Step 1: Configure Google Services
1. Copy `GoogleService-Info-Template.plist` to `GoogleService-Info.plist`
2. Replace all placeholder values with your actual Google project credentials:
   ```
   YOUR_CLIENT_ID_HERE → Your actual Google Client ID
   YOUR_API_KEY_HERE → Your actual Google API Key
   YOUR_PROJECT_ID_HERE → Your actual Firebase Project ID
   etc.
   ```

### Step 2: Environment Variables (Recommended for CI/CD)
Set these environment variables for maximum security:
```bash
export GOOGLE_CLIENT_ID="your-client-id"
export GOOGLE_API_KEY="your-api-key"
export GOOGLE_PROJECT_ID="your-project-id"
export GOOGLE_APP_ID="your-app-id"
export GCM_SENDER_ID="your-sender-id"
export GOOGLE_STORAGE_BUCKET="your-storage-bucket"
```

### Step 3: Verify Security Configuration
The app will automatically validate configuration on launch and print status to console.

## 🔒 Security Features

### Keychain Storage
- Refresh tokens: Stored in iOS Keychain
- Access tokens: Stored in iOS Keychain
- Automatic migration: Existing UserDefaults tokens migrated on first launch
- Secure deletion: Proper cleanup when unlinking accounts

### Configuration Management
- Environment-first: Checks environment variables first
- Secure fallback: Falls back to secure config files
- Validation: Automatic validation on app launch
- Debug protection: Development fallbacks only in DEBUG builds

### Production Environment
- Push notifications: Production APS environment
- iCloud sync: Production CloudKit environment
- Security: Production-grade token storage

## 🚨 Important Security Notes

### For Development
- GoogleService-Info.plist is now in .gitignore
- Use the template file to create your local configuration
- Never commit actual API keys to version control

### For Production
- Use environment variables in CI/CD pipelines
- Regularly rotate API keys and credentials
- Monitor for security vulnerabilities
- Test keychain migration thoroughly

### For Team Members
1. Get GoogleService-Info.plist from secure team storage (not Git)
2. Place it in `LotusPlannerV3/LotusPlannerV3/` directory
3. Build and run - migration will happen automatically

## 🔧 Troubleshooting

### Configuration Validation Fails
- Check console output for specific missing values
- Verify GoogleService-Info.plist exists and has correct values
- Ensure environment variables are set correctly

### Keychain Migration Issues
- Migration happens automatically on first launch
- Check console for migration success/failure messages
- Clear app data if migration fails and retry

### Token Storage Issues
- Tokens are now stored securely in iOS Keychain
- Use "Clear All Auth State" in settings if issues persist
- Check device keychain permissions

## 📱 Testing Security

### Before Production Release
1. ✅ Verify no API keys in Git history
2. ✅ Test keychain storage on device (not simulator)
3. ✅ Verify production environment settings
4. ✅ Test token refresh and storage
5. ✅ Test account unlinking and cleanup

### Security Checklist
- [ ] GoogleService-Info.plist not in version control
- [ ] All tokens stored in Keychain (not UserDefaults)
- [ ] Production environment configured
- [ ] Configuration validation passes
- [ ] No hardcoded secrets in code
- [ ] Proper error handling for security failures

## 🆘 Emergency Procedures

### If API Keys Are Compromised
1. Immediately rotate all Google API keys
2. Update GoogleService-Info.plist or environment variables
3. Force users to re-authenticate (clear auth state)
4. Review access logs for suspicious activity

### If Keychain Issues Occur
1. Use `clearAllAuthState()` method to reset
2. Users will need to re-authenticate
3. Check iOS keychain permissions
4. Verify app signing and entitlements

---

**⚠️ CRITICAL**: Never commit GoogleService-Info.plist or any file containing actual API keys to version control!
