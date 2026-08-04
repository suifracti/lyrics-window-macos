# Phase 2.11B-Assist MVP — Acceptance Closure

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-04 |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| 功能基线链 | `393adcd` → `5da57b6` → `4e06519` → `8023f65` → docs |
| **结论** | **代码闭环完成，真实验收仍未完成** |

---

## 1. 仓库 / HEAD 核对（真实）

```text
branch: codex/phase-2-11b-assist-mvp
HEAD (closure start): 433af25
merge-base(393adcd, HEAD): 393adcd
```

### 1.1 与报告中哈希的关系

| 哈希 | 身份 | 是否当前 HEAD |
|---|---|---|
| **`433af25`** | `docs(assist): Phase 2.11B Assist MVP acceptance evidence` — **当时真实 HEAD** | 收口开始时为 YES |
| `19f4bc5` | 文档 amend 链中的 **中间产物**（多次 `commit --amend` 被取代） | **NO**（已不在分支尖端） |
| `5da57b6` | **功能** commit 1：draft + merge + partial times | 是 HEAD 祖先 |
| `4e06519` | **功能** commit 2：编辑器建议/标记/跳转 | 是 HEAD 祖先 |
| `8023f65` | **功能** commit 3：入口/捕获/切歌 | 是 HEAD 祖先 |

**当前 HEAD 完整包含三个功能 commits：是**（`merge-base --is-ancestor` 全部 YES）。

`ACCEPTANCE.md` 中的 `19f4bc5` 为 **过时文档笔误**；以 `git rev-parse HEAD` 为准。

### 1.2 收口过程中的额外代码提交

为真实验收自动化（SwiftUI 无可靠 AX 标签、无法点击「边听边排轴」），在 **DEBUG 验收控制文件** 中增加了 harness 令牌（非产品 UI）：

- `assist_start` / `assist_seconds=` / `assist_cancel` / `assist_save` / `assist_mark=`
- `assist_make_plain` / `assist_undo` / `assist_redo`

这是既有 `SPOTIFYLYRICS_ACCEPTANCE_CONTROL_PATH`（mode/retry）的扩展，**不改变产品界面**。  
见单独 commit：`fix(debug): Assist acceptance control harness`。

---

## 2. TCC / 签名

| 项 | 值 |
|---|---|
| App path | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| Bundle ID | `com.spotifylyrics.app` |
| 签名 | ad-hoc（Sign to Run Locally） |
| 最终 CDHash（harness 构建后） | `b545ddd10672d47fcbe4e38e78c09f8a4a8ccde9` |

### 2.1 TCC 实测

| 时间点 | 结果 |
|---|---|
| 用户首次授权后（CDHash `df9c7dac…`） | **STREAM started**，短捕获成功，正式库 SHA 不变 |
| harness rebuild 后（CDHash 变更） | **SPIKE failed: 用户拒绝了…TCC** |
| 用户称「已重新开启」后 | **仍失败**；`tcc-dump.txt` 显示 **无** `kTCCServiceAudioCapture` / `kTCCServiceScreenCapture` 针对 `com.spotifylyrics.app` |

**结论：当前系统并未对 SpotifyLyrics 授予屏幕/系统音频捕获权限（TCC.db 无对应 auth_value=2 记录）。**  
不得将「用户口头确认」视为通过；必须以捕获成功日志 + TCC 证据为准。

### 2.2 ad-hoc 与 TCC 不稳定

每次 `xcodebuild` 改变 CDHash → 权限可能失效。  
稳定验收要求：

1. 固定 DerivedData 路径  
2. 授权后 **禁止 rebuild**  
3. 在「屏幕与系统音频录制」中用 **+** 添加：  
   `…/DerivedData/Build/Products/Debug/SpotifyLyrics.app`  
4. 开关打开后立刻跑捕获探针，确认 `STREAM started`

---

## 3. 隔离环境与正式库

| 项 | 结果 |
|---|---|
| 临时库示例 | `/tmp/spotifylyrics-assist-closure-A-*.sqlite3` |
| 正式库路径 | `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3` |
| formal before（探针成功段） | `61f9e97c…` |
| formal after（同段） | **相同** `61f9e97c…` |
| spike `formal_db_opened` | **NO** |

探针成功窗口内正式库 **未变化**。  
Assist 启动后因 TCC 失败未完成写库路径验证的其余场景。

---

## 4. 真实样本 A/B / 场景 C–E

| 场景 | 状态 | 证据 |
|---|---|---|
| A 夜の合図 E2E | **未完成** | 纯文本加载成功（QQ 32 行）；`assist_start` 已触发；捕获 **TCC 拒绝** |
| B アイドル E2E | **未执行** | 依赖捕获 |
| 保存→重启→恢复 | **未执行** | 依赖草稿与保存 |
| 取消不写库 | **未完整执行** | 代码路径存在；无成功捕获后的取消证据 |
| 切歌防串歌 | **未完整执行** | 代码路径 + 合同；无实时日志 |

**禁止用旧 S3B 离线报告代替本轮端到端。** 本收口 **未** 把旧 `partial-*.json` 计为通过。

---

## 5. 合同与构建

```text
assist_candidate_merge_contract: PASS
assist_editor_contract: PASS
assist_session_contract: PASS
s3a_partial_alignment_contract: PASS
s3b_anchor_alignment_contract: PASS
Debug xcodebuild: BUILD SUCCEEDED（harness 后）
```

---

## 6. 最终状态定义（强制）

> **代码闭环完成，真实验收仍未完成。**

未同时满足：

- [x] HEAD 与三功能 commit 关系明确  
- [x] 合同与 Debug 构建通过  
- [ ] TCC 真实捕获稳定成功（当前失败）  
- [ ] 样本 A/B 真实端到端  
- [ ] 保存→重启→恢复  
- [ ] 取消不写库（完整）  
- [ ] 切歌防串歌（完整）  

**不得写：Phase 2.11B-Assist MVP ✅ 完成并真实验收。**

---

## 7. 恢复真实验收的最小步骤（人工）

1. 打开系统设置 → 隐私与安全性 → **屏幕与系统音频录制**  
2. **+** 添加  
   `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`  
3. 打开开关（确认列表项存在）  
4. **不要 rebuild**  
5. 探针：`SPOTIFYLYRICS_SCK_S3A=1` 启动，确认日志含 `STREAM started`  
6. 再跑 A/B/取消/切歌/重启恢复  

---

## 8. 暂停

不进入 S3C / S4 / S5 / Phase 3。  
本收口到此结束。
