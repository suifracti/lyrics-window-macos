# Task Plan: SpotifyLyrics Xcode 构建基线

## Goal
建立可重复、可验证的标准 Xcode Debug 构建基线，区分旧手工 `build/SpotifyLyrics.app` 与新的 `DerivedData` 产物，并对新产物进行真实窗口验证。

## Next Step
后续产品功能工作应从独立分支开始；本基线 commit 保持不变。

## Current Phase
Phase 5 — Documentation and Commit

## Scope & Boundaries
- 唯一正式项目：`/Users/apple/backup/sptifylyrics`
- 黑盒 UI 参考：`/Applications/Dynamic Lyrics.app`（只读）
- 文档/截图参考：`Lyricify-App-main` 或未来的 `References/Lyricify-App`（只读）
- 歌词格式参考：未来的 `References/Lyricify-Lyrics-Helper`（只读；不复制或链接代码）
- 本轮允许写入：`AUDIT.md`、`.gitignore`、`task_plan.md`、`findings.md`、`progress.md`；如 Scheme 缺失，仅修复 Scheme 或工程配置
- 本轮禁止修改：Swift 产品功能、任何参考目录、任何 `.app`、Spotify/歌词 Provider/SQLite/AI/自动排轴

## Phases

### Phase 1: Environment and Project — complete
- [x] 输出工作目录、Git 状态和最近五次提交
- [x] 检查完整 Xcode、默认开发者目录和工程可解析性
- [x] 审计 `project.pbxproj`、Scheme、Target、Bundle ID、Deployment Target、Build Settings
- [x] 检查现有 `build/SpotifyLyrics.app` 的来源、Info.plist、架构和源码一致性

### Phase 2: Xcode Discovery — complete
- [x] 输出 `xcode-select -p`
- [x] 输出 `xcodebuild -version`
- [x] 使用指定 `DEVELOPER_DIR` 运行 `xcodebuild -list -project SpotifyLyrics.xcodeproj`
- [x] 确认 Target 与 Scheme 可用

### Phase 3: Standard Debug Build — complete
- [x] 使用指定命令执行真实 Debug `xcodebuild`
- [x] 记录 `BUILD SUCCEEDED` 日志结尾
- [x] 记录 Xcode 生成的 `.app` 绝对路径
- [x] 确认旧 `build/SpotifyLyrics.app` 与新产物分离

### Phase 4: Runtime UI Audit — complete
- [x] 启动 DerivedData 中的新 `.app`
- [x] 验证主窗口、悬浮歌词、顶部胶囊、全屏覆盖歌词
- [x] 验证辅助窗口关闭与重新打开

### Phase 5: Documentation and Commit — complete
- [x] 将 `DerivedData/` 和 `build/` 加入 `.gitignore`
- [x] 更新 `AUDIT.md` 记录真实 Xcode 构建和运行时结果
- [x] 提交 `Establish verified Xcode build baseline`

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

## Notes
- 任何无法真实验证的项目必须明确标记为“未验证”，不能推断为完成。
- 审计结束前不修改产品代码或工程配置。
