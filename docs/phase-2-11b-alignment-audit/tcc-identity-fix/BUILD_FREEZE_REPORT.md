# Phase 2.11B-TCC Identity Fix — Build Freeze Report

| 项 | 值 |
|---|---|
| 日期 | 2026-08-04 |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| 状态 | **稳定签名构建已完成；等待用户重新授权 TCC 后做最小探针** |

---

## 构建产物（冻结）

**绝对路径：**

```text
/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app
```

| 检查 | 结果 |
|---|---|
| 非 adhoc | **PASS**（`Signature size=4778`，有 Authority 链） |
| Authority | `Apple Development: 3881920884@qq.com (XJDV53A9C8)` → WWDR → Apple Root CA |
| TeamIdentifier | **`5RGL84U3V2`** |
| CDHash | `8c1a17a96ddf624616869ab89ec3374e41d6cdda` |
| Bundle ID | `com.spotifylyrics.app` |
| `SpotifyLyrics.debug.dylib` | **不存在**（`ENABLE_DEBUG_DYLIB=NO`） |
| 主 executable | 单文件 ~24.9 MB |
| codesign verify | valid on disk · satisfies Designated Requirement |

**Designated requirement：**

```text
identifier "com.spotifylyrics.app" and anchor apple generic
and certificate leaf[subject.CN] = "Apple Development: 3881920884@qq.com (XJDV53A9C8)"
and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */
```

---

## 配置要点

| 设置 | Debug |
|---|---|
| `CODE_SIGN_STYLE` | Automatic |
| `CODE_SIGN_IDENTITY` | 空 / 由 Automatic 解析为 Apple Development |
| `DEVELOPMENT_TEAM` | `5RGL84U3V2`（来自证书 OU，写在 **gitignored** `DebugSigning.local.xcconfig`） |
| `ENABLE_DEBUG_DYLIB` | **NO** |
| Release | **未改**（仍 ad-hoc） |

### 构建中遇到并已处理的本机问题

1. **Team ID 误用了 CN 括号内 ID**（`XJDV53A9C8`）→ 正确为证书 **OU=`5RGL84U3V2`**  
2. **证书被设为「始终信任」** → Xcode 报 `Invalid trust settings`；已用 `security remove-trusted-cert` 恢复系统默认信任  

---

## 用户授权步骤（请严格按序）

> 本构建 **已冻结**。在授权与探针完成前 **请勿再次 xcodebuild**。

1. **完全退出** SpotifyLyrics / Lyric Island（活动监视器确认无进程）  
2. **系统设置 → 隐私与安全性 → 屏幕与系统音频录制**  
3. **删除** 列表中所有旧的 `SpotifyLyrics` / 旧路径条目（若有）  
4. 启动新签名 App：

```bash
open /Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app
```

5. 若系统弹出授权，点 **允许**  
6. 若无弹窗：在设置中用 **+** 添加上述路径的 App，打开开关  
7. **完全退出** App  
8. **再启动一次**  
9. 回复：**「已重新授权」**

---

## 授权后由代理执行（本阶段）

最小探针：

- `SCShareableContent` + 仅 Spotify 音频  
- 必须出现 **`DISCOVER`** 与 **`STREAM started`**  
- 捕获 10–15 秒 PCM 后停止并清理  

**成功后再另开 Acceptance Closure，本阶段不自动跑样本 A/B。**

---

## SwiftUI Preview

`ENABLE_DEBUG_DYLIB=NO` 仅作用于本 App Target Debug：主程序为单一可执行文件。Preview 可能变慢或行为不同；**不影响**本机运行正式 Debug App。
