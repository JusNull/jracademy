# Evidence Archive

This directory contains the original Chrome extension package and key source files preserved for independent verification. The extension may be updated or removed from the Chrome Web Store at any time.

## Download Date

2026-04-03

## Archived External Sources

| Source | Live URL | Wayback Machine Archive |
|--------|----------|------------------------|
| JR Academy Privacy Policy | https://jiangren.com.au/privacy-policy | [2026-04-03 snapshot](https://web.archive.org/web/20260403061621/https://jiangren.com.au/privacy-policy) |
| Chrome Web Store Listing | https://chromewebstore.google.com/detail/kbecnmcienhaopoibckmbijngmcakplf | [2026-04-03 snapshot](https://web.archive.org/web/20260403061642/https://chromewebstore.google.com/detail/%E6%B1%82%E8%81%8C%E5%8C%A0-job-hunter/kbecnmcienhaopoibckmbijngmcakplf) |

These archives preserve the state of external sources at the time of the audit, in case they are later modified or removed.

## Extension Version

0.9.18 (as declared in manifest.json)

## How This Was Obtained

```bash
curl -L -o extension.crx \
  "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx2,crx3&x=id%3Dkbecnmcienhaopoibckmbijngmcakplf%26uc"
```

This is Google's public update API. Any Chrome extension's CRX can be downloaded this way.

## File Integrity (SHA-256)

```
c34771c4e288aaff727776c1083e69cf3d9efebbc1f5109e375975cfc26a099b  extension.crx
328d2fcc6b36d31707ed54d66890e9e706fee6d8b905e9a72af1d11ddfb04b03  manifest.json
cc79789b78cd750fd280a7720165168a1c2495c0367ab057bc422584557194ff  verified_contents.json
100571de5e9c6ae4b7ffd67d379f99d91c7f1489fac91eef24a35b50a80c787b  key-source-files/content-script.ts-JvBoJEXM.js
17751d64278825e8b223a1391b3d4730e541e32506d19776974c41c57030a009  key-source-files/profile-extractor-C60-IxP0.js
4f1d524f554816aed8d81939d4313ffa11b4377946a20ac5a8a5a5babc441048  key-source-files/service-worker.ts-BSerYTM6.js
0a2691deb372655a90316f35f44cb880be3fe8b0532e7c8e098954b7afede93f  key-source-files/storage-suDUeHVU.js
```

Verify with: `shasum -a 256 <file>`

## Contents

| File | Description | Relevance |
|------|-------------|-----------|
| `extension.crx` | Original CRX3 package from Chrome Web Store | Complete extension archive — extract with `python3 ../extract.py extension.crx` |
| `verified_contents.json` | Google-signed content verification data | Cryptographic proof of the CRX contents at time of publication |
| `manifest.json` | Extension manifest | Declares permissions (cookies, tabs, scripting) and host permissions |
| `key-source-files/service-worker.ts-BSerYTM6.js` | Service Worker | **Contains `R()` upload function and `PAGE_TYPE_CHANGED` auto-trigger** |
| `key-source-files/storage-suDUeHVU.js` | Storage module | **Contains `sameSite: "no_restriction"` cookie configuration** |
| `key-source-files/profile-extractor-C60-IxP0.js` | Profile Extractor | **Contains DOM extraction logic for all 15+ profile fields** |
| `key-source-files/content-script.ts-JvBoJEXM.js` | Content Script | Entry point that detects page types and dispatches extractors |

## Quick Verification

```bash
# Search for the upload endpoint in the service worker
grep "ai-tutor/linkedin-profile" key-source-files/service-worker.ts-BSerYTM6.js

# Search for the automatic trigger
grep "PAGE_TYPE_CHANGED" key-source-files/service-worker.ts-BSerYTM6.js

# Search for SameSite=None
grep "no_restriction" key-source-files/storage-suDUeHVU.js

# Or run the full verification script
cd .. && ./verify.sh evidence/key-source-files/../..
```
