# Task Plan: SpotifyLyrics Local Spotify Desktop Provider

## Goal
在已提交的主窗口基础上，实现下载后即可使用的本机 Spotify Desktop 播放链路：通过真实 Apple Events 读取 Spotify 当前歌曲、封面 URL、播放状态和进度，并提供播放控制；UI 只依赖 `PlaybackProvider` 协议；Spotify 不可用时明确显示并回退 Mock 预览。本阶段不实现 Web API、OAuth、SQLite、歌词 Provider 或在线歌词源。

## Next Step
完成 Phase 20 的两种主窗口布局、真实运行截图和签名 Debug 验收后，提交独立 UI commit；随后完成 Phase 21 的独立歌曲搜索链路；不进入悬浮/胶囊/全屏视觉重做。

## Current Phase
Phase 20 — Reference Audit and Switchable Main Layouts (in progress)

## Scope & Boundaries
- 唯一正式项目：`/Users/apple/backup/sptifylyrics`
- 黑盒 UI 参考：`/Applications/Dynamic Lyrics.app`（只读）
- 文档/截图参考：`Lyricify-App-main` 或未来的 `References/Lyricify-App`（只读）
- 歌词格式参考：未来的 `References/Lyricify-Lyrics-Helper`（只读；不复制或链接代码）
- 本轮允许写入：PlaybackProvider/LyricsProvider 状态链路、Track identity、只读本地歌词、LRCLIB、Track-bound 背景、主窗口状态提示、测试契约、规划记录和真实 Spotify 运行截图
- 本轮禁止：Spotify Web API、OAuth、SQLite、AI、自动排轴、其他歌词源、主窗口布局重做、悬浮/胶囊/全屏视觉重做；不修改 Dynamic Lyrics、Lyricify-App-main 或参考应用资源

## Phases

### Phase 1: Audit Commit and Branch — completed
- [x] 提交审计文档、规划记录和观察截图：`05ad34564d069ad8d95dfce8d75c0eb162ada920`
- [x] 创建并切换 `ui-redesign-phase-1`
- [x] 保持 `DerivedData/`、`build/`、`Lyricify-App-main/` 不进入提交

### Phase 2: Red Contract — completed
- [x] 创建 `Tests/phase1_ui_contract.sh`
- [x] 在生产代码前运行并确认因目标组件文件不存在而失败

### Phase 3: Main Window Components — completed
- [x] 新增设计 token、主窗口、歌词画布、歌词行、歌曲头部和设置 popover
- [x] 从旧 `LyricsViews.swift` 移除仅主窗口定义，保留三个辅助窗口视图
- [x] 将新文件加入 `SpotifyLyrics` Target

### Phase 4: Build Gates — completed
- [x] 组件完成后运行一次 `xcodebuild`，得到 `** BUILD SUCCEEDED **`
- [x] 最终 Debug 构建得到 `** BUILD SUCCEEDED **`，退出码 `0`
- [x] 确认 `MockData.swift`、`PlaybackState.swift`、`WindowManager.swift` 没有差异

### Phase 5: Runtime Visual Validation — completed
- [x] 启动 DerivedData 新 `.app`，并用进程绝对路径确认身份
- [x] 验证默认尺寸配置 `1040×680`；实际内容窗口约 `1038×680`
- [x] 验证最小尺寸约 `760×520` 内容（外框约 `760×552`）
- [x] 验证播放/暂停、进度变化、歌词随 Mock 时间变化
- [x] 验证原文/翻译/罗马音/假名开关和设置 popover
- [x] 保存并覆盖最终截图：`ui-redesign-assets/phase1-main-default.png` 与 `ui-redesign-assets/phase1-main-minimum.png`

### Phase 6: Handoff — completed
- [x] 展示 `git diff --stat`、关键 Swift diff、构建日志结尾和 app 绝对路径
- [x] 等待用户确认截图方向；用户已确认主窗口方向并给出 refinement 清单

### Phase 7: Main Window Refinement Contract — completed
- [x] 将用户确认的五项 refinement 写入红色合约
- [x] 运行合约并确认因 `TrackArtworkView` 尚未实现而失败
- [x] 完成实现后重新运行，合约通过

### Phase 8: Main Window Refinement — completed
- [x] 增加独立 Mock 专辑封面和弱化背景封面层
- [x] 增加上一首/播放暂停/下一首三键布局；单曲 Mock 的前后曲动作保持明确禁用
- [x] 让歌词舞台按可用宽度动态居中，减少宽窗口右侧空白
- [x] 将相邻/远处歌词 blur 降到可读范围
- [x] 为窗口模式入口增加可理解图标、Tooltip 和辅助标签

### Phase 9: Build and Runtime Evidence — completed
- [x] 运行阶段构建，得到 `** BUILD SUCCEEDED **`
- [x] 重新启动 DerivedData `.app`，验证默认/最小尺寸、控制布局、封面、歌词层级和窗口模式 Tooltip
- [x] 更新 `ui-redesign-assets/phase1-main-default.png` 与 `phase1-main-minimum.png`
- [x] 确认 `MockData.swift`、`PlaybackState.swift`、`WindowManager.swift` 与辅助模式没有差异
- [x] 运行最终用户指定 Debug 构建并读取日志结尾，返回 `0` 并输出 `** BUILD SUCCEEDED **`

### Phase 10: Main Window Commit — complete
- [x] 展示最终 `git status`、`git diff --stat`、构建日志结尾、app 路径和截图
- [x] 提交：`Refine verified main lyrics window`
- [x] 不进入 Provider、SQLite、Spotify 或悬浮/胶囊/全屏视觉实现

### Phase 11: Spotify Desktop Provider Contract — in_progress
- [x] 记录真实 Spotify.app 路径、版本和完整 `sdef` 字段/命令
- [x] 先写协议、状态和权限/回退契约，并确认红色失败

### Phase 12: Provider and State Synchronization — pending
- [x] 实现 `PlaybackProvider` 协议和 `SpotifyDesktopProvider`
- [x] 实现 Apple Events 读取歌曲、艺人、专辑、时长、位置、播放状态、封面 URL、Spotify URL/Track ID
- [x] 实现 play/pause/previous/next/seek
- [x] 加入本地时间插值、定期校准、暂停/seek/切歌重新同步
- [x] 实现 Spotify 不可用状态和 Mock 回退

### Phase 13: Artwork and Main Window Wiring — pending
- [x] 异步下载 artwork URL，增加内存/磁盘缓存和 Mock 封面回退
- [x] 主窗口接入真实 Track、封面、播放状态和进度；歌词数组保持 Mock，不接歌词源
- [x] 显示未安装、未运行、无歌曲、权限拒绝和连接失败状态

### Phase 14: Signing and Permission Gate — pending
- [x] 添加 `NSAppleEventsUsageDescription`
- [x] 添加 Apple Events entitlement
- [x] 用不带 `CODE_SIGNING_ALLOWED=NO` 的 Debug 构建启动应用并实际读取 Spotify 控制权限状态（TCC 在首次签名启动期间写入授权记录；未重置权限）

### Phase 15: Real Spotify Acceptance — pending
- [x] 使用至少五首真实歌曲，覆盖普通歌曲、长歌名、多艺人、暂停/恢复、切歌、seek、封面切换
- [x] 验证 Spotify 退出后重新打开和状态恢复
- [x] 保存真实歌曲运行截图并记录每首歌曲的可复核证据

### Phase 16: Build and Commit — pending
- [x] 运行无签名构建和正常签名 Debug 构建，均保留结果
- [x] 输出工作目录、修改文件、diff、xcodebuild、app 路径、权限和真实运行验证
- [x] 提交独立 commit：`3fcc104 Add verified Spotify desktop provider`

## Phase 17: Real Track Visual and Lyrics Slice — completed
- [x] 完成设计确认，写入 spec/plan，并提交 `60db497`
- [x] 写入红色核心契约并确认缺少生产核心文件时失败
- [x] 切歌 identity 变化时清空旧歌词、翻译、罗马音、假名、滚动位置和背景状态；lyrics/background 异步结果均二次核对 identity/revision/key
- [x] 区分真实 Spotify、Mock Preview、歌词加载中、无歌词和搜索失败状态；真实 Spotify 不回退 Mock 歌词
- [x] 定义 `LyricsProvider`，实现只读 LocalProvider 与 LRCLIBProvider；不接 SQLite、AI 或其他歌词源
- [x] 使用真实 artwork 生成主色多层渐变、放大裁切模糊纹理和可读性遮罩，并对旧背景做短暂交叉淡出
- [x] 已保存英文、日文、中文/无歌词和真实歌曲 loading 状态截图；亮/暗封面均已由真实封面运行样本覆盖
- [x] 完成 failed 状态的真实网络错误截图、最终正常签名 Debug build 和完整验收记录

## Phase 18: Playback and Lyrics Correctness — completed
- [x] 先写并观察红色契约：typed lyrics failure、noMatch、纯文本时间轴、候选手选/错误 identity 忽略、重试和播放控制
- [x] 将网络不可用、超时、服务端错误、解析失败建模为独立 `LyricsFailure`，并保留 noMatch 与 noLyrics 的不同状态
- [x] 低置信度候选不自动采用；UI 仅在当前 identity 下允许手动采用，错误与 noMatch 支持重新搜索
- [x] 无时间轴歌词不计算当前行，不伪造高亮/滚动，并以可读的全文样式展示
- [x] 保留 LyricsSessionController 的取消、revision、identity 二次核对，覆盖快速切歌和乱序返回；背景请求继续使用 identity/artwork key 与取消保护
- [x] 新增播放状态契约，覆盖真实播放 provider 的 pause/play、seek、previous/next、退出和重连后的 Track identity/进度状态
- [x] 已用正常签名 Debug 产物实际验证当前真实 Spotify 歌曲、连续切歌、封面/歌词切换、暂停/恢复、seek、上一首/下一首、Spotify 退出和重连
- [x] 运行最终全量契约、无签名 Debug build、正常签名 Debug build、codesign 验证和真实 Spotify 运行核对
- [x] 提交独立 commit：`Fix playback and lyrics state correctness`

## Phase 19: Lyrics Recovery and Safe Seek — complete
- [x] 先新增歌词恢复与安全 seek 回归契约，并观察红色失败
- [x] 网络错误恢复时对当前 Track identity 自动有限重试一次；保留手动重试且不改变播放锚点
- [x] 只允许合法逐行时间轴歌词触发 seek，拒绝纯文本、非法时间戳和非歌词状态
- [x] 增加 Debug seek 日志，完成全量契约和 Xcode 构建
- [x] 用正常签名 Debug 产物实际验证同步歌词点击 seek 与 Spotify 播放位置；网络恢复的有限重试由合同测试覆盖，未通过切换系统网络设置强行制造断网
- [x] 提交独立 commit：`Fix lyrics recovery and invalid lyric seek`

## Phase 20: Reference Audit and Switchable Main Layouts — complete
- [x] 先读 Lyricify LICENSE，审计其模式枚举/切换入口/持久化/主歌词界面文件
- [x] 黑盒观察 Dynamic Lyrics 与当前 Music.app，并记录窗口、AX、截图证据
- [x] 查询 Apple 官方 HIG、Materials、Windows 和 macOS Design Resources
- [x] 输出 `UI_LAYOUT_AUDIT_PHASE2.md` 与拟修改文件清单
- [x] 先让 `Tests/phase2_layout_contract.sh` 红灯，再实现 `lyricsFocus`/`immersiveSplit`
- [x] 两种布局共享播放、歌词会话、Provider、背景和控制逻辑；完成即时切换、截图、无签 Debug 构建和正常签名 Debug 构建
- [x] 提交独立 UI/搜索实现 commit，不修改悬浮/胶囊/全屏/SQLite/AI

## Phase 21: Independent Song Search — complete
- [x] 先写 SongSearchProvider 红色契约，覆盖统一结果模型、Provider 调度和旧请求取消
- [x] 实现 LocalSearchProvider、SpotifyCurrentTrackProvider、LRCLIBProvider
- [x] 实现 SongSearchManager，UI 只依赖 manager 与统一结果
- [x] 增加搜索入口、结果列表和点击结果加载歌词，不复制参考应用代码
- [x] 完成签名 Debug 构建、真实运行搜索和点击结果验证
- [x] 记录验证结果并提交独立搜索 commit

## Phase 22: Song and Lyrics Source Research — completed, awaiting user confirmation
- [x] 读取 `Lyricify-App-main` 许可证与公开实现线索；不读取 Dynamic Lyrics 闭源实现或资源
- [x] 调查 Spotify Web API、LRCLIB、网易云、QQ 音乐、酷狗、Apple Music/MusicKit 及补充来源的官方 API、条款、字段、额度、缓存与发布风险
- [x] 以当前日期记录实际官方来源、最小请求验证和非官方方案的维护风险
- [x] 审计当前 SongSearch/LyricsProvider/identity/matcher 架构是否混淆曲库搜索、当前播放识别和歌词版本搜索
- [x] 输出 `SOURCE_PROVIDER_RESEARCH.md`、推荐分层和分阶段接入计划；等待用户确认，不修改 Swift 或接入新 Provider


## Phase 23: Low-risk Architecture Split (Track vs Lyrics) — complete
- [x] Split SongSearchManager into TrackSearchManager + LyricsSearchManager with compatibility facade
- [x] Track search returns metadata-only TrackSearchResult (no lyrics body)
- [x] SpotifyCurrentTrackProvider repositioned as CurrentTrackResolver (not free-text catalog)
- [x] Shared read-only LocalLyricsIndex for LocalSearchProvider + LocalLyricsProvider
- [x] LRCLIB isolated to lyrics path with timeout/retry/429/cancel classification; disabled in track search
- [x] Contract tests: search models, provider failure matrix, existing song search + real track suites
- [x] Signed Debug xcodebuild + codesign verify + real Spotify Desktop launch smoke
- [x] Pause before Spotify Web OAuth / Chinese platform experimental plugins


## Phase 24: Japanese Alias + Lyrics Recovery Design — awaiting confirmation
- [x] Write design: alias model, query matrix, safe match, JP romanization, recovery, source survey
- [x] Add red contracts `Tests/japanese_alias_contract.*` (production sources intentionally missing)
- [ ] User confirms model choices (TrackMetadata shape, romaji style, recovery scope)
- [ ] Implement pure functions then Local/LRCLIB multi-variant only
- [ ] Do not enable NetEase/QQ/KuGou in core default path

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| 本轮只做审计 | 用户明确要求先核实现状，不继续开发 |
| 真实 Xcode 构建是工程成功的唯一构建证据 | 手工 `swiftc` 拼装不能证明 Xcode 工程有效 |
| 参考应用和仓库只读 | 防止把第三方二进制、品牌资源或源码混入独立 Swift 实现 |
| UI 结论必须来自实际窗口观察 | 进程存活或代码存在不等于窗口功能可用 |
| 本阶段视觉主参考收敛为 Dynamic Lyrics + Lyricify Apple Music 模式 | 用户确认只需要这两个产品方向；Music.app/HIG 仅保留平台约束，不作为样板 |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| None yet | 0 | — |
| zsh `status` is read-only while capturing a failing contract exit code | 1 | Re-ran with `rc` and confirmed the intended red exit code `1` |
| zsh glob for `SpotifyLyrics/Providers/*Lyrics*.swift` matched no files | 1 | Stopped using the speculative glob and enumerated the actual `SpotifyLyrics/Lyrics/` and `SpotifyLyrics/Search/` files |
| Computer Use 坐标点击误触“假名”开关 | 1 | 停止坐标点击，改用 AX 索引/键盘焦点并恢复状态 |
| 后续 `swift -e` WindowServer 查询被 Xcode license 提示阻止 | 1 | 不运行 sudo、不接受许可；改用已收集证据和 Computer Use 继续审计 |
| 播放计时器持续刷新导致 Computer Use 报告界面被改变 | 1 | 重新查询最终状态，确认暂停已生效，不把中间失败当成功 |
| 直接调用新 Xcode Swift 查询 WindowServer：缺少 SDK / CFArray 无 count | 1-2 | 第三次改用明确 SDK 和 Foundation NSArray 桥接 |
| Computer Use 不接受 `Space` 大写按键名 | 1 | 改用小写 `space`，并重新读取焦点状态 |
| AX 点击全屏按钮未触发状态变化 | 1 | 依据最新截图改用坐标点击，再用 WindowServer 验证 |
| 退出已关闭主窗口的应用时 LS 返回 procNotFound | 1 | 不重复退出；随后用 Computer Use 重新启动 DerivedData 产物并验证主窗口 |
| 同名旧手工进程遮蔽 DerivedData 产物 | 1 | 先通过应用菜单退出 `build/SpotifyLyrics.app`，再启动并用 `ps` 验证 DerivedData 可执行文件路径 |
| Dynamic Lyrics 二次读取超时 | 1 | 不重复操作；沿用已保存的黑盒截图/WindowServer 证据，并将胶囊具体展开态标为未验证 |

## Phase 25: Known Lyrics + Local Audio Line Alignment V1 — in progress (runtime correction)
- [x] 修复 `PlaybackState` 自动排轴环境钩子并通过接线红绿契约
- [x] 运行逐行对齐合同、正常签名 Debug 构建和 codesign 检查
- [x] 发现并复现错误：79.8255 秒 TTS 夹具被用于 171.177 秒 Spotify 歌曲，导致 1:18 结束和前置误动
- [x] 增加时长兼容保护、前置未匹配行的首锚点保护，并在真实 App 显示明确失败状态
- [ ] 使用与当前 Spotify 版本匹配的完整本地音频完成 QQ 32 行 → 有效逐行预览 → 确认保存
- [ ] 验证真实歌曲的开口起点、全曲尾点、播放跟随和确认前后播放位置不变
- [x] 保存时长拒绝的真实 App 截图、分层日志与回归合同
- [ ] 仅提交本阶段源代码、合同和更正后的验收证据；不提交 DerivedData 或备份目录

### Phase 25 Scope
- 只做已知纯文本歌词与用户本地音频的逐行自动排轴。
- 不新增歌词 Provider、音频下载、系统音频捕获、ASR-from-scratch、逐字时间轴或完整编辑器。

## Notes
- 任何无法真实验证的项目必须明确标记为“未验证”，不能推断为完成。
- 审计结束前不修改产品代码或工程配置。
