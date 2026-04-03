#!/bin/bash
#
# Verify that the evidence CRX in this repo matches what Google serves.
# Usage: ./verify-integrity.sh

EXTENSION_ID="kbecnmcienhaopoibckmbijngmcakplf"
EVIDENCE_CRX="evidence/extension.crx"
EXPECTED_HASH="c34771c4e288aaff727776c1083e69cf3d9efebbc1f5109e375975cfc26a099b"
TEMP_CRX=$(mktemp /tmp/fresh_crx_XXXXXX.crx)

echo "========================================"
echo "  CRX Integrity Verification"
echo "========================================"
echo ""

if [ ! -f "$EVIDENCE_CRX" ]; then
    echo "Error: $EVIDENCE_CRX not found. Run from repo root."
    rm -f "$TEMP_CRX"
    exit 1
fi

echo "[1] Local evidence file (archived 2026-04-03, v0.9.18):"
LOCAL_HASH=$(shasum -a 256 "$EVIDENCE_CRX" | awk '{print $1}')
echo "    SHA-256: $LOCAL_HASH"
if [ "$LOCAL_HASH" = "$EXPECTED_HASH" ]; then
    echo "    Status:  MATCHES expected hash"
else
    echo "    Status:  WARNING — does not match expected hash!"
    echo "    Expected: $EXPECTED_HASH"
fi
echo ""

echo "[2] Downloading fresh copy from Google..."
curl -sL -o "$TEMP_CRX" \
    "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx2,crx3&x=id%3D${EXTENSION_ID}%26uc"

if [ ! -s "$TEMP_CRX" ]; then
    echo "    Download failed — extension may have been removed."
    echo "    The archived CRX remains the only preserved copy."
    rm -f "$TEMP_CRX"
    exit 0
fi

REMOTE_HASH=$(shasum -a 256 "$TEMP_CRX" | awk '{print $1}')
echo "    SHA-256: $REMOTE_HASH"
echo ""

echo "[3] Result:"
if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
    echo "    IDENTICAL — archived CRX matches Google's current version."
else
    echo "    DIFFERENT — extension has been updated since archival."
    echo "    The archived v0.9.18 remains valid evidence of behavior at that time."
fi

rm -f "$TEMP_CRX"
echo ""
