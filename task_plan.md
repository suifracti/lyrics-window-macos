# Task Plan: SpotifyLyrics Local Spotify Desktop Provider

## Goal
在已提交的主窗口基础上，实现下载后即可使用的本机 Spotify Desktop 播放链路：通过真实 Apple Events 读取 Spotify 当前歌曲、封面 URL、播放状态和进度，并提供播放控制；UI 只依赖 `PlaybackProvider` 协议；Spotify 不可用时明确显示并回退 Mock 预览。本阶段不实现 Web API、OAuth、SQLite、歌词 Provider 或在线歌词源。

## Next Step
完成“真实歌曲视觉与歌词纵向切片”：切歌时清空旧歌词/翻译/滚动/背景状态，接入 LocalProvider 与 LRCLIBProvider，生成与真实 artwork 绑定的主色渐变背景，并用真实歌曲截图验证加载、失败、无歌词和亮暗封面状态。

## Current Phase
Phase 17 — Real Track Visual and Lyrics Slice (design pending)

## Scope & Boundaries
- 唯一正式项目：`/Users/apple/backup/sptifylyrics`
- 黑盒 UI 参考：`/Applications/Dynamic Lyrics.app`（只读）
- 文档/截图参考：`Lyricify-App-main` 或未来的 `References/Lyricify-App`（只读）
- 歌词格式参考：未来的 `References/Lyricify-Lyrics-Helper`（只读；不复制或链接代码）
- 本轮允许写入：Provider 协议/实现、PlaybackState 的 Provider 接线、Track/封面缓存模型、主窗口状态提示、Info.plist/Apple Events entitlement、测试契约、`task_plan.md`、`progress.md` 和真实 Spotify 运行截图
- 本轮禁止：Spotify Web API、OAuth、SQLite、LocalProvider/LRCLIB、AI、自动排轴、任何歌词源；不修改 Dynamic Lyrics、Lyricify-App-main 或参考应用资源；不改变悬浮/胶囊/全屏视觉实现

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

## Phase 17: Real Track Visual and Lyrics Slice — design pending
- [ ] 先完成设计确认，再写实现计划和红色契约
- [ ] 切歌 identity 变化时清空旧歌词、翻译、罗马音、假名、滚动位置和背景状态
- [ ] 区分真实 Spotify、Mock Preview、歌词加载中、无歌词和搜索失败状态
- [ ] 定义 `LyricsProvider`，实现 LocalProvider 与 LRCLIBProvider；不接 SQLite、AI 或其他歌词源
- [ ] 使用真实 artwork 生成主色多层渐变、放大裁切模糊纹理和可读性遮罩
- [ ] 以英文、日文、中文、无歌词、亮/暗封面和切歌过程保存实际截图
- [ ] 运行契约、Xcode Debug build 和真实应用验收；未通过不得声称完成

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| 本轮只做审计 | 用户明确要求先核实现状，不继续开发 |
| 真实 Xcode 构建是工程成功的唯一构建证据 | 手工 `swiftc` 拼装不能证明 Xcode 工程有效 |
| 参考应用和仓库只读 | 防止把第三方二进制、品牌资源或源码混入独立 Swift 实现 |
| UI 结论必须来自实际窗口观察 | 进程存活或代码存在不等于窗口功能可用 |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| None yet | 0 | — |
| Computer Use 坐标点击误触“假名”开关 | 1 | 停止坐标点击，改用 AX 索引/键盘焦点并恢复状态 |
| 后续 `swift -e` WindowServer 查询被 Xcode license 提示阻止 | 1 | 不运行 sudo、不接受许可；改用已收集证据和 Computer Use 继续审计 |
| 播放计时器持续刷新导致 Computer Use 报告界面被改变 | 1 | 重新查询最终状态，确认暂停已生效，不把中间失败当成功 |
| 直接调用新 Xcode Swift 查询 WindowServer：缺少 SDK / CFArray 无 count | 1-2 | 第三次改用明确 SDK 和 Foundation NSArray 桥接 |
| Computer Use 不接受 `Space` 大写按键名 | 1 | 改用小写 `space`，并重新读取焦点状态 |
| AX 点击全屏按钮未触发状态变化 | 1 | 依据最新截图改用坐标点击，再用 WindowServer 验证 |
| 退出已关闭主窗口的应用时 LS 返回 procNotFound | 1 | 不重复退出；随后用 Computer Use 重新启动 DerivedData 产物并验证主窗口 |
| 同名旧手工进程遮蔽 DerivedData 产物 | 1 | 先通过应用菜单退出 `build/SpotifyLyrics.app`，再启动并用 `ps` 验证 DerivedData 可执行文件路径 |
| Dynamic Lyrics 二次读取超时 | 1 | 不重复操作；沿用已保存的黑盒截图/WindowServer 证据，并将胶囊具体展开态标为未验证 |

## Notes
- 任何无法真实验证的项目必须明确标记为“未验证”，不能推断为完成。
- 审计结束前不修改产品代码或工程配置。
