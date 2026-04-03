# Chrome 扩展安全审计报告：静默数据外传的技术取证

> 审计对象：某求职辅助类 Chrome 扩展（v0.9.x）
> 审计方法：从 Chrome Web Store 下载 CRX 包，解压后对全部 JS 源码进行静态分析
> 审计原则：仅记录可从代码中直接验证的事实，不做推测

---

## 摘要

本次审计在该扩展的 Service Worker 源码中发现一个**自动数据外传机制**：当用户浏览特定职业社交平台（下称 "L 平台"）的个人资料页面时，扩展在**无需任何用户操作**的情况下，自动提取页面上的完整个人资料数据，并通过 HTTP POST 请求上传至开发者的后端服务器。

该行为与扩展自身隐私政策中"不被动监控浏览行为"、"仅在用户主动触发时采集数据"的声明**直接矛盾**。

以下所有结论均附有对应的源代码片段，可独立复现验证。

---

## 1. 事实一：存在自动数据外传机制

### 1.1 上报函数

Service Worker 中存在一个数据上报函数（混淆后为 `R()`），其功能为将 L 平台个人资料数据通过 POST 请求发送至后端 API：

```javascript
// Service Worker 源码（反混淆后的等价逻辑）
let lastReportedUrl = "";
let lastReportedTime = 0;

function reportProfileToServer(profileData) {
    // 校验：必须包含姓名和 URL
    if (!profileData?.name || !profileData?.profileUrl) return;

    const url = profileData.profileUrl;
    const now = Date.now();

    // 节流：相同 URL 10 秒内不重复上报
    if (url === lastReportedUrl && now - lastReportedTime < 10000) return;
    lastReportedUrl = url;
    lastReportedTime = now;

    // 构造带认证的请求头
    getAuthHeaders().then(headers => {
        // 仅在用户已登录时上传
        headers.Authorization && fetch(
            "https://api.*****.com.au/ai-tutor/linkedin-profile",
            {
                method: "POST",
                headers: headers,
                body: JSON.stringify(profileData)
            }
        ).catch(() => {})   // 静默失败，不通知用户
    }).catch(() => {})
}
```

**原始混淆代码对照（可在 CRX 解压后直接搜索验证）：**

```javascript
function R(e){if(!(e!=null&&e.name)||!(e!=null&&e.profileUrl))return;const t=e.profileUrl,a=Date.now();t===J&&a-j<1e4||(J=t,j=a,m().then(r=>{r.Authorization&&fetch(y("/ai-tutor/linkedin-profile"),{method:"POST",headers:r,body:JSON.stringify(e)}).catch(()=>{})}).catch(()=>{}))}
```

其中 `y()` 函数定义为：

```javascript
const me = "https://api.*****.com.au";
function y(e) { return `${me}${e}` }
```

**可验证事实：**
- 目标端点：`https://api.*****.com.au/ai-tutor/linkedin-profile`
- 请求方法：POST
- 请求体：`JSON.stringify(profileData)` — 即完整的个人资料 JSON
- 认证：携带 `Authorization: Bearer <token>` 和 `x-device-id` 头
- 错误处理：`.catch(() => {})` — 静默吞掉所有错误

### 1.2 自动触发点

该上报函数的核心调用位于 `PAGE_TYPE_CHANGED` 消息处理器中：

```javascript
// Service Worker — 消息监听器（反混淆后的等价逻辑）
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === "PAGE_TYPE_CHANGED") {
        const tabId = sender.tab?.id;
        // ...
        // 当页面类型为 "profile" 时，延迟 3 秒后自动提取并上传
        message.payload.pageType === "profile" && tabId && setTimeout(() => {
            chrome.tabs.sendMessage(tabId, { type: "EXTRACT_PROFILE_DATA" })
                .then(result => {
                    result?.profileData && reportProfileToServer(result.profileData)
                })
                .catch(() => {})
        }, 3000)
        return false;
    }
    // ...
});
```

**原始混淆代码对照：**

```javascript
if(e.type==="PAGE_TYPE_CHANGED"){const i=(o=t.tab)==null?void 0:o.id;return i!==void 0&&(q.set(i,e.payload.pageType),chrome.runtime.sendMessage({type:"PAGE_TYPE_CHANGED",payload:e.payload}).catch(()=>{}),e.payload.pageType==="profile"&&i&&setTimeout(()=>{chrome.tabs.sendMessage(i,{type:"EXTRACT_PROFILE_DATA"}).then(l=>{l!=null&&l.profileData&&R(l.profileData)}).catch(()=>{})},3e3)),!1}
```

**可验证事实：**
- 触发条件：Content Script 检测到当前页面为 L 平台的 profile 页面，发送 `PAGE_TYPE_CHANGED` 消息
- 用户操作：**无** — 用户仅需正常浏览 L 平台的个人资料页面
- 延迟：3000 毫秒（`3e3`）
- 执行链：`setTimeout` → `sendMessage(EXTRACT_PROFILE_DATA)` → 收到结果 → `R(profileData)`
- 整个链条中**没有任何用户确认步骤**

### 1.3 上传的数据结构

通过分析 Profile Extractor 模块（Content Script 端），`EXTRACT_PROFILE_DATA` 返回的 `profileData` 对象包含以下字段：

```javascript
{
    name: "完整姓名",
    headline: "职业标题",
    about: "个人简介（完整文本）",
    location: "所在地",
    profileUrl: "L 平台个人主页 URL",
    isOwnProfile: false,              // 是否是用户自己的页面
    experience: [                      // 完整工作经历
        {
            title: "职位名称",
            company: "公司名称",
            duration: "时间段",
            description: "职位描述（最多 2000 字符）",
            isCurrent: true/false
        }
        // ...
    ],
    education: [                       // 完整教育经历
        {
            school: "学校名称",
            degree: "学位",
            field: "专业",
            years: "年份"
        }
        // ...
    ],
    skills: ["技能1", "技能2", ...],   // 完整技能列表
    certifications: [...],             // 专业认证
    languages: [...],                  // 语言能力
    volunteerExperience: [...],        // 志愿者经历
    profileImageUrl: "头像 URL",
    connectionLevel: "1st/2nd/3rd",    // 人脉关系级别
    connections: "500+ connections"     // 人脉数量描述
}
```

**可验证事实（Profile Extractor 中的提取函数）：**
- `Q()` — 提取工作经历，description 字段截取前 2000 字符：`.substring(0, 2000)`
- `V()` — 提取教育经历
- `z()` — 提取技能列表
- `G()` — 提取认证信息
- `K()` — 提取语言能力
- `X()` — 提取志愿者经历
- `Z()` — 提取头像 URL
- `Y()` — 提取人脉关系级别

以上函数均通过 DOM 选择器从页面中提取数据，最终由 `T()` / `B()` 函数聚合为完整的 profileData 对象。

---

## 2. 事实二：自动校友查询泄露浏览记录

### 2.1 查询机制

Service Worker 中存在校友检查函数（混淆后为 `_e()`），向后端 API 发送查询请求：

```javascript
// 反混淆后的等价逻辑
async function checkAlumni(linkedinUrl, name) {
    const cached = alumniCache.get(linkedinUrl);
    if (cached) return cached;

    const headers = await getAuthHeaders();
    const params = new URLSearchParams({ linkedinUrl, name });
    const response = await fetch(
        `https://api.*****.com.au/ai-tutor/alumni/check?${params}`,
        { headers }
    );
    // ...
}
```

**原始混淆代码对照：**

```javascript
async function _e(e,t){const a=I.get(e);if(a)return a;try{const o=await m(),n=new URLSearchParams({linkedinUrl:e,name:t}),s=await fetch(y(`/ai-tutor/alumni/check?${n}`),{headers:o});
```

### 2.2 自动触发

该查询由 Content Script 在检测到 profile 页面时自动发起 `CHECK_JR_ALUMNI` 消息，**无需用户操作**。

**可验证事实：**
- 目标端点：`GET https://api.*****.com.au/ai-tutor/alumni/check?linkedinUrl=xxx&name=xxx`
- 发送的数据：被浏览者的 L 平台 URL + 姓名
- 影响：后端可记录"哪些 L 平台用户被扩展用户浏览过"，构成浏览行为追踪

---

## 3. 事实三：隐私政策与代码行为直接矛盾

### 3.1 矛盾一：「不被动监控」

**隐私政策原文（Section 1.3）：**

> "We do not passively monitor your browsing activity."
>
> "No background data collection, automatic screenshots, or passive browsing monitoring occurs."

**代码事实：**

`PAGE_TYPE_CHANGED` 处理器在用户浏览 L 平台 profile 页面时**自动触发**数据提取和上传，用户未执行任何操作。这在定义上属于 "passive browsing monitoring" 和 "background data collection"。

### 3.2 矛盾二：「仅在主动触发时采集」

**隐私政策原文（Section 1.3）：**

> "Our Chrome browser extensions collect additional data only when you actively use their features."
>
> "Screenshots and content extraction occur only when you explicitly trigger them (e.g., pressing a keyboard shortcut or clicking a button)."

**代码事实：**

`PAGE_TYPE_CHANGED` → `setTimeout(3000)` → `EXTRACT_PROFILE_DATA` → `R()` 这个完整链条中，**不存在任何检查用户操作的代码**。没有按钮点击检测、没有键盘快捷键检测、没有用户确认弹窗。唯一的触发条件是页面 URL 匹配 L 平台 profile 模式。

### 3.3 矛盾三：数据采集范围低报

**隐私政策原文（Section 1.3 表格）：**

> | Extension | Data Collected |
> |-----------|---------------|
> | [扩展名] | **Job posting content** from supported job sites; current page URL |

**代码事实：**

如第 1.3 节所述，实际上传的数据包含完整的个人资料对象（姓名、经历、教育、技能、认证、语言、志愿者经历、头像、联系级别等 15+ 个字段）。这些数据类型在隐私政策中**完全未提及**。

### 3.4 矛盾四：第三方数据采集完全未披露

**隐私政策：**

Section 1 的标题为 "Information **You** Provide to Us" 和 "Information Collected **Automatically**"，暗示所有数据采集对象为扩展用户本人。整份隐私政策**从未提及**会采集第三方用户（即被浏览的 L 平台用户）的个人信息。

**代码事实：**

`R()` 函数上传的 profileData 中，`isOwnProfile` 字段的存在证明开发者明确区分了"自己的页面"和"他人的页面"。代码中 `R()` 函数**不检查 `isOwnProfile` 的值**——无论是自己的还是他人的页面，数据都会被上传。

```javascript
// Profile Extractor — isOwnProfile 检测函数
function J() {
    // 检查页面上是否有 "Edit intro"、"Add profile section" 等仅自己页面可见的按钮
    const editButtons = [
        'button[aria-label*="Edit intro"]',
        'button[aria-label*="Add profile section"]',
        // ...
    ];
    // 如果找到这些按钮，说明是自己的页面
    // ...
}
```

```javascript
// R() 函数 — 不检查 isOwnProfile
function R(e) {
    if (!(e?.name) || !(e?.profileUrl)) return;  // 仅校验姓名和 URL 存在
    // 没有 if (e.isOwnProfile) return; 这样的检查
    // 直接上传
    // ...
}
```

**可验证事实：** 开发者在 Profile Extractor 中实现了 `isOwnProfile` 检测，说明明确知道存在"浏览他人页面"的场景。但上报函数中没有基于此字段做任何过滤。

---

## 4. 事实四：Cookie 安全配置不当

### 4.1 跨站 Cookie 配置

Storage 模块中，扩展将认证 token 和用户信息写入后端域名的 Cookie：

```javascript
// Storage 模块 — 原始混淆代码
await chrome.cookies.set({
    url: a,                          // "https://*****.com.au"
    name: r,                         // token cookie name
    value: e,                        // 明文 token
    path: "/",
    secure: true,
    sameSite: "no_restriction",      // ← SameSite=None
    expirationDate: Math.floor(Date.now() / 1e3) + 30 * 86400  // 30 天
});

await chrome.cookies.set({
    url: a,
    name: c,                         // user info cookie name
    value: encodeURIComponent(JSON.stringify(t)),  // 用户信息 JSON
    path: "/",
    secure: true,
    sameSite: "no_restriction",      // ← SameSite=None
    expirationDate: Math.floor(Date.now() / 1e3) + 30 * 86400
});
```

**可验证事实：**
- `sameSite: "no_restriction"` 等同于 `SameSite=None`，允许任何第三方网站在跨站请求中携带这些 Cookie
- 认证 token 以明文存储
- 用户信息以 `encodeURIComponent(JSON.stringify())` 格式存储，无加密
- 有效期 30 天
- 未设置 `httpOnly` 标志（Chrome extension cookie API 不支持此参数，但这意味着页面脚本可通过 `document.cookie` 读取）

### 4.2 Session Storage 访问级别

```javascript
// Service Worker 末尾 — 原始代码
chrome.storage.session.setAccessLevel({
    accessLevel: "TRUSTED_AND_UNTRUSTED_CONTEXTS"
})
```

**可验证事实：** 默认值为 `TRUSTED_CONTEXTS`（仅扩展页面可访问）。设置为 `TRUSTED_AND_UNTRUSTED_CONTEXTS` 后，运行在第三方网页中的 Content Script 也可访问 session storage。

---

## 5. 需要澄清的部分：合理的本地功能

为确保报告的公正性，以下模块经代码验证**不存在自动回传后端的行为**，属于合理的本地用户功能：

| 模块 | 功能 | 数据流向 | 是否调用后端 API |
|------|------|---------|----------------|
| Connections Extractor + Classifier | 提取并分类用户人脉列表 | Content Script → Sidepanel（本地展示） | **否** |
| Message Extractor + Classifier | 提取并分类私信内容 | Content Script → Sidepanel（本地展示） | **否** |
| Feed Scanner | 扫描动态流中的招聘帖 | Content Script 本地处理 + DOM 注入 UI 标记 | **否** |
| Company Extractor | 提取公司页面信息 | Content Script → Sidepanel（本地展示） | **否** |
| Message Quick Reply | 快速回复模板 | 本地 DOM 注入 | **否** |
| Post Injector | 向编辑器注入内容 | 本地 DOM 操作 | **否** |
| Profile SEO Scorer | 计算个人资料 SEO 评分 | 本地计算 | **否**（但评分结果随 profile 数据一起上传） |
| Job Save（右键菜单） | 保存职位到后端 | Content Script → 后端 | 是，但为**用户主动触发**且保存的是职位信息 |

**验证方法：** 在 Service Worker 的消息处理器中，以上模块对应的 `case` 分支均调用 `p()` 函数（向 Content Script 转发消息并返回结果），**不调用 `R()` 函数或任何 `fetch()`**。

---

## 6. 复现指南

任何人可通过以下步骤独立验证本报告的全部结论：

### 6.1 获取源码

```bash
# 下载 CRX 包
curl -L -o extension.crx \
  "https://clients2.google.com/service/update2/crx?response=redirect\
&prodversion=131.0.0.0&acceptformat=crx2,crx3\
&x=id%3D<EXTENSION_ID>%26uc"

# 提取 ZIP（Python）
python3 -c "
import struct, zipfile
with open('extension.crx','rb') as f:
    f.read(4)  # magic
    f.read(4)  # version
    hl = struct.unpack('<I', f.read(4))[0]
    f.seek(12+hl)
    open('ext.zip','wb').write(f.read())
zipfile.ZipFile('ext.zip').extractall('source')
"
```

### 6.2 验证自动上传

1. 在 `source/assets/` 目录下找到 Service Worker 文件（文件名含 `service-worker`）
2. 搜索字符串 `ai-tutor/linkedin-profile` — 确认 POST 端点存在
3. 搜索字符串 `PAGE_TYPE_CHANGED` — 确认自动触发机制
4. 追踪调用链：`PAGE_TYPE_CHANGED` → `"profile"` 判断 → `setTimeout(3e3)` → `EXTRACT_PROFILE_DATA` → `R()` → `fetch(POST)`
5. 确认 `R()` 函数中**不存在**任何用户确认步骤

### 6.3 验证隐私政策矛盾

1. 访问扩展开发者官网的隐私政策页面
2. 搜索 "passively monitor" — 找到 "We do not passively monitor your browsing activity"
3. 搜索 "explicitly trigger" — 找到 "content extraction occur only when you explicitly trigger them"
4. 搜索 Section 1.3 的数据采集表格 — 确认仅声明 "Job posting content" 和 "current page URL"
5. 对照第 1 节的代码证据

---

## 附录：审计局限性

1. 代码经 Vite 构建压缩，变量名被混淆。本报告中的函数名称（如 `R()`、`_e()`）为混淆后的名称，反混淆后的名称为分析者推断，但**代码逻辑和调用关系可直接从混淆代码中验证**
2. 未对后端 API 进行主动测试。后端实际存储、保留、共享数据的方式未知
3. Sidepanel 主文件（300KB+ React 应用）未完整审阅，AI 聊天功能发送的 `context` 字段具体内容未确认
4. 未进行动态运行时抓包验证。以上结论基于静态代码分析，实际网络请求可通过浏览器开发者工具或抓包工具独立验证
5. 本报告仅记录技术事实，不构成法律意见
