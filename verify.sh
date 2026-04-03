#!/bin/bash
#
# Verify the key findings from the Chrome extension audit.
# Usage: ./verify.sh [source_directory]
#
# This script searches the extracted extension source for the specific
# code patterns documented in the audit report.

DIR="${1:-source}"

if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' not found."
    echo ""
    echo "Usage: ./verify.sh [extracted_source_directory]"
    echo ""
    echo "To get started:"
    echo "  curl -L -o extension.crx 'https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx2,crx3&x=id%3Dkbecnmcienhaopoibckmbijngmcakplf%26uc'"
    echo "  python3 extract.py extension.crx"
    echo "  ./verify.sh source"
    exit 1
fi

echo "========================================"
echo "  Chrome Extension Audit Verification"
echo "========================================"
echo ""
echo "Target directory: $DIR"
echo ""

PASS=0
FAIL=0

check() {
    local label="$1"
    local pattern="$2"
    local description="$3"

    RESULT=$(grep -rl "$pattern" "$DIR" 2>/dev/null)
    if [ -n "$RESULT" ]; then
        echo "[FOUND]  $label"
        echo "         $description"
        echo "         File(s): $RESULT"
        PASS=$((PASS + 1))
    else
        echo "[NOT FOUND] $label"
        FAIL=$((FAIL + 1))
    fi
    echo ""
}

echo "--- Finding 1: Silent Profile Upload ---"
echo ""

check \
    "Backend API endpoint" \
    "ai-tutor/linkedin-profile" \
    "POST endpoint for uploading profile data to api.jiangren.com.au"

check \
    "Backend base URL" \
    "api.jiangren.com.au" \
    "Hardcoded backend server URL"

check \
    "Automatic trigger (PAGE_TYPE_CHANGED)" \
    "PAGE_TYPE_CHANGED" \
    "Event handler that auto-fires when user visits a LinkedIn profile"

check \
    "3-second delay before extraction" \
    "3e3" \
    "setTimeout(3000ms) delay in the service worker"

echo "--- Finding 2: Alumni Check Leaks Browsing History ---"
echo ""

check \
    "Alumni check endpoint" \
    "alumni/check" \
    "Sends LinkedIn URL + name to backend on every profile visit"

echo "--- Finding 3: Insecure Cookie Configuration ---"
echo ""

check \
    "SameSite=None cookies" \
    "no_restriction" \
    "Cookies set with sameSite: no_restriction (SameSite=None)"

check \
    "Session Storage access level" \
    "TRUSTED_AND_UNTRUSTED_CONTEXTS" \
    "Session storage opened to untrusted contexts (content scripts)"

echo "--- Finding 4: Privacy Policy Contradictions ---"
echo ""

check \
    "isOwnProfile field exists" \
    "isOwnProfile" \
    "Developer distinguishes own/other profiles but uploads both"

echo "========================================"
echo "  Results: $PASS found, $FAIL not found"
echo "========================================"

if [ $FAIL -eq 0 ]; then
    echo "  All audit findings verified."
else
    echo "  Some patterns not found. The extension may have been updated."
fi
