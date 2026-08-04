# Phase 2.11B-TCC Identity Fix — 只读审计

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| 目标 | 稳定 Debug 签名身份，使 ScreenCaptureKit TCC 在 rebuild 后仍可识别 |

---

## 1. 环境

| 项 | 值 |
|---|---|
| Xcode | **26.6** (17F113) |
| Target | `SpotifyLyrics`（唯一 PBXNativeTarget App） |
| Scheme | 无 shared scheme 文件；默认用 target 名 `SpotifyLyrics` |
| 本机 codesign 身份 | **`security find-identity -v -p codesigning` → 0 valid identities** |
| Xcode Accounts / IDEProvisioningTeams | **空 / 未配置** |

---

## 2. 当前签名设置（project.pbxproj）

### Target `SpotifyLyrics` — Debug (`110000002D83400000000008`)

| 设置 | 当前值 |
|---|---|
| `CODE_SIGN_STYLE` | **未设置**（等价于手动 + identity `-`） |
| `CODE_SIGN_IDENTITY` | **`"-"`（ad-hoc / Sign to Run Locally）** |
| `DEVELOPMENT_TEAM` | **未设置** |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.spotifylyrics.app` |
| `CODE_SIGN_ENTITLEMENTS` | `SpotifyLyrics/SpotifyLyrics.entitlements` |
| `ENABLE_DEBUG_DYLIB` | **未设置 → Xcode 默认 YES**（主 stub + `.debug.dylib`） |

### Target `SpotifyLyrics` — Release

| 设置 | 当前值 |
|---|---|
| `CODE_SIGN_IDENTITY` | `"-"`（ad-hoc） |
| `DEVELOPMENT_TEAM` | 未设置 |
| 本阶段策略 | **不修改 Release** |

### Project-level Debug/Release

同样 `CODE_SIGN_IDENTITY = "-"`，无 Team。

---

## 3. 当前构建产物 codesign（冻结前 ad-hoc）

路径：`DerivedData/Build/Products/Debug/SpotifyLyrics.app`

| 组件 | Identifier | CDHash | Signature | Team |
|---|---|---|---|---|
| App bundle | `com.spotifylyrics.app` | `b545ddd1…` | **adhoc** | not set |
| 主 executable | `com.spotifylyrics.app` | `b545ddd1…` | adhoc | not set |
| **SpotifyLyrics.debug.dylib** | **`SpotifyLyrics.debug`** | **`b9b39fe6…`** | adhoc | not set |

→ **主程序与 debug dylib 身份分裂**已证实。

---

## 4. Entitlements（`SpotifyLyrics.entitlements` + 运行时）

文件内容：

- `com.apple.security.automation.apple-events` = true  

运行时额外出现：

- `com.apple.security.get-task-allow` = true（Debug 注入）

**无** 麦克风 entitlement（符合「不请求麦克风」）。

---

## 5. Info.plist 用途说明

`GENERATE_INFOPLIST_FILE = YES`，Debug/Release 均含：

| Key | 有无 |
|---|---|
| `NSAppleEventsUsageDescription` | 有 |
| `NSSpeechRecognitionUsageDescription` | 有 |
| **`NSScreenCaptureUsageDescription`** | **有**（项目已配置；当前 ad-hoc 产物 Info 中若未显示，以 pbxproj 源为准——生成键已存在） |

注：对已构建的 ad-hoc 产物 `plutil` 曾只列出 AppleEvents/Speech；`INFOPLIST_KEY_NSScreenCaptureUsageDescription` 在 pbxproj 中已设置。稳定签名重建后应出现在 Info.plist。

---

## 6. 结论与暂停原因

| 检查 | 结果 |
|---|---|
| 可用 Apple Development 证书 | **无（0 identities）** |
| 能否本机 Automatic Signing | **否，直至用户登录 Apple Account 并创建 Development 证书** |
| 是否允许用 ad-hoc 冒充修复 | **否（本阶段明确禁止）** |

**本阶段在签名配置落地前暂停于：等待 Apple Account / Development 身份。**

用户需在 **Xcode → Settings → Accounts** 登录 Apple ID，并确保出现 **Personal Team** 或付费 Team，且 `security find-identity -v -p codesigning` 至少有一条 `Apple Development: …`。

准备就绪后（配置已草拟于同目录 `SIGNING_PLAN.md`），继续：

1. Debug Automatic Signing + 本地 Team（不提交私钥/profile）  
2. `ENABLE_DEBUG_DYLIB = NO`（仅 App Target Debug）  
3. 单次 Debug 构建并冻结  
4. 用户重新授权 TCC  
5. 最小 `STREAM started` 探针  
