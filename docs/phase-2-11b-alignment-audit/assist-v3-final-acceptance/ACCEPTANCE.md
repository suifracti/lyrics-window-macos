# Phase 2.11B — 最终产品验收收口（默认 V3 · 无 harness）

| 项 | 值 |
|---|---|
| 产品 | **Lyric Island** |
| 日期 | 2026-08-04（2026-08-05 更正：撤销“用户已检查入口”误述） |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| **HEAD** | **`abee438ce10c736f083d4b13ab32f5a3b0fdac3a`** |
| 实现 commit | `abee438` — fix(assist): wire listening alignment into immersive V3 |
| 基线（接线前） | `85657ab` |
| App | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| TeamIdentifier | **`5RGL84U3V2`** |
| CDHash | **`9b32bab10a51d3181d9dd509121b7e2774d9d78f`** |
| 签名 | Apple Development · **非 ad-hoc** · 无 debug dylib |
| 本轮 rebuild | **否**（沿用 abee438 构建产物） |
| 验收库 | 隔离临时库 `SPOTIFYLYRICS_DATABASE_PATH`（见 `temp-db.txt`） |
| harness | **未使用**（e2e 中 `ACCEPTANCE control` / `assist_start` 计数 = **0**） |

### Identity

```text
Identifier=com.spotifylyrics.app
CDHash=9b32bab10a51d3181d9dd509121b7e2774d9d78f
TeamIdentifier=5RGL84U3V2
Authority=Apple Development: 3881920884@qq.com (XJDV53A9C8)
designated => identifier "com.spotifylyrics.app" and anchor apple generic
  and certificate leaf[subject.CN] = "Apple Development: 3881920884@qq.com (XJDV53A9C8)" …
codesign: valid on disk · satisfies Designated Requirement
```

证据：`identity.txt` · `app-path.txt`

---

## 0. 结论（先读）

### 最终状态（2026-08-05 收口裁定）

**Phase 2.11B：实现与工程验收完成；真人 UI 验收延期。**

| 层 | 状态 |
|---|---|
| 算法 / 捕获 / Merger / 部分持久化 / 会话隔离（真机 + 合同） | **工程验收完成** |
| 默认 V3 接线（Sheet host / phase UI / dismiss） | **工程验收完成**（`abee438` + 合同） |
| 合同套件 | **全 PASS** |
| **真人 UI 录屏 G1–G7** | **延期**（用户不继续手动验收；**不阻塞**进入 2.11C 规划） |
| 产品默认主路径 | **不再以手动 Assist 为主**；手动 Assist 保留为高级校正 / DIY 回退 |

### 准确表述

> Phase 2.11B：**实现与工程验收完成；真人 UI 验收延期。**  
> 手动「边听边排轴」保留为高级 / DIY 路径，**不再作为默认产品主路径**。  
> 默认主路径规划转入 **Phase 2.11C Zero-Operation Automatic Alignment**（见 `docs/phase-2-11c-zero-operation-alignment/`）。

---

## 1. 合同（本轮重跑，全部 PASS）

```text
assist_v3_entry_contract: PASS
assist_session_contract: PASS
assist_candidate_merge_contract: PASS
assist_editor_contract: PASS
assist_partial_persist_contract: PASS
s3a_partial_alignment_contract: PASS
s3b_anchor_alignment_contract: PASS
```

证据：`contracts.log`

---

## 2. 正式库与隔离库

| 检查 | 结果 |
|---|---|
| 启动方式 | 直接可执行文件 + **仅** `SPOTIFYLYRICS_DATABASE_PATH`（**无** `SPOTIFYLYRICS_ACCEPTANCE_CONTROL_PATH`） |
| 临时库 | `/tmp/spotifylyrics-v3-final-20260804235044.sqlite3` |
| 临时库内容 | 1 个版本：`qqExperimental` · `is_synced=0` · timed=0/32（纯文本加载，**无 Assist 写库**） |
| formal before SHA | `d6d5f121152057908ccd70cf4b83d8c76d86b9f4b9c9929326c45a60eb5f420b` |
| formal after SHA | **相同** |
| formal_db_opened by Assist 验收进程 | **否**（TEMP 路径） |
| harness 令牌 | **0** |

> 注：formal SHA 相对更早窗口的 `a0ea0fc2…` 已变化，归因于验收外的正式库使用；**本轮 TEMP 验收进程未写入 formal**。

---

## 3. 本轮已取证的真实 UI / 会话状态（无 harness）

| 步骤 | 证据 | 状态 |
|---|---|---|
| App 以 Development 签名运行 | `identity.txt` · 进程路径 = 冻结 App | ✅ |
| 播放《夜の合図》 | e2e trackChange + Spotify | ✅ |
| 纯文本 · 未排轴 | 截图可见状态条「纯文本 · 未排轴」；e2e `alignmentQueued source=qqExperimental lines=32` | ✅ |
| 歌词已持久化到 TEMP | TEMP db timed=0/32 qqExperimental | ✅ |
| 未使用 assist_start / control 文件 | e2e 计数 0 | ✅ |
| 当前歌曲面板「边听边排轴」可见 | **真人入口检查未完成**；仅有合同/代码路径，**无**真人/截图证据 | ❌ 属 G1，未完成 |
| Sheet / 取消恢复 / 再进入 | **真人入口检查未完成**；合同覆盖 `dismissListeningAssistExplanation` 源码存在性 | ❌ 属 G1–G2，未完成 |
| 真实捕获 STREAM / PCM | 本轮 **未**从 UI 启动捕获 | ❌ 本轮缺口 |
| Merger → 编辑器草稿 | 本轮 **未**从 UI 完成 | ❌ 本轮缺口 |
| Space / N / undo | 编辑器路径仍在；本轮 **未**交互录制 | ❌ 本轮缺口 |
| 部分时间轴子版本 | 本轮 TEMP **无** manualEdit 子版 | ❌ 本轮缺口 |
| 完整跟播录屏 | 未做 | ❌ 本轮缺口 |

截图：

- `screenshots/01-main-display.png` — 主窗口《夜の合図》+「纯文本 · 未排轴」
- `screenshots/03-after-hover-click.png` — 自动化尝试 hover 工具栏后

e2e 摘录（无 harness）：

```text
SESSION apply alignmentQueued source=qqExperimental lines=32
SESSION persistence save … disposition=inserted
（无 ACCEPTANCE control / 无 assist_start）
```

---

## 4. 代码路径与先前真机证据（不冒充本轮 UI 录屏）

### 4.1 V3 接线（abee438）

| 能力 | 位置 |
|---|---|
| 唯一 Sheet host | `MainLyricsWindowView` → `AssistExplainSheet` |
| 入口 + 全 phase | `CurrentSongOperationsView.listeningAssistControls` |
| dismiss → idle | `PlaybackState.dismissListeningAssistExplanation` |
| 草稿打开编辑器 | `assistEditorOpenToken` + `openListeningAssistEditorWithDraft` |
| S1/S2/S3A | **未改**（`Main.swift` 诊断菜单） |

### 4.2 捕获→合并→部分保存（先前真机，同产品路径逻辑）

`docs/phase-2-11b-alignment-audit/assist-mvp-closure-final/` 在 Development 签名下已证明：

- STREAM started · formal_db_opened=NO  
- ASSIST draft ready · mark / undo / redo / partial save  
- parent timed=0 · child manualEdit timed>0 · is_synced=0  
- 重启恢复 · 取消不写库 · A→B 切歌 · formal SHA  

> 该轮验收 **使用了 harness 直调** `confirmListeningAssistAndCapture`（跳过 Sheet）。  
> **abee438 的目标正是去掉该依赖**；本轮因 §5 未能完成「从 V3 点击」的替代录屏。

### 4.3 部分 vs 完整跟播（产品语义 · 代码审计）

| 类型 | 行为 | 是否伪造同步 |
|---|---|---|
| 部分时间轴 `is_synced=0` | 主界面保持纯文本/未排轴；**不**按播放位置滚动 | **正确 · 不伪造** |
| 完整时间轴 `validation.isSynchronized` | `adoptPersisted` 后 `loaded` + `liveLyricsAreSynchronized` → 主界面跟播 | 预期行为 |
| 保存后当前选择 | `editor.onSaved` → `applyLyricsEditorResult` → **`adoptPersisted`** | 自动采用 |

本轮 **未**补齐「完整标记 → 主界面跟播」录屏，故 **不能**关闭完整跟播验收项。

---

## 5. 代理无法无人值守完成 V3 点击路径的原因

V3 工具栏实现（`AppleMusicImmersiveV3WindowView`）：

```text
toolBar
  .opacity(toolsVisible ? 1 : 0)
  .allowsHitTesting(toolsVisible)
onContinuousHover: y ≤ 96 → revealTools()
```

结果：

1. 「当前歌曲」按钮默认 **不可点、不可见**  
2. 需真实 hover 顶栏才 `toolsVisible=true`  
3. 本环境合成 `CGEvent` 鼠标移动 **未能** 打开面板（`logs/automation-blocker.txt`）  
4. 未打开面板则无法 AX 到「边听边排轴」/ Sheet「开始」  
5. **禁止** 用 `assist_start` 绕过 → 代理卡在入口点击  

这 **不是** 算法回归；是 **验收自动化与 content-first 工具栏** 的摩擦。  
**真人入口是否可走通：尚未完成检查**（不得假设用户已验证）。

---

## 6. 失败 / 安全路径（合同 + 代码 · 本轮未重做真机切歌）

| 路径 | 依据 |
|---|---|
| Sheet dismiss 不残留 explaining | `dismissListeningAssistExplanation` → idle · 合同 |
| 捕获中取消 | `cancelListeningAssist` → stop userStop · 清草稿 |
| 切歌取消 | `invalidateAssistOnTrackChange` · 合同 |
| 取消不写库 | confirm 路径无 `saveAlignedVersion` · 合同 |
| 临时 WAV | 捕获 cleanup 路径（先前真机 wav_remaining=0） |
| 正式库 | 本轮 TEMP · formal SHA 不变 |
| S1/S2/S3A | 菜单不调用 Merger / 编辑器 / 保存 · 合同 |

---

## 7. 剩余缺口清单（关闭 Phase 2.11B 前必须补齐）

| # | 缺口 | 建议证据 |
|---|---|---|
| G1 | **真人入口检查未完成**：V3 顶栏 hover → 当前歌曲 →「边听边排轴」可见 → Sheet 出现（此前误记“用户已检查”，**已撤销，不计入完成**） | 截图 / 短录屏 |
| G2 | Sheet **取消** → 入口恢复 → **再开始**（无 harness）；**真人未完成** | 录屏 + e2e 无 control |
| G3 | 真实 STREAM / PCM / 无 mic / 无 video | `spotifylyrics-sck-spike.log` |
| G4 | draft ready → 编辑器建议/未排 | 截图 |
| G5 | Space / N / ↑↓ / undo | 短录屏 |
| G6 | 部分子版本 parent / is_synced=0 / 无伪时间 / adopt | TEMP sqlite 查询 |
| G7 | 完整时间轴 → 主界面跟播 + 暂停/恢复/seek + 切歌不串 | **录屏（强制）** |
| G8 | 捕获中取消 / A→B / A→B→A 无 harness 复验（可选加固） | 日志 |

补齐 G1–G7 后，方可写：

> **Phase 2.11B ✅ 核心链路、默认 V3 产品入口与完整跟播均真实验收完成。**

---

## 8. 本轮不做

- 未 rebuild  
- 未改 ASR / DP / 锚点 / schema  
- 未用 harness 冒充 UI  
- 未进入 S3C / 2.7 / 3  
- 未实施 2.11C  

---

## 9. 产物索引

| 文件 | 内容 |
|---|---|
| `identity.txt` | HEAD / CDHash / Team |
| `contracts.log` | 合同全 PASS |
| `temp-db.txt` | 隔离库路径 |
| `formal-db-before.sha` / `after.sha` | 正式库未变 |
| `logs/03-lyrics-ready.txt` | 纯文本加载 |
| `logs/automation-blocker.txt` | 自动化阻塞说明 |
| `screenshots/01-main-display.png` | 纯文本 · 未排轴 |
| 先前 | `../assist-mvp-closure-final/` 算法真机证据 |
| 接线 | `../assist-mvp-manual-entry-audit/V3_WIRING_FIX.md` |

---

**暂停。** 等待用户补齐 G1–G7 录屏/截图后，再更新本文件为正式关闭状态。
