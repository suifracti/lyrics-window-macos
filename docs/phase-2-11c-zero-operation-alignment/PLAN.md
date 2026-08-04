# Phase 2.11C — Zero-Operation Automatic Alignment Mode（只读规划）

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 状态 | **只读规划 · 不实施** |
| 前置 | Phase 2.11B Assist MVP（半自动边听边排轴） |
| 日期 | 2026-08-04 |
| 禁止本轮 | whisper.cpp · Demucs · Spleeter · S3C 实施 · schema 迁移 · Phase 3 视觉 |

---

## 0. 产品目标（一句话）

用户**只开一次全局开关**后，对后续每一首「纯文本且无可靠时间轴」的歌曲，系统在后台自动：捕获 → 识别 → 对齐 → 质量门控 → **达标则自动保存并采用新版本**；失败则保持纯文本，不伪造、不强制打断。编辑器/工作台退化为**主动校正与 DIY**，不再是默认必经路径。

---

## 1. 与 2.11B 的关系

| | 2.11B Assist MVP | 2.11C Zero-Op |
|---|---|---|
| 触发 | 用户每次点「边听边排轴」 | 全局开关 + 自动触发条件 |
| 草稿 | 编辑器建议 / 未排 · 用户标记 | 默认**不进编辑器** |
| 保存 | 用户确认 partial/full | 门控通过后**自动** save + adopt |
| 失败 | 用户可见状态 / 重试 | 静默保持纯文本 · 可通知可选 |
| 引擎 | Apple Speech + 现有 DP/锚点 | 引擎抽象（Speech 默认 · 可选本地 ASR） |
| 人声分离 | 不做 | **可选重型回退**（条件触发，非默认） |

2.11B 的会话 guard、切歌丢弃、TEMP 清理、部分时间轴语义、正式库隔离原则 **全部继承**。

---

## 2. 自动触发条件

### 2.1 全局开关

- 设置项建议名：**「自动排轴」**（默认 **关**）  
- 首次开启：简短隐私说明（仅分析当前 Spotify 音频、不录音上传、可随时关）  
- 关闭后：立即 cancel 进行中任务，不写半成品

### 2.2 单曲触发（全部满足）

1. 全局开关 = 开  
2. `hasLiveTrack` 且非 mock  
3. 当前歌词状态为 **纯文本 / 未排轴**（`!isSynchronized` 或等价 `alignmentQueued`）  
4. 存在已保存 `activeLyricsVersionID`（有可绑定的父纯文本）  
5. 该 identity **无** 用户锁定的同步版本优先占用  
6. 本曲本会话尚未标记「用户明确拒绝自动排轴」  
7. 电源 / 热 / 磁盘策略允许（见 §10）  
8. ScreenCapture 权限可用；否则进入权限失败态（见 §12）

### 2.3 不触发

- 已是完整同步歌词  
- 用户「本次播放不使用歌词」  
- 正在手动 Assist / 本地音频排轴 / 编辑器脏保存  
- 后台已有同 identity 任务 running  
- 负缓存：短时内连续失败（退避）

---

## 3. 后台任务生命周期

```text
idle
  → eligible (条件满足)
  → arming (绑定 guard: identity + version + hash + revision + jobId)
  → capturing (SCK · segment · 可分段)
  → aligning (Speech/ASR → DP/锚点 → merge)
  → gating (质量门控)
  → auto_saving (仅 gate 通过)
  → adopted (当前版本切换)
  → idle
失败/取消分支 → cancelled | failed_soft → idle（不写库或仅写诊断）
```

原则：

- **单一 job / identity**；新触发取消旧 job  
- 与 2.11B 相同：`AlignmentSessionGuard` + track change invalidate  
- **不**占用主线程 UI；状态可在「当前歌曲」只读摘要一行（非强制 modal）

---

## 4. 首次播放只能逐段积累

语义：

- 用户从曲中途进入时，**只对齐已捕获窗口**，不假装全曲完成  
- 自动结果默认是 **部分时间轴**（`is_synced=0`）直到门控认为「足够完整」  
- 首次会话产出：`partial_candidate`（内存 + 可选磁盘缓存，见 §7）  
- **禁止**对未听段落插值铺满时间轴

进度模型（规划）：

- `coverage = timed_nonblank / nonblank`  
- `listen_ratio = captured_unique_playback_span / track_duration`  
- 自动 **adopt 完整同步** 需同时过 coverage 与质量门；否则只缓存 partial

---

## 5. 切歌 / 暂停 / seek / 续排

| 事件 | 行为 |
|---|---|
| 切歌 A→B | 取消 A job；丢弃未确认结果；B 重新评估 eligible |
| A→B→A | **新 job**；可加载 A 的 partial 缓存续排，**不**合并 B 的证据 |
| 暂停 | 结束当前 segment；不强制 stop 整个 job（可等 resume） |
| seek | 新 segment（与 S2 连续策略一致）；标记 discontinuous |
| 续排 | 同 identity + 同 parent version hash：合并新 segment 证据到已有 partial；version hash 变则废弃缓存 |

---

## 6. 自动质量门控（规划阈值 · 可调）

通过才允许 **自动保存并采用**：

1. **身份**：guard 全程有效  
2. **覆盖率**：`coverage ≥ T_cov`（建议初值 0.85，可配置）  
3. **单调性**：时间轴校验无 error  
4. **锚点/高置信占比**：`high_conf_ratio ≥ T_hc`（防整曲胡填）  
5. **听过比例**（完整采用时）：`listen_ratio ≥ T_listen` 或 用户完整播完  
6. **冲突**：与已有锁定同步版冲突 → **不覆盖**，仅提议（或进 DIY）  

未过门控：

- 保持纯文本当前版  
- 可选：写入 **非当前** 诊断草稿（默认 **不** 打扰）  
- 或仅缓存 partial 供下次续排

---

## 7. 部分结果缓存与下次续排

| 层 | 内容 | 生命周期 |
|---|---|---|
| 内存 | job partial draft | 进程内 · 切 identity 丢弃（可序列化） |
| 磁盘缓存（规划） | identity + parentHash + segment digests + candidate times | 有上限 LRU；开关关闭可清 |
| 正式库 | 仅 gate 通过后的 `manualEdit`/`automaticAlignment` 子版本 | 用户可见版本树 |

续排合并：同 parentHash 下按行索引合并更高置信 / 锚点优先（复用 2.11B merger 精神，**不**降低阈值偷懒铺满）。

---

## 8. 自动保存与采用规则

| 结果类型 | 保存 | 采用为当前 |
|---|---|---|
| 未过门控 partial | 默认否 | 否 |
| 过门控 partial | 是 · `is_synced=0` · parent 链接 | **是**（主界面仍不伪造整曲同步滚动） |
| 过门控 full | 是 · `is_synced=1` | **是** · 主界面跟播 |
| 用户锁定版存在 | 不自动覆盖 | 否；可生成旁路候选 |

保存路径：复用 `saveManualEdit` / 既有 persistence，**禁止** silent formal 旁路。  
默认仍建议验收与开发用 TEMP；生产写正式库仅在用户机器正常产品路径。

---

## 9. 引擎抽象（规划）

```text
protocol AlignmentEngine {
  id, costClass, offlineCapability
  align(segments, plainLyrics, locale) -> PartialCandidate
}
```

| 引擎 | 角色 | 2.11C 默认 |
|---|---|---|
| Apple Speech + 现有 DP/锚点 | 轻量默认 | **是** |
| 本地 ASR（如 whisper.cpp） | 可选增强 | **规划 · 不实施** |
| 人声分离前处理（Demucs 等） | 可选重型回退 | **规划 · 不实施** |

切换策略（规划）：

1. 默认 Speech  
2. 连续 N 次 coverage 过低 → 提示「可下载增强模型」（用户同意）  
3. 增强仍差且用户开启「允许重型处理」→ Demucs 回退队列（耗电/磁盘门控）

---

## 10. 模型下载 / 性能 / 能耗 / 磁盘

| 策略 | 说明 |
|---|---|
| 下载 | 仅用户同意；校验 checksum；断点续传；可取消 |
| 存储 | 模型目录可配置；上限；不足时拒绝下载 |
| 性能 | 同机最多 1 个重型 job；前台播放优先 |
| 能耗 | 低压/节能模式暂停重型；仅保留轻量 Speech |
| 热度 | 可选：过热暂停自动排轴 |
| 磁盘 | 捕获 WAV 仍 **用后即删**；报告可选保留 |

---

## 11. 设置信息架构

### 11.1 普通设置

- 自动排轴：开/关  
- 自动采用完整同步：开/关（关则只缓存/只保存 partial）  
- 失败通知：关 / 仅徽章 / 横幅  
- 隐私摘要入口  

### 11.2 高级 DIY（工作台）

- 引擎选择与模型管理  
- 门控阈值 T_cov / T_hc / T_listen  
- 允许重型回退  
- 缓存清理  
- 手动「对此曲再跑一次」  
- 打开编辑器校正（2.11B 路径）  

原则：**普通用户只见一个开关；高级不默认展开。**

---

## 12. 隐私 / 权限 / 失败态

| 态 | UI | 行为 |
|---|---|---|
| 权限缺失 | 设置引导一次 | 不循环弹窗 |
| TCC 拒绝 | 软失败 | 保持纯文本 |
| 捕获失败 | 可重试徽章 | 不写库 |
| 识别失败 | 静默/徽章 | 不伪造 |
| 门控失败 | 默认可静默 | 保留缓存可选 |
| 用户关闭开关 | 立即停 | 清进行中 job |

音频策略继承 2.11B：

- 仅 Spotify 应用音频  
- 无麦克风  
- 不上传  
- 不导出用户未请求的音频文件  

---

## 13. 里程碑建议（不实施）

| 阶段 | 内容 | 成功标准 |
|---|---|---|
| C0 | 开关 + 自动触发 + 复用 2.11B 捕获/merge + **不**自动保存 | 日志证明 auto start/cancel |
| C1 | 门控 + 自动 partial 保存/采用 | 隔离库真机 2 曲 |
| C2 | 完整采用 + 跟播 | 录屏 |
| C3 | 缓存续排 | A 听半首 → 再听后半 → 合并 |
| C4 | 引擎抽象 + 可选本地下载 ASR | 默认仍 Speech |
| C5 | 可选 Demucs 回退 | 默认关 · 文档化成本 |

每阶段保持：正式库 SHA 纪律、无 schema 强迁、可关即停。

---

## 14. 明确不做（本规划边界）

- 不默认开启自动排轴  
- 不用低置信插值伪装 100% 同步  
- 不在未授权时下载模型  
- 不把 DIY 工作台当默认必经  
- 不在本规划文档中实施任何引擎或 UI  

---

## 15. 开放问题（需产品决策）

1. 自动 partial 采用后，主界面是否显示「部分排轴」徽章？  
2. 失败是否允许偶尔一次非阻塞通知？  
3. 自动版本的 `source` 枚举：复用 `automaticAlignment` 还是新 source？  
4. 与 LRCLIB 等在线同步源的优先级（自动排轴是否永远让位在线同步）？  

---

**本文档为只读规划。不实施 Phase 2.11C。不进入 S3C / Phase 2.7 / Phase 3。**
