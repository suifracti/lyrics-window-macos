# Task Plan: SpotifyLyrics UI Redesign Phase 1

## Goal
在 `ui-redesign-phase-1` 分支上实现已确认的主窗口阶段 0/1：Canvas-first 单画布、独立视觉 token、当前/相邻歌词层级和设置 popover；不修改悬浮歌词、顶部胶囊、全屏窗口、数据含义或外部功能。

## Next Step
完成已确认的主窗口 refinement：Mock 封面、三键播放控制、宽窗口动态布局、较轻的非当前歌词模糊和明确的窗口模式入口；重新构建、运行取证并提交独立主窗口 commit。

## Current Phase
Phase 7 — Main Window Refinement Contract

## Scope & Boundaries
- 唯一正式项目：`/Users/apple/backup/sptifylyrics`
- 黑盒 UI 参考：`/Applications/Dynamic Lyrics.app`（只读）
- 文档/截图参考：`Lyricify-App-main` 或未来的 `References/Lyricify-App`（只读）
- 歌词格式参考：未来的 `References/Lyricify-Lyrics-Helper`（只读；不复制或链接代码）
- 本轮允许写入：主窗口 Swift 组件、Target 文件引用、`Tests/phase1_ui_contract.sh`、`task_plan.md`、`progress.md`、`ui-redesign-assets/`
- 本轮禁止修改：`MockData.swift`、`PlaybackState.swift`、`WindowManager.swift`、悬浮/胶囊/全屏窗口行为、`Dynamic Lyrics.app`、`Lyricify-App-main/`、Spotify/歌词 Provider/SQLite/AI/自动排轴

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
