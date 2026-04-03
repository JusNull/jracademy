# 「求職匠 Job Hunter」Chrome 擴充功能如何在你不知情的情況下上傳你瀏覽的每一個 LinkedIn 個人檔案

## JR Academy Chrome 擴充功能安全審計：靜默資料外傳的技術取證

> **審計對象**：求職匠 Job Hunter v0.9.18（Chrome Web Store ID: `kbecnmcienhaopoibckmbijngmcakplf`）
>
> **開發者**：JR Academy Pty Ltd（https://jiangren.com.au），澳洲匠人學院
>
> **審計方法**：從 Chrome Web Store 下載 CRX 套件，解壓後對全部 JS 原始碼進行靜態分析
>
> **審計原則**：本報告僅記錄可從原始碼中直接驗證的事實，不做推測

---

## 摘要

**求職匠 Job Hunter** 是由 [JR Academy（匠人學院）](https://jiangren.com.au) 開發的 Chrome 瀏覽器擴充功能，宣稱提供 AI 求職輔助功能。然而，對其原始碼的完整審計揭露了一個**隱藏的自動資料外傳機制**：當安裝了該擴充功能的使用者瀏覽**任何** LinkedIn 個人檔案頁面時，擴充功能會在**完全無需使用者操作**的情況下，自動擷取該頁面上的完整個人檔案資料（姓名、工作經歷、學歷、技能等 15+ 個欄位），並透過 HTTP POST 請求靜默上傳至 `api.jiangren.com.au`。

JR Academy 自己的隱私政策明確聲明：

> *「We do not passively monitor your browsing activity」*（我們不會被動監控您的瀏覽活動）
>
> *「Content extraction occur only when you explicitly trigger them」*（內容擷取僅在您主動觸發時才會發生）

原始碼證明事實恰恰相反。

**[English Version](README.md)** | **[简体中文版](README.zh-CN.md)**

---

## 目錄

1. [鐵證：自動上傳個人檔案資料](#1-鐵證自動上傳個人檔案資料)
2. [校友查詢洩露瀏覽記錄](#2-自動校友查詢洩露瀏覽記錄)
3. [隱私政策與實際行為的直接矛盾](#3-隱私政策與實際行為的直接矛盾)
4. [不安全的 Cookie 設定](#4-不安全的-cookie-設定)
5. [本報告不主張的部分](#5-本報告不主張的部分)
6. [更廣泛的啟示](#6-更廣泛的啟示)
7. [獨立驗證指南](#7-獨立驗證指南)

---

## 1. 鐵證：自動上傳個人檔案資料

### 1.1 上傳函式

Service Worker 中存在一個資料上報函式（混淆後為 `R()`），功能為將 LinkedIn 個人檔案資料透過 POST 請求傳送至 JR Academy 的後端伺服器：

```javascript
// 反混淆後的等價邏輯
let lastReportedUrl = "";
let lastReportedTime = 0;

function reportProfileToServer(profileData) {
    if (!profileData?.name || !profileData?.profileUrl) return;

    const url = profileData.profileUrl;
    const now = Date.now();

    // 節流：相同 URL 10 秒內不重複上報
    if (url === lastReportedUrl && now - lastReportedTime < 10000) return;
    lastReportedUrl = url;
    lastReportedTime = now;

    getAuthHeaders().then(headers => {
        // 僅在使用者已登入時上傳
        headers.Authorization && fetch(
            "https://api.jiangren.com.au/ai-tutor/linkedin-profile",
            {
                method: "POST",
                headers: headers,
                body: JSON.stringify(profileData)  // 完整個人檔案物件
            }
        ).catch(() => {})  // 靜默吞掉所有錯誤
    }).catch(() => {})
}
```

**原始混淆程式碼**（可在解壓後的 CRX 中搜尋驗證 — 檔案 `assets/service-worker.ts-BSerYTM6.js`）：

```javascript
function R(e){if(!(e!=null&&e.name)||!(e!=null&&e.profileUrl))return;const t=e.profileUrl,a=Date.now();t===J&&a-j<1e4||(J=t,j=a,m().then(r=>{r.Authorization&&fetch(y("/ai-tutor/linkedin-profile"),{method:"POST",headers:r,body:JSON.stringify(e)}).catch(()=>{})}).catch(()=>{}))}
```

其中 `y()` 函式定義為：

```javascript
const me = "https://api.jiangren.com.au";
function y(e) { return `${me}${e}` }
```

### 1.2 自動觸發機制

該上傳函式的核心呼叫位於 `PAGE_TYPE_CHANGED` 訊息處理器中 — 當使用者瀏覽任何 LinkedIn 個人檔案頁面時**自動觸發**：

```javascript
// 反混淆後的等價邏輯
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "PAGE_TYPE_CHANGED") {
        const tabId = sender.tab?.id;

        // 當頁面類型為 "profile" — 延遲 3 秒後觸發
        message.payload.pageType === "profile" && tabId && setTimeout(() => {
            chrome.tabs.sendMessage(tabId, { type: "EXTRACT_PROFILE_DATA" })
                .then(result => {
                    result?.profileData && reportProfileToServer(result.profileData)
                })
                .catch(() => {})
        }, 3000)

        return false;
    }
});
```

**原始混淆程式碼：**

```javascript
if(e.type==="PAGE_TYPE_CHANGED"){const i=(o=t.tab)==null?void 0:o.id;return i!==void 0&&(q.set(i,e.payload.pageType),chrome.runtime.sendMessage({type:"PAGE_TYPE_CHANGED",payload:e.payload}).catch(()=>{}),e.payload.pageType==="profile"&&i&&setTimeout(()=>{chrome.tabs.sendMessage(i,{type:"EXTRACT_PROFILE_DATA"}).then(l=>{l!=null&&l.profileData&&R(l.profileData)}).catch(()=>{})},3e3)),!1}
```

### 1.3 上傳的資料內容

`profileData` 物件包含以下欄位：

```javascript
{
    name:                "完整姓名",
    headline:            "職業頭銜",
    about:               "完整的「關於」區段文字",
    location:            "所在地",
    profileUrl:          "https://www.linkedin.com/in/...",
    isOwnProfile:        true/false,
    experience:          [{ title, company, duration, description, isCurrent }],
    education:           [{ school, degree, field, years }],
    skills:              ["技能1", "技能2", ...],
    certifications:      [...],           // 專業認證
    languages:           [...],           // 語言能力
    volunteerExperience: [...],           // 志工經歷
    profileImageUrl:     "https://...",   // 大頭貼 URL
    connectionLevel:     "1st/2nd/3rd",   // 人脈關係級別
    connections:         "500+ connections"
}
```

這不是摘要 — 而是涵蓋 **15+ 個資料欄位**的完整個人檔案擷取。

### 1.4 完整攻擊鏈

```
使用者瀏覽任何 LinkedIn 個人檔案頁面
    |
    v
Content Script 偵測到 URL 符合 linkedin.com/in/*
    |
    v
發送 PAGE_TYPE_CHANGED { pageType: "profile" } 至 Service Worker
    |
    v
Service Worker 等待 3 秒（setTimeout 3000ms）
    |
    v
向 Content Script 發送 EXTRACT_PROFILE_DATA 指令
    |
    v
Profile Extractor 解析整個頁面 DOM
    |
    v
Service Worker 收到完整的 profileData 物件
    |
    v
R() 將完整 JSON 透過 POST 傳送至 https://api.jiangren.com.au/ai-tutor/linkedin-profile
    |
    v
.catch(() => {})  — 使用者看不到任何東西，完全不知情
```

**整個過程中零使用者互動。**

---

## 2. 自動校友查詢洩露瀏覽記錄

Service Worker 中還包含一個校友檢查函式（混淆後為 `_e()`），在使用者每次瀏覽 LinkedIn 個人檔案頁面時，自動向 JR Academy 後端發送被瀏覽者的 URL 和姓名：

```javascript
async function checkAlumni(linkedinUrl, name) {
    const params = new URLSearchParams({ linkedinUrl, name });
    const response = await fetch(
        `https://api.jiangren.com.au/ai-tutor/alumni/check?${params}`,
        { headers: authHeaders }
    );
}
```

**原始混淆程式碼：**

```javascript
async function _e(e,t){const a=I.get(e);if(a)return a;try{const o=await m(),n=new URLSearchParams({linkedinUrl:e,name:t}),s=await fetch(y(`/ai-tutor/alumni/check?${n}`),{headers:o});
```

此查詢由 Content Script **自動發起，無需使用者操作**。後端因此可記錄每個擴充功能使用者瀏覽過的所有 LinkedIn 個人檔案。

---

## 3. 隱私政策與實際行為的直接矛盾

JR Academy 的隱私政策（最後更新日期 2026 年 3 月 16 日）做出了以下聲明，每一條都被程式碼直接推翻。

### 矛盾一：「不被動監控」

| 隱私政策聲明 | 程式碼事實 |
|-------------|-----------|
| *「We do not passively monitor your browsing activity.」* | `PAGE_TYPE_CHANGED` 處理器在使用者僅僅瀏覽 LinkedIn 個人檔案時就自動擷取並上傳資料，無需點擊、無需快捷鍵、無需同意。 |
| *「No background data collection, automatic screenshots, or passive browsing monitoring occurs.」* | 整個 `PAGE_TYPE_CHANGED` → 3 秒延遲 → `EXTRACT_PROFILE_DATA` → `R()` 鏈條完全在背景執行，零使用者互動。 |

### 矛盾二：「僅在主動觸發時擷取」

| 隱私政策聲明 | 程式碼事實 |
|-------------|-----------|
| *「Our Chrome browser extensions collect additional data only when you actively use their features.」* | 觸發條件是 URL 模式匹配，不是使用者操作。 |
| *「Content extraction occur only when you explicitly trigger them (e.g., pressing a keyboard shortcut or clicking a button).」* | 從 `PAGE_TYPE_CHANGED` 到 `R()` 的程式碼路徑中**不存在任何使用者互動檢查** — 沒有 `confirm()`、沒有點擊監聽器、沒有快捷鍵偵測。 |

### 矛盾三：資料擷取範圍嚴重低報

| 隱私政策聲明 | 程式碼事實 |
|-------------|-----------|
| 資料擷取範圍：*「Job posting content from supported job sites; current page URL」* | 實際上傳：完整姓名、頭銜、簡介、所在地、完整工作經歷、學歷、技能、認證、語言、志工經歷、大頭貼、人脈級別 — **15+ 個資料欄位，全部未揭露** |

### 矛盾四：第三方資料蒐集完全未揭露

隱私政策僅描述對擴充功能使用者本人資料的蒐集，**從未提及**會蒐集第三方 LinkedIn 使用者的個人資訊 — 即那些被瀏覽的個人檔案的擁有者。

`isOwnProfile` 欄位的存在證明開發者明確區分了「自己的頁面」和「他人的頁面」。然而上傳函式 `R()` **並不檢查此欄位** — 無論是自己的還是他人的個人檔案，都會被一律上傳：

```javascript
function R(e) {
    if (!(e?.name) || !(e?.profileUrl)) return;  // 僅校驗姓名和 URL 存在
    // 沒有 isOwnProfile 檢查 — 全部上傳
    // ...
}
```

---

## 4. 不安全的 Cookie 設定

認證 token 以 `SameSite=None` 儲存：

```javascript
await chrome.cookies.set({
    url: "https://jiangren.com.au",
    name: "jr_ext_token",
    value: token,                        // 明文 token
    sameSite: "no_restriction",          // SameSite=None — 任何第三方網站都能跨站攜帶此 Cookie
    expirationDate: now + 30 * 86400    // 30 天有效期
});

await chrome.cookies.set({
    url: "https://jiangren.com.au",
    name: "jr_ext_user",
    value: encodeURIComponent(JSON.stringify(userInfo)),  // 使用者資訊以明文 JSON 儲存
    sameSite: "no_restriction",
    expirationDate: now + 30 * 86400
});
```

Session Storage 存取層級也被提升，允許 Content Scripts（在第三方網頁上下文中執行）存取 session 資料：

```javascript
chrome.storage.session.setAccessLevel({
    accessLevel: "TRUSTED_AND_UNTRUSTED_CONTEXTS"
})
```

---

## 5. 本報告不主張的部分

為維護報告公信力，以下模組經程式碼驗證為**純本地功能**，不存在自動回傳後端的行為：

| 模組 | 是否呼叫後端 API？ | 結論 |
|------|-------------------|------|
| 人脈擷取 + 分類 | **否** | 本地功能 |
| 訊息擷取 + 分類 | **否** | 本地功能 |
| 動態流掃描 | **否** | 本地功能 |
| 公司資訊擷取 | **否** | 本地功能 |
| 快速回覆模板 | **否** | 本地功能 |
| 貼文注入 | **否** | 本地功能 |
| 職位收藏（右鍵選單） | 是，但為**使用者主動觸發** | 合理功能 |

這些是合理的本地功能。本報告僅聚焦於第 1-4 節所述的自動、靜默資料外傳行為。

---

## 6. 更廣泛的啟示

此案例揭示了一個被低估的攻擊面：**利用擴充功能使用者作為不知情的資料蒐集代理節點。**

與傳統爬蟲相比，此模式具有以下優勢（對攻擊者而言）：

- **繞過反機器人防護** — 請求來自真實瀏覽器，帶有真實的 Cookie 和 Session
- **分散 IP 位址** — 每個使用者有不同的 IP
- **利用已認證的 Session** — 可存取僅登入使用者可見的資料（如聯絡資訊、2nd/3rd 度人脈）
- **隨安裝量擴展** — 無需維護爬蟲基礎設施

假設有 1,000 名活躍使用者，每人每天瀏覽 10 個 LinkedIn 個人檔案，後端每天可累積 **10,000 份完整的職業個人檔案** — 零基礎設施成本。

---

## 7. 獨立驗證指南

所有發現均可在 5 分鐘內獨立驗證。

### 步驟 1：下載並解壓

```bash
# 下載 CRX
curl -L -o extension.crx \
  "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx2,crx3&x=id%3Dkbecnmcienhaopoibckmbijngmcakplf%26uc"

# 解壓（使用本專案提供的腳本）
python3 extract.py extension.crx
```

### 步驟 2：執行自動驗證

```bash
./verify.sh source/
```

### 步驟 3：手動驗證

```bash
# 搜尋上傳端點
grep -r "ai-tutor/linkedin-profile" source/

# 搜尋自動觸發機制
grep -r "PAGE_TYPE_CHANGED" source/

# 搜尋 SameSite=None Cookie
grep -r "no_restriction" source/

# 追蹤呼叫鏈：PAGE_TYPE_CHANGED → "profile" → setTimeout(3e3) → EXTRACT_PROFILE_DATA → R() → fetch(POST)
```

---

## 揭露時間線

| 日期 | 行動 |
|------|------|
| 2026-04-03 | 原始碼審計完成 |
| 2026-04-03 | 向 Google Chrome Web Store 及 LinkedIn Trust & Safety 提交舉報 |
| 2026-04-03 | 公開揭露 |
| 待定 | 向 JR Academy 提交正式隱私投訴（privacy@jiangren.com.au） |
| +30 天 | 向 OAIC（澳洲資訊專員辦公室）提出申訴 |

---

## 法律聲明

本分析透過對 Chrome Web Store 公開套件的靜態程式碼審查進行。未進行動態測試、後端 API 逆向工程或任何未授權存取。CRX 檔案可透過 Google 的 update API 公開下載 — 解壓並分析它們是標準的安全研究實務。

---

## 倉庫可用性聲明

本倉庫**不會**被維護者主動刪除或設為私有。如果本倉庫在任何時候變得無法存取，應視為受到**外部施壓、法律威脅或其他不可抗力因素**所致，而非維護者主動撤回報告內容。

作者對本報告中記錄的每一項技術事實負責。所有發現均可透過所附的證據和腳本獨立驗證。

建議讀者 **Fork 本倉庫**，以確保資訊持續可用。

---

## 授權條款

本報告以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 授權發布。您可以在標明出處的前提下自由分享和改編本報告。
