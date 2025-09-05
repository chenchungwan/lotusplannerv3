#!/bin/bash

# Security Validation Script for LotusPlannerV3
# This script checks for common security issues before production deployment

echo "🔒 LotusPlannerV3 Security Validation"
echo "===================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Check 1: Ensure GoogleService-Info.plist is not in version control
echo -n "Checking if GoogleService-Info.plist is in .gitignore... "
if grep -q "GoogleService-Info.plist" .gitignore; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "  GoogleService-Info.plist should be in .gitignore"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check 2: Ensure no API keys in Git history
echo -n "Checking for API keys in current files... "
if grep -r "AIzaSy" --include="*.swift" --include="*.plist" LotusPlannerV3/ 2>/dev/null | grep -v "Template" | grep -v "YOUR_API_KEY_HERE"; then
    echo -e "${RED}❌ FAIL${NC}"
    echo "  Found potential API keys in tracked files"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "${GREEN}✅ PASS${NC}"
fi

# Check 3: Ensure KeychainManager is used
echo -n "Checking if KeychainManager is implemented... "
if grep -q "KeychainManager" LotusPlannerV3/LotusPlannerV3/GoogleAuthManager.swift; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "  KeychainManager not found in GoogleAuthManager"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check 4: Ensure production environment
echo -n "Checking for production environment settings... "
if grep -q "production" LotusPlannerV3/LotusPlannerV3/LotusPlannerV3.entitlements; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "  Environment should be set to production"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check 5: Ensure UserDefaults token storage is removed
echo -n "Checking for insecure UserDefaults token storage... "
if grep -n "UserDefaults.*token" LotusPlannerV3/LotusPlannerV3/GoogleAuthManager.swift | grep -v "migration" | grep -v "cleanup" | grep -v "expiry" | grep -v "email" | grep -v "custom"; then
    echo -e "${YELLOW}⚠️  WARNING${NC}"
    echo "  Found potential UserDefaults token usage (review manually)"
    echo "  This might be acceptable for non-sensitive data like expiry dates"
else
    echo -e "${GREEN}✅ PASS${NC}"
fi

# Check 6: Ensure template file exists
echo -n "Checking if template file exists... "
if [ -f "LotusPlannerV3/LotusPlannerV3/GoogleService-Info-Template.plist" ]; then
    echo -e "${GREEN}✅ PASS${NC}"
else
    echo -e "${RED}❌ FAIL${NC}"
    echo "  GoogleService-Info-Template.plist should exist for team setup"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check 7: Ensure actual config file exists (for local development)
echo -n "Checking if actual config file exists... "
if [ -f "LotusPlannerV3/LotusPlannerV3/GoogleService-Info.plist" ]; then
    echo -e "${GREEN}✅ PASS${NC}"
    # Additional check: ensure it's not the template
    if grep -q "YOUR_CLIENT_ID_HERE" LotusPlannerV3/LotusPlannerV3/GoogleService-Info.plist 2>/dev/null; then
        echo -e "${YELLOW}⚠️  WARNING${NC}"
        echo "  GoogleService-Info.plist contains template values"
        echo "  Replace with actual values for the app to work"
    fi
else
    echo -e "${YELLOW}⚠️  WARNING${NC}"
    echo "  GoogleService-Info.plist not found"
    echo "  Copy from template and configure with actual values"
fi

echo ""
echo "===================================="
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}🎉 Security validation passed!${NC}"
    echo "The app appears to be configured securely for production."
else
    echo -e "${RED}❌ Found $ISSUES_FOUND security issues${NC}"
    echo "Please address the issues above before production deployment."
    exit 1
fi

echo ""
echo "Next steps:"
echo "1. Test keychain storage on a real device"
echo "2. Verify token refresh works correctly"
echo "3. Test account unlinking and re-authentication"
echo "4. Review all console output for security warnings"
