# Craft 与仓库对账发现

## 用户目标

- 访问用户指定的 Craft 空间/页面。
- 根据仓库实际进度修改规划，而不是继续沿用可能过时的口头状态。
- 收束当前混乱，给出可以按顺序执行的计划。

## 已知上下文（待仓库与 Craft 复核）

- 用户已明确：近期只改 V3，不改 V4。
- 近期 V3 工作集中在歌词切换流畅度、日文汉字假名、封面/背景、进度条、工具栏、设置材质、卡死和单实例运行。
- Direction D/V4 有独立规划文件，但不能仅凭规划文件把未执行项目算作完成。
- 仓库存在多个历史规划入口，且工作区有大量未提交改动；这是当前「做乱了」的主要风险之一。

## 证据原则

1. 通过测试 + 当前源码 + 可复现运行状态支持的项目，记为「已验证」。
2. 只有源码、没有真实联调或验收证据的项目，记为「已实现待验收」。
3. 仅存在于计划/想法中的项目，记为「待做」或「想法池」。
4. Direction D/V4 与 V3 分线统计，禁止互相借完成度。

## Craft 初读（2026-08-06）

- Craft 空间：`个人系统`；父文档为 `spotify lyrics app`，目标子页面为 `Lyric Island｜总规划与想法（唯一页面）`（root block `E994D4BE-C78A-49BC-BCD4-6D7B8A4A25BD`）。
- 页面声明自己是唯一规划事实来源，但内部同时保留了多轮阶段结论，缺少一个置顶的、按当前仓库重算的状态层。
- 页面较早的“当前真实进度”仍写：Phase 2.11B 核心链路与接线完成，但真人 G1–G7 验收未关闭。
- 页面后部又写：Phase 2.11C-MVP1 已完全验收并冻结，下一主线进入 Phase 3。
- 页面后部连续记录 Phase 3.2 CLOSED、Phase 3.3 从 CONDITIONAL PASS 到 A. PASS、Phase 3.4 CONDITIONAL PASS / 待工程审计。
- 当前页面因此混合了：稳定产品基线、历史检查点、当时的阶段判断、未来想法和执行指令。它们都可以保留，但必须用新的置顶摘要标明哪些仍是当前事实。
- 页面明确要求本地 planning-with-files 只能作为当次执行镜像，完成后需回写 Craft；本次 scoped plan 符合该用途。

## 仓库快照（2026-08-06）

- 当前分支：`antigravity/phase-3-4-direction-d-main-window`；当前 HEAD：`522236f00a7a`。
- 最近提交仍属于 Direction D Phase 3.4 视觉修复/评审线；最新三项为右侧封面布局说明、视觉评审候选、Direction D visual host/small sheet 稳定化。
- 工作区严重未收口：58 个 tracked 文件有差异（约 1859 insertions / 1126 deletions），另有大量 untracked 计划、测试、截图和审计材料；变更同时覆盖 V3、Direction D、共享组件、设置、测试与历史验收日志。
- 当前分支名和最近提交属于 Direction D，但用户最近明确要求“只改 V3，不改 V4”。继续在这一分支叠加 V3 修复会让产品主线、实验线与证据线失去边界。
- 根目录 `task_plan.md` / `progress.md` 仍停在 Phase 3.1/3.2 完成语境；`.planning/phase-3-4-*` 又保留了不同的未完成/修复计划。它们都不能单独代表当前总进度。
- V3 当前源码确实包含近期修复：协调式歌词滚动动画、日语读音缓存与自动补全、kanji-only ruby token、歌手/专辑同排、材质工具栏、亮色封面自适应暗幕等。
- 当前运行中仅发现一个 SpotifyLyrics 实例：PID `72187`，来自 `/private/tmp/spotifylyrics-v3-kana-final-build/.../SpotifyLyrics.app`，即近期 V3 假名修复构建。
- 仓库根目录只保留一个 DerivedData：`DerivedDataLyricsReadability20260806`；历史 DerivedData 已归档到 `artifacts/derived-data/archive/`。

## 当前最大的组织性风险

1. **分支错位**：Direction D 分支承载 V3 临时修复。
2. **状态错位**：Craft、根计划、scoped plans 和实际工作区分别讲不同版本的“当前主线”。
3. **证据未固化**：近期 V3 合同测试脚本仍为 untracked，实际可用修复尚未形成可回退的 clean baseline。
4. **历史日志被改动**：旧验收产物也在 dirty diff 中，若直接提交会把代码修复与历史证据重写混在一起。

## Direction D / V4 实际状态对账

- Phase 3.2 设计系统和 Phase 3.3 产品状态有关闭文档与合同证据；V3 始终保持 default，Direction D 始终是 experimental。
- Phase 3.4 的工程接入已经比旧 scoped plan 写得更远：存在真实 `DirectionDMainWindowView`、Wide/Small/Lyrics Focus 证据、29/29 合同、签名构建与窗口级截图，不能再简单写成“尚未开始”。
- Phase 3.4 correctness closeout 通过了身份 fail-closed、暂停状态和受控状态证据；但完整外部快速 A→B/B-loading/B-noLyrics 切换仍是 **UNVERIFIED**。
- Phase 3.4 视觉修复已有 `READY FOR USER REVIEW` 候选与独立截图，但文档明确写“not user-accepted yet”。因此准确状态是：**工程与受控正确性基本完成；视觉候选待用户验收；外部快速切歌仍待补证；不得算产品默认/发布完成。**
- `.planning/phase-3-4-direction-d-main-window` 仍显示 Stage 0–5 全未勾选，`.planning/phase-3-4-visual-conformance-repair` 仍停在 Phase 2；它们已被后续提交超越，是过时执行镜像，不应继续作为当前事实源。
- 鉴于用户当前明确“只改 V3，不改 V4”，Direction D/V4 应标为 **暂停/封存候选**：保留已有成果和缺口，停止继续修图、切默认或启动 Phase 3.5，直到 V3 发布候选收口后再做是否恢复的决策。

## V3 合同复核

- `Tests/ruby_layout_contract.sh`：PASS；包含本轮新增的截图句子样例，确认只给汉字标 ruby、送假名不整句铺底。
- `Tests/japanese_reading_contract.sh`：PASS；形态素读音链可运行。
- `Tests/v3_lyric_readability_contract.sh`：PASS。
- `Tests/v3_lyric_transition_contract.sh`：PASS。
- `Tests/v3_visual_polish_contract.sh`：PASS。
- `Tests/v3_cover_layout_contract.sh`：PASS。
- `Tests/v3_backdrop_contract.sh`：PASS。
- `Tests/lyrics_transition_contract.sh`：PASS。
- 以上证明当前源码的结构合同与日语读音样例没有回退，但它们不能替代长时间真实播放、快速切歌、亮/暗封面和 CPU/卡死的发布级 soak。
- 最初裸跑 `swift Tests/ruby_token_contract.swift` 失败是调用方式错误；正式入口 `ruby_layout_contract.sh` 会把 `JapaneseReadingPipeline.swift` 与测试一起编译，已通过。

## 当前整树构建

- 使用唯一根 DerivedData `DerivedDataLyricsReadability20260806` 对当前 dirty worktree 执行 Debug build：`** BUILD SUCCEEDED **`。
- 构建覆盖了 V3、Direction D、共享窗口/设置等当前源码，因此至少证明混合工作树当前可编译。
- 构建仍有一项既存 Swift 6 迁移警告：`WhisperCLISpeechEngine` 的 `FileManager` stored property 不满足 Sendable；当前 Swift 5 模式只是 warning，但应在发布前登记为技术债。
- AppIntents metadata 因未依赖 AppIntents.framework 被跳过；这不是当前歌词主线失败。
- 本次未做签名/发布构建，也未启动第二个 App 实例。

## Direction D 合同复核

- 当前最新合同通过：Phase 3.4 main window 29/29、correctness 22/22、layout recovery PASS、live playback 14/14、visual 35/35；Phase 3.2 汇总合同也通过。
- 唯一失败是较旧的 `direction_d_phase_3_3_contracts.sh` 中 `no_d_default_layout`：它禁止 Direction D 成为任何 `MainWindowLayoutStyle`，而 Phase 3.4 已正式给 V4 新增独立 layout 值。较新的合同同时验证 V3 仍是默认、V4 可独立选择，因此这是**旧合同语义过期**，不是 V4 抢占默认。
- 这再次证明不能用“所有历史文件同时有效”的方式管理项目：后阶段合法决策必须显式 supersede 旧合同/旧计划。
- Direction D 的静态/模型合同很完整，但用户视觉验收仍是独立门槛；合同通过不等于当前应继续开发 V4。

## 功能主线与遗留项复核

- Craft 记录的关键提交均存在于当前仓库：Phase 2.6 读音/文字、2.11A 免费歌词来源、2.11B V3 Assist 接线、2.11C S3/S4/S4.5/MVP1、Phase 3.2/3.3 closeout 等不是空计划。
- 正式数据库仍保持 `user_version=4`；源码中 v5/v6 是 additive/local validation schema，最新 Phase 3.4 证据也明确正式库为 v4。因此“正式数据库迁移、备份与回滚验收”仍未完成，不能从 Craft 的待联调项里删掉。
- 未找到 Phase 2.7（听歌历史/统计）或 Phase 2.8（个人曲库/私人同步）已开始的仓库证据；它们应保留为后续产品阶段，不再夹在 V3 当前 UI 修复中。
- V3 对长歌词的当前修复是：限制可读宽度、按字符数调整字号、允许最多两行换行；未发现把 Provider 的超长语义行自动重分句的实现。因此早先“歌词过长”既可能来自歌词源分行，也有渲染责任：**视觉溢出已处理，源级/语义分句尚未解决，应列入歌词质量而非继续调字号。**
- 近期“封面下三行元数据”“假名太小/错位/整句假名”“背景多第二张封面”“纯白背景可读性”“切行卡顿/卡死”“进度条/工具栏/设置材质”都已有当前 V3 源码与合同对应；尚缺的是把这些未提交修改固化成独立 V3 baseline，并做发布级真人验收。

## 运行状态快照

- 当前只有一个 App 进程，已持续运行约 22 分钟，进程状态为 sleeping，5 次采样 CPU 约 16.0%–17.8%、内存约 0.5%。
- 这说明当前没有复现 99% CPU 的完全卡死，也没有多实例问题；但安静播放时仍有持续 CPU 活动，不能据此宣布性能问题关闭。
- V3 发布候选必须增加 30–60 分钟真实播放 soak，并对稳定态 CPU、快速切歌、窗口缩放/布局切换、歌词层变化做 Instruments 或 `sample` 证据。

## Craft 收口方案

### 方案 A（推荐）：原页置顶“当前执行看板”

- 在唯一规划页开头新增 `00. 当前执行看板（2026-08-06 仓库对账）`。
- 看板只保留当前决策、状态分栏、风险、下一阶段与恢复 V4 的门槛。
- 原有长篇愿景、想法池和历史检查点全部保留；明确“下方旧状态均为历史记录，若冲突以置顶看板为准”。
- 优点：改动最小、证据不丢、仍符合“一页事实源”；缺点：页面仍然很长，但入口清楚。

### 方案 B：重写主页面，历史内容迁入折叠/归档页

- 当前页只留产品定义、真实进度、路线图和决策；把旧检查点迁走。
- 优点：最干净；缺点：搬迁风险高，容易遗漏原始想法，也弱化“一页事实源”。

### 方案 C：新建独立“执行看板”文档

- 原页保留产品总规划，新页只维护当前 sprint。
- 优点：日常执行轻；缺点：重新出现两个事实源，正是当前混乱的根因，不推荐。

## 推荐路线图草案

1. **R0 — 先收仓库，不再叠功能**：冻结当前进程与构建证据；把 V3、Direction D/V4、历史日志、截图/测试按归属做清单；不删除用户改动。
2. **R1 — 固化 V3 Release Candidate baseline**：从当前混合工作树中只提取 V3 与必要共享修复，保留/归档 V4；把 untracked V3 contracts 纳入版本控制；形成可回退提交。
3. **R2 — V3 真人验收与性能收口**：覆盖亮/暗/白封面、短/长歌词、无/有 Provider 假名、快速切歌、单行↔两行、窗口尺寸与 30–60 分钟 soak；性能未过门槛就只修卡顿，不继续外观微调。
4. **R3 — 可靠性与数据收口**：处理 Provider 语义分句、真实 API/Apple Translation 联调、正式数据库 v4→最终 schema 的备份/迁移/回滚；这是发布前工程门槛。
5. **R4 — 首发范围冻结**：从剩余大清单中只选首发必需；Phase 2.7 历史统计、2.8 个人曲库/私人同步默认后移，除非用户重新提升优先级。
6. **R5 — V4 决策门**：V3 RC 稳定后再看 Direction D 视觉候选；用户验收通过才恢复，补外部快速切歌证据后再谈 Phase 3.5；否则继续 experimental/归档。

### 近期只做三件事

1. 建立当前 dirty worktree 的归属清单与安全 baseline。
2. 固化并验收 V3 RC（包含性能 soak）。
3. 再做正式数据库/API 可靠性，不碰 Phase 3.5、2.7、2.8。
