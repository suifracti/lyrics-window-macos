# Task Plan: SpotifyLyrics UI Reference Audit

## Goal
在 `ui-reference-audit` 分支上完成 Dynamic Lyrics 黑盒、Lyricify 公开资料和当前标准 Xcode 产物的 UI 参考审计，形成独立视觉设计规范与分阶段改造计划；不修改 Swift 源码、Xcode 工程或任何 `.app`。

## Next Step
完成最终文档/状态边界核验，确认只新增审计文档、规划日志和截图资产。

## Current Phase
Phase 6 — Audit Deliverable and Verification

## Scope & Boundaries
- 唯一正式项目：`/Users/apple/backup/sptifylyrics`
- 黑盒 UI 参考：`/Applications/Dynamic Lyrics.app`（只读）
- 文档/截图参考：`Lyricify-App-main` 或未来的 `References/Lyricify-App`（只读）
- 歌词格式参考：未来的 `References/Lyricify-Lyrics-Helper`（只读；不复制或链接代码）
- 本轮允许写入：`UI_REFERENCE_AUDIT.md`、审计截图资产目录、`task_plan.md`、`findings.md`、`progress.md`
- 本轮禁止修改：Swift 源码、`SpotifyLyrics.xcodeproj`、任何 `.app`、`Dynamic Lyrics.app`、`Lyricify-App-main/`、Spotify/歌词 Provider/SQLite/AI/自动排轴

## Phases

### Phase 1: Scope and Reference Collection — completed
- [x] 读取 `AUDIT.md` 和基线 commit
- [x] 创建并切换 `ui-reference-audit` 分支
- [x] 盘点 Lyricify README/docs/images 与许可/素材边界
- [x] 读取 Dynamic Lyrics `Info.plist` 和公开资源清单

### Phase 2: Dynamic Lyrics Black-box Audit — completed
- [x] 观察主窗口、悬浮歌词、顶部胶囊收起/展开、全屏歌词；胶囊具体展开内容标记为未验证
- [x] 记录窗口尺寸、位置、透明度、圆角、阴影、层级和状态切换
- [x] 保存关键状态截图；不修改、提取或复用专有素材

### Phase 3: Current Product UI Audit — completed
- [x] 退出旧手工进程后启动 DerivedData 标准 `.app`，确认可执行文件路径
- [x] 记录主窗口、悬浮歌词、顶部胶囊、全屏歌词真实截图和窗口测量
- [x] 观察歌词层级、设置占比、背景材质和控制区布局

### Phase 4: Comparison Matrix — completed
- [x] 对照参考对象和当前实现逐项记录差异
- [x] 明确当前测试面板、卡片背景、胶囊宽度/动画、全屏覆盖和设置占比问题

### Phase 5: Independent UI Design Plan — completed
- [x] 提出主窗口、胶囊、悬浮歌词、全屏歌词的独立视觉方案
- [x] 定义字体、材质、圆角、间距、动画、主题和窗口尺寸规范
- [x] 建议 SwiftUI/AppKit 组件边界和分阶段改造顺序

### Phase 6: Audit Deliverable and Verification — completed
- [x] 创建 `UI_REFERENCE_AUDIT.md`
- [x] 检查没有修改 Swift、Xcode 工程、应用包或参考对象
- [x] 输出分支、路径、`git status --short` 和 `git diff --stat`

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
