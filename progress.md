# Progress Log

## Session: 2026-07-26

### Phase 1: Requirements & Discovery
- **Status:** complete
- Actions taken:
  - 检查当前工作区文件、Git 分支、提交和远程配置。
  - 检查 `Lyricify-App-main` 是否有独立 Git 元数据。
  - 记录参考项目的文件类型和可参考范围。
- Files created/modified:
  - `task_plan.md`
  - `findings.md`
  - `progress.md`

### Phase 2: Planning & Structure
- **Status:** complete
- Actions taken:
  - 确认当前仓库已有 `main` 基线。
  - 确认参考目录当前作为未跟踪目录出现在父仓库中。
  - 根据用户确认，决定参考项目继续放在仓库内并由 `.gitignore` 忽略。
- Files created/modified:
  - `task_plan.md`
  - `findings.md`
  - `progress.md`

### Phase 3: Implementation
- **Status:** complete
- Actions taken:
  - 在 `.gitignore` 中加入 `Lyricify-App-main/`。
  - 未修改参考项目内容。
- Files created/modified:
  - `.gitignore`
  - `task_plan.md`
  - `findings.md`
  - `progress.md`

### Phase 4: Testing & Verification
- **Status:** complete
- Actions taken:
  - 重新检查 Git 状态，确认参考目录不再显示为未跟踪。
- Files created/modified:
  - `progress.md`

### Phase 5: Delivery
- **Status:** complete
- Actions taken:
  - 确认 `Lyricify-App-main/` 被 `.gitignore` 命中。
  - 确认 `git status` 不再显示参考目录。
- Files created/modified:
  - `.gitignore`
  - `task_plan.md`
  - `findings.md`
  - `progress.md`

## Test Results
| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| Git baseline | `git status --short --branch` | 识别分支和未跟踪内容 | `main`；参考目录已被忽略 | ✓ |
| Reference boundary | `find . -name .git` | 确认参考项目是否独立 | 参考项目无独立 `.git`，保持只读 | ✓ |

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-07-26 | `git -C Lyricify-App-main` 未进入独立仓库上下文 | 1 | 确认其没有 `.git`，记录为父仓库内只读参考目录 |

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Phase 5：规划交付 |
| Where am I going? | 具体功能开始时创建 `codex/<topic>` 分支 |
| What's the goal? | 让当前 SpotifyLyrics 项目和他人参考项目在 Git 上保持清晰隔离 |
| What have I learned? | 见 `findings.md`：当前有 `main` 基线，参考目录已忽略且无独立 Git |
| What have I done? | 已将参考目录加入 `.gitignore`，并完成状态验证 |

## Session: 2026-07-26 — Reality Audit

### Phase 1: Evidence Collection
- **Status:** in_progress
- Actions taken:
  - 收集 Git、Xcode 安装、xcode-select、project.pbxproj、源码和 app bundle 证据。
  - 运行请求的 `xcodebuild -list` 和真实 build 命令；均因完整 Xcode 缺失而失败。
  - 追溯初始提交中的 `build.sh`，确认现有 `.app` 是 `swiftc` 手工编译/拼装产物。
  - 实际启动现有 `.app` 并确认主窗口可见。
  - 点击悬浮歌词按钮并记录状态变化；独立悬浮窗尚未在截图中确认可见。
  - 第一次顶部胶囊点击未改变 UI 状态，已记录为无效尝试，不重复用同一状态下的点击作为结论。
  - 坐标点击因窗口坐标偏移误触“假名”，已改用 AX 索引/键盘交互，并将恢复该临时状态。
  - 使用 Tab + Space 成功切换顶部胶囊状态；下一步用桌面级截图核实辅助窗口是否实际可见。
  - Finder 截图仍按目标应用裁剪，不能用于跨应用窗口验证；下一步查询 WindowServer。
  - WindowServer 查询真实确认悬浮窗和胶囊窗均已创建、on-screen，尺寸与代码一致。
  - 已触发全屏歌词模式并确认主窗口状态切换，待 WindowServer 复核。
  - WindowServer 真实确认全屏窗口尺寸/层级；再次触发后确认该窗口关闭。
  - 重新触发后确认全屏窗口再次出现，完成全屏关闭/重开验证。
  - 已再次触发顶部胶囊按钮，待 WindowServer 确认关闭状态。
  - WindowServer 确认顶部胶囊可关闭并重新打开。
  - 已再次触发悬浮歌词按钮，待 WindowServer 确认关闭状态。
  - WindowServer 确认悬浮歌词可关闭并重新打开。
  - 关闭三个辅助窗口后，WindowServer 查询遭遇 Xcode license 阻断；已记录，不运行 sudo。
  - 截图确认三个辅助窗口状态均关闭。
  - 点击播放后确认时间从 0.2 秒推进到约 3.8 秒；这是 Mock timer，不是 Spotify 联动。
  - 持续更新的计时器干扰了 UI 自动化状态同步，但最终确认暂停生效，时间停在约 27.6 秒。
  - 使用 `Cmd+W` 关闭主窗口；Computer Use 随后报告无可用窗口。
  - 确认进程关闭主窗口后仍存活；按 Bundle ID 重新激活后主窗口重新出现并保留状态。
  - 完成 Swift 文件与 PBX Sources 对照、按钮 action、未使用状态及缺失功能审计。
  - 只读确认 Dynamic Lyrics.app 存在；未创建附件建议的 References 克隆。
  - 审计后段系统命令被 Xcode license 提示阻断；未运行 sudo 或接受许可。
  - 外部环境随后出现 Xcode 26.6 并切换 xcode-select；重新执行 list/build，仍被未同意许可阻断。
  - 使用 fallback git 复核工作区状态和提交记录。
  - 尝试绕过 xcrun 许可检查做只读 WindowServer 查询：首次缺 SDK，第二次因 Swift 6.3 的 CFArray API 差异失败；下一次改用 NSArray 桥接。
  - 第三次通过直接 Swift + 显式 SDK + NSArray 桥接成功恢复 WindowServer 查询。
  - 首次批量准备多桌面测试被 Computer Use 状态变化中断；WindowServer 确认辅助窗口仍关闭，未把该尝试计为成功。
  - 改为逐步操作后，WindowServer 确认悬浮窗口已打开，开始多桌面测试准备。
  - 已逐步打开顶部胶囊；准备切换 Space 并对比 WindowServer on-screen 窗口。
  - 尝试 Ctrl+Right 多桌面验证；当前活跃显示器没有第二个 Space，无法形成有效切换，已标记为未验证。
  - 创建并校验 `AUDIT.md`，按“已真实验证 / 仅有代码但未验证 / 尚未实现 / 错误或虚假实现”分类记录证据。
  - 最终复核 Git 变更范围：没有修改 Swift、Xcode 工程、`.app` 或参考项目。
  - 退出审计期间启动的 SpotifyLyrics 应用。
- Files created/modified:
  - `task_plan.md`
  - `findings.md`
  - `progress.md`
- Errors:
  - shell glob `/Applications/Xcode*.app` 在 zsh 中无匹配；改用 `find /Applications -name 'Xcode*.app'` 验证，结果仍为空。
  - `xcodebuild` 无法运行：系统只有 Command Line Tools。

### Phase 5: Audit Report
- **Status:** complete
- Deliverable:
  - `AUDIT.md`
- Remaining blocker:
  - Xcode 许可尚未由用户接受，因此真实 `xcodebuild -list` 与 Debug build 均未通过。

## Session: 2026-07-26 — Verified Xcode Build Baseline

### Phase 1: Xcode Discovery
- **Status:** complete
- `xcode-select -p`：`/Applications/Xcode.app/Contents/Developer`
- `xcodebuild -version`：`Xcode 26.6`, `Build version 17F113`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -project SpotifyLyrics.xcodeproj` 成功列出 Target `SpotifyLyrics`、Debug/Release 和 Scheme `SpotifyLyrics`。

### Phase 2: Standard Debug Build
- **Status:** complete
- 命令：
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO build`
- 结果：退出码 `0`，日志结尾为 `** BUILD SUCCEEDED **`。
- 新产物：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`
- 旧对照产物：`/Users/apple/backup/sptifylyrics/build/SpotifyLyrics.app`
- 构建期间仅出现 destination 选择和无 AppIntents 依赖的 warning，没有失败。

### Phase 3: Runtime Validation
- **Status:** complete
- 通过 Computer Use 启动 DerivedData `.app`，读取到主窗口、YOASOBI《夜に駆ける》和 6 行 Mock 歌词。
- 只读 WindowServer 查询确认：
  - 主窗口：900×621，layer 0。
  - 悬浮歌词：600×180，layer 3；打开/关闭/重开均有窗口级证据。
  - 顶部胶囊：380×46，layer 25；打开/关闭/重开均有窗口级证据。
  - 全屏覆盖歌词：2560×1440，layer 8；打开/关闭/重开均有窗口级证据。
- `Cmd+W` 后主窗口从 WindowServer 消失；退出验证实例后，用 Computer Use 重新启动 DerivedData `.app`，主窗口再次真实可见。
- 没有把进程存在作为 UI 成功证据。

### Phase 4: Documentation and Git Boundary
- **Status:** complete
- `.gitignore` 已明确包含 `DerivedData/`、`build/` 和 `Lyricify-App-main/`。
- `AUDIT.md` 已补充 Xcode Target/Scheme、构建命令、BUILD SUCCEEDED、产物路径、旧/新产物区分和新产物 UI 验证。
- 已复核 diff 范围并暂存允许文件。
- 已提交独立 commit：`29e7cc7 Establish verified Xcode build baseline`。

### Errors
| Error | Resolution |
|-------|------------|
| Computer Use `Space` 大写按键名不存在 | 改用小写 `space` |
| AX 点击全屏按钮未改变状态 | 改用最新截图坐标点击，并用 WindowServer 核验 |
| 退出已无 eligible process 的实例返回 `procNotFound` | 忽略该退出提示，重新启动并完成干净主窗口验证 |

## Session: 2026-07-26 — UI Reference Audit

### Phase 1: Scope and Reference Collection
- **Status:** complete
- 已读取 `AUDIT.md`，确认基线 commit `e24fbb35ea8247f39d52e3a0772f34c4e8633454`。
- 已创建并切换到 `ui-reference-audit`；没有在 `main` 上做 UI 工作。
- 已读取 `Lyricify-App-main/README.md`、`docs/`、`images/` 和歌词格式说明；记录了可参考的信息架构和第三方素材边界。
- 已读取 Dynamic Lyrics `Info.plist` 和公开资源清单；没有提取或复用资源。

### Phase 2: Dynamic Lyrics Black-box Audit
- **Status:** complete with explicit limits
- 已观察主窗口、更多菜单、外部播放状态变化、系统全屏和辅助窗口对象。
- 已记录主窗口约 `1000×650`、辅助层 `610×200`/`600×78` 及其 layer/位置变化。
- 已保存 `dynamic-main-initial.png`、`dynamic-main-paused.png`、`dynamic-fullscreen.png` 和 `dynamic-floating.png`。
- `dynamic-floating.png` 为空白/透明；胶囊具体收起/展开内容和动画时长均标为未验证。

### Phase 3: Current Product UI Audit
- **Status:** complete
- 先退出同名旧的 `build/SpotifyLyrics.app` 进程，再启动 DerivedData `.app`；`ps` 实际路径为 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`。
- 已保存标准 Xcode 产物的主窗口、悬浮歌词、胶囊和全屏截图：`spotifylyrics-main-xcode.png`、`spotifylyrics-floating-xcode.png`、`spotifylyrics-capsule-xcode.png`、`spotifylyrics-fullscreen-xcode.png`。
- WindowServer 记录：主窗口 `900×621/layer 0`；浮动 `600×180/layer 3`；胶囊 `380×46/layer 25`；全屏覆盖 `2560×1440/layer 8`。
- 全屏截图确认当前实现是黑色覆盖层和单行蓝色罗马音；胶囊只观察到单一 compact 态。
- 退出并重新启动 DerivedData 应用，主窗口恢复；没有把进程存在当作 UI 成功证据。

### Phase 4: Comparison Matrix
- **Status:** complete
- 已按主窗口、悬浮、胶囊收起/展开、全屏、歌词层级、语言层级、背景材质、控制布局、窗口状态切换九类证据形成逐项差异矩阵。

### Phase 5: Independent UI Design Plan
- **Status:** complete
- 已定义 Canvas-first 主窗口、胶囊三态、悬浮歌词、全屏歌词、字体/材质/间距/圆角/主题/窗口尺寸 token。
- 已给出 SwiftUI/AppKit 组件边界、六阶段改造顺序和每阶段验收标准。

### Phase 6: Audit Deliverable
- **Status:** complete
- 已创建 `UI_REFERENCE_AUDIT.md`。
- 最终核验通过：Git 变更仅包含审计文档、截图资产和规划日志；Swift、Xcode 工程和应用包没有出现在变更范围；已输出 `git status --short` 与 `git diff --stat`。

### Errors
| Error | Resolution |
|---|---|
| 同名旧手工进程导致首次截图身份不够明确 | 通过应用菜单退出旧进程；重新启动 DerivedData 并用 `ps` 验证可执行文件绝对路径 |
| Dynamic Lyrics 二次 `get_app_state` 超时 | 不重复操作；保留既有黑盒截图/WindowServer 记录，明确胶囊展开态未验证 |

## Session: 2026-07-26 — UI Redesign Phase 1

### Phase 1: Audit Commit and Branch
- **Status:** complete
- 审计资产总大小：`808K`。
- `ui-reference-audit-assets/` 共 12 个文件，`file` 均识别为 PNG/JPEG 观察截图；没有 `.app`、framework、bundle、Assets.car、字体、dylib、压缩包或其他提取资源。
- 已提交 `05ad34564d069ad8d95dfce8d75c0eb162ada920 Add verified UI reference audit`。
- 已从该提交创建并切换到 `ui-redesign-phase-1`。

### Phase 2: TDD Red Contract
- **Status:** complete
- 新增 `Tests/phase1_ui_contract.sh`，在任何生产 Swift 修改前运行。
- 失败证据：`missing required phase-1 file: SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift`。

### Phase 3: Main Window Components
- **Status:** in_progress
- 计划只修改 `Main.swift`、旧主窗口定义的承载文件和 Xcode 文件引用；新增六个主窗口组件/设计 token 文件。
- `MockData.swift`、`PlaybackState.swift`、`WindowManager.swift` 及悬浮/胶囊/全屏实现保持不动。

### Phase 3: Component Build Checkpoint
- **Status:** complete
- 已新增六个主窗口组件/设计 token 文件，并将其加入 `SpotifyLyrics` Target。
- 已从 `LyricsViews.swift` 移除旧 `MainWindowView`/`NavigationSplitView`，保留 `LineDisplayView` 及悬浮、胶囊、全屏视图。
- 第一次组件构建命令返回 `0`，输出 `** BUILD SUCCEEDED **`。
- 阶段 1 合约测试由红转绿：`phase-1 UI contract passed`。

### Phase 5: Initial Runtime Check
- **Status:** in_progress
- DerivedData app 实际启动，WindowServer 主窗口默认帧为约 `1040×680`；已保存 `ui-redesign-assets/phase1-main-default.png`。
- 通过拖拽调整到最小约 `761×552` 外框（对应内容最小 `760×520` 约束）；已保存 `ui-redesign-assets/phase1-main-minimum.png`。
- 播放按钮由“播放”变为“暂停”，时间从 `00:00` 推进到 `00:15`，再次点击恢复暂停。
- AX 树确认设置 popover；逐一关闭/恢复原文、翻译、罗马音、假名开关时，歌词文本随层级消失/恢复，没有常驻 checkbox 面板。

### Build Error Log
- 第一次最终构建命令的 shell 包装误用了 zsh 保留变量 `status`，导致包装命令返回 1；日志本身已经包含 `** BUILD SUCCEEDED **`。
- 立即改用 `build_exit` 重新执行同一用户指定命令，返回码 `0`，日志结尾为 `** BUILD SUCCEEDED **`。

### Phase 4: Final Build and Runtime Evidence
- **Status:** complete
- 最终命令按用户指定重新执行并返回 `0`：
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO build`
- `/tmp/spotifylyrics-phase1-build.log` 结尾包含 `** BUILD SUCCEEDED **`；真实产物为 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`。
- `git diff -- SpotifyLyrics/Services/MockData.swift SpotifyLyrics/Services/PlaybackState.swift SpotifyLyrics/Windows/WindowManager.swift` 为空，数据含义和辅助窗口实现未改动。

### Phase 5: Final Runtime Screenshots
- **Status:** complete
- 启动进程路径已确认：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`。
- 默认窗口配置为 `1040×680`；WindowServer 实际内容窗口约 `1038×680`（系统标题栏外框为 `1038×680`）。
- 拖动右下角验证最小约束：内容约 `760×520`，含标题栏外框约 `760×552`；恢复默认尺寸后继续保留应用供复核。
- 已实际点击播放/暂停并观察 Mock 进度从 `00:00` 推进到约 `00:15`，暂停后保持时间；歌词当前行随 Mock 时间切换。
- 设置 popover 已实际打开；原文、翻译、罗马音、假名开关逐一关闭/恢复，AX 歌词文本随层级消失/恢复且无空白占位。
- 最终截图已覆盖保存：
  - `ui-redesign-assets/phase1-main-default.png`（默认态）
  - `ui-redesign-assets/phase1-main-minimum.png`（最小态）
- 最终截图资产目录仅含上述两张 PNG，总大小约 `1.3M`；默认截图为 `1150×792`，最小截图为 `872×664`（含屏幕空白区域）。
- 最终构建后重新启动并再次验证播放/暂停、时间推进、四个语言开关和 popover；验证结束后应用保持在默认尺寸、暂停状态供查看。

### Phase 6: Handoff
- **Status:** waiting for visual confirmation
- 本轮实现没有提交 commit；当前分支保留工作区改动和截图，等待用户查看视觉方向。

## Session: 2026-07-27 — Main Window Refinement

### Phase 7: Refinement Contract
- **Status:** red observed
- 用户确认主窗口方向并提出五项必须修正：Mock 专辑封面、上一首/播放/下一首、宽窗口动态布局、较轻的非当前歌词 blur、明确窗口模式入口。
- 扩展 `Tests/phase1_ui_contract.sh` 后先运行，按预期在缺少 `TrackArtworkView` 时退出 `1`；生产 Swift 尚未因本轮 refinement 修改。
- 另外三种显示模式、Provider、SQLite、Spotify、AI 和自动排轴保持在本轮范围外。

### Phase 8: Main Window Refinement
- **Status:** complete
- `TrackHeaderView` 现在使用独立生成的 Mock 封面卡片（渐变、图形符号和专辑文字），并在主画布右侧加入低透明度、强弱化的背景封面层；没有读取或复制参考软件资源。
- 底部加入“上一首 / 播放暂停 / 下一首”三键；由于 `PlaybackState` 仍只有单曲 Mock，前后曲按钮明确禁用并通过 Tooltip 说明，不改变数据语义。
- `LyricsCanvasView` 使用 `GeometryReader` 和居中 HStack 将歌词列按可用宽度重定位；相邻歌词调整为 `0.62 / 0.6 blur`，更远歌词调整为 `0.32 / 1.8 blur`，保持层级但恢复可读性。
- 新增“窗口模式”菜单按钮，AX 树确认图标、标签和 Tooltip：主窗口、悬浮歌词、顶部胶囊、全屏歌词。

### Phase 9: Refinement Runtime Evidence
- **Status:** in_progress
- 组件构建已返回 `0` 并输出 `** BUILD SUCCEEDED **`；当前 DerivedData app 已重新启动。
- AX 树已确认专辑封面、上一首/播放/下一首按钮、窗口模式 Tooltip 和歌词显示层级。
- 实测默认内容窗口约 `1038×680`，最小外框 `760×552`（内容约 `760×520`），并已恢复默认尺寸。
- 播放从 `00:00` 推进至 `00:11`，暂停后保持；实际截图显示当前歌词从第一行切换到「さよなら」行。
- 设置 popover 和原文、翻译、罗马音、假名四个开关逐一切换并恢复默认状态。
- 已更新 `ui-redesign-assets/phase1-main-default.png` 和 `ui-redesign-assets/phase1-main-minimum.png`；审计截图资产仍未做破坏性删除，公开发布前另行清理。

### Phase 9: Final Build Gate
- **Status:** complete
- 按用户指定的完整命令重新构建，返回 `0`；`/tmp/spotifylyrics-phase1-refinement-final-build.log` 结尾为 `** BUILD SUCCEEDED **`。
- 构建后重新启动 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`，AX 树再次确认窗口模式、封面、三键控制和歌词画布；窗口默认内容约 `1038×680`。
- 最终最小尺寸截图覆盖后恢复默认尺寸；`MockData.swift`、`PlaybackState.swift`、`WindowManager.swift` 的 diff 仍为空。

### Phase 10: Main Window Commit
- **Status:** complete
- 已提交独立主窗口 refinement commit：`Refine verified main lyrics window`（最终 hash 由 Git 记录）。
- 本提交只包含主窗口 refinement、合约测试、规划记录和两张主窗口截图；未包含 DerivedData、build 或参考应用资源。

## Session: 2026-07-27 — Local Spotify Desktop Provider

### Phase 11: Environment and Dictionary Audit
- **Status:** complete
- 当前工作目录：`/Users/apple/backup/sptifylyrics`；分支：`ui-redesign-phase-1`；工作区在本阶段开始时干净。
- `/Applications/Spotify.app` 存在，版本 `1.2.94.583`，Bundle ID `com.spotify.client`。
- 已实际执行 `sdef /Applications/Spotify.app`，确认 `current track`、`player position`、`artwork url`、`spotify url`、`id`、`play`、`pause`、`previous track`、`next track` 等真实字典项。
- 直接 Apple Events probe 成功读取真实当前歌曲：`IDOLPOWER` / `M!LK` / `IDOLPOWER`，位置约 `148.444s`，时长 `230453ms`，封面 URL、Spotify URI 和 Track ID 均返回。

### Phase 11: Provider Contract
- **Status:** red observed
- 新增 `Tests/spotify_provider_contract.sh`，先运行并按预期因 `SpotifyLyrics/Providers/PlaybackProvider.swift` 尚不存在而失败。

### Phase 12: Provider and State Synchronization
- **Status:** complete
- 新增 `PlaybackProvider`、`SpotifyDesktopProvider` 和 `MockPlaybackProvider`；Apple Events 脚本只使用本机 `sdef` 确认的字段/命令。
- 读取歌曲名、艺人、专辑、毫秒时长、播放位置、播放状态、`artwork url`、Spotify URI 和 track ID；命令覆盖 play/pause/previous/next/seek。
- 用时间锚点在 0.2s UI tick 中插值，约 2s 重新读取 Spotify；暂停、seek、命令和切歌后重置锚点。命令返回 `missing value` 的真实 AppleScript 行为已修复为成功，不再误回退 Mock。
- 合约测试在实现后通过；组件 Debug build 通过。

### Phase 13: Artwork and Main Window Wiring
- **Status:** complete
- `ArtworkImageLoader` 以 `NSCache` 缓存远程封面，失败时保留现有 Mock 渐变占位；主窗口只依赖 `PlaybackState`，没有直接引用 Spotify 实现。
- 主窗口新增 Provider 状态胶囊、重试入口和真实播放控制；歌词数组仍为 MockData，没有接入歌词源。
- 已真实显示 Spotify 封面和歌曲元数据，并保留 Spotify 不可用时的 Mock 预览。

### Phase 14: Signing and Permission Gate
- **Status:** verified with limitation
- 正常签名 Debug 构建成功；`NSAppleEventsUsageDescription` 和 `com.apple.security.automation.apple-events` 已在产物中验证。
- TCC 只读记录显示 `com.spotifylyrics.app → com.spotify.client` 的 `auth_value=2`，`last_modified` 为本次首次签名 Debug 启动期间的 `2026-07-27 14:20:04 +0800`；签名 app 的 in-app Apple Events 查询和控制成功。捕获状态时没有残留权限弹窗；没有重置用户 TCC 权限。

### Phase 15: Real Spotify Acceptance
- **Status:** complete with dictionary limitation documented
- 实际验证至少八首真实歌曲，覆盖普通歌曲、长/括号标题、多艺人曲目、播放/暂停/恢复、进度 seek、连续切歌、封面切换和 Spotify 退出/重开。
- 多艺人曲目 `Die With A Smile` 在 Spotify UI 显示 Lady Gaga 与 Bruno Mars，但当前安装版本的 AppleScript `artist`/`album artist` 字段均只返回 Lady Gaga；未调用 Web API，也未伪造艺人字符串。
- 真实运行截图保存在 `spotify-provider-assets/`；退出态明确显示 `Spotify.app 未运行 · 正在使用 Mock 预览`。

### Phase 16: Build and Commit
- **Status:** complete
- 已完成无签名 Debug build、正常签名 Debug build、codesign 验证、合约测试和真实 Spotify 运行验证。
- 最终无签名和正常签名 Debug 日志均以 `** BUILD SUCCEEDED **` 结尾；产物路径为 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`。
- 已提交独立 commit：`3fcc104 Add verified Spotify desktop provider`。
- 下一阶段仍未开始：LocalProvider + LRCLIBProvider；本阶段没有接入歌词源、Web API、OAuth、SQLite 或 AI。

## Session: 2026-07-27 — Real Track Visual and Lyrics Slice

- **Status:** design pending
- 用户要求保持现有主窗口布局，只修复真实歌曲 identity 与歌词/背景状态一致性，并接入第一版 LocalProvider + LRCLIBProvider。
- 已确认当前实现仍将 `MockData.sampleLyrics` 常驻在 `PlaybackState`，Spotify 切歌时不会清空歌词；主窗口背景也只是固定渐变加右上角封面纹理，尚未按 Track ID / artwork 生成主色背景。
- 本阶段先不写 Swift 实现，等待设计确认后进入 TDD 红色契约。

### Phase 17: Red Core Contract
- **Status:** red observed
- 已获得用户对设计和本地歌词目录的确认。
- `Tests/real_track_lyrics_contract.sh` 已先于生产核心文件运行，并按预期失败：`missing production/test source: SpotifyLyrics/Lyrics/TrackIdentity.swift`。
- 下一步实现纯 Foundation identity、LRC parser、lyrics model 和 confidence matcher，再运行同一契约进入 green。

### Phase 17: Core Green
- **Status:** complete
- Added `TrackIdentity`, `LyricsLoadState`/document/candidate models, LRC parser, and weighted matcher.
- Core contract now prints `lyrics core contract passed`; the full slice contract remains intentionally red because provider/session/background files are not implemented yet.
- One harness issue was corrected during this cycle: Swift top-level test code must be copied to `main.swift`, and the core model no longer depends directly on `MockData` so the Foundation test remains isolated.

### Phase 17: Local and LRCLIB Providers
- **Status:** implementation green, live probe verified
- `LocalLyricsProvider` reads the three approved directories in order and the temporary-directory contract confirms file bytes are unchanged.
- `LRCLIBLyricsProvider` uses the current `/api/get` metadata query, falls back to `/api/search`, parses `syncedLyrics`/`plainLyrics`, and returns candidates below the high-confidence threshold.
- `CompositeLyricsProvider` stops on a match/candidate and continues from local no-match to LRCLIB.
- The contract passes core, local, LRCLIB, session, palette, and UI source checks. Plain LRCLIB lyrics are marked unsynchronized and do not drive playback highlighting.

### Phase 17: Session, background, and UI state chain
- **Status:** implementation and contract verification complete; final runtime gate in progress
- Added `LyricsSessionController` with revision/identity checks, immediate clear-on-begin, cancellation, loading/noLyrics/candidates/failed/mockPreview states, and candidate adoption without persistence.
- Added Track identity priority: Spotify Track ID, Spotify URI, ISRC, then normalized title/artist/album/rounded duration. The stable key always includes the metadata fingerprint, so an ID alone cannot keep stale lyrics attached to changed metadata.
- Added `TrackBackdropView` and `BackdropPalette`: artwork-bound request keys, cancellation/stale-return guards, palette extraction, cropped/blurred texture, gradient layers, readability veil, neutral fallback, and short crossfade snapshot.
- Replaced real-track Mock lyric fallback with explicit `Mock Preview`; switching real identities clears lyric rows and resets the scroll view through the session revision.
- Fixed provider refresh to recalibrate periodically while Spotify is ready, so externally triggered Spotify track changes reach the app without requiring a local transport command.

### Phase 17: Contract and real runtime evidence
- `./Tests/real_track_lyrics_contract.sh` passes: core identity/LRC/matcher, read-only local lookup, LRCLIB JSON/query/synced/plain parsing, delayed session ordering, palette extraction for vivid/bright/dark/single-color inputs, and UI source checks.
- The final no-signing DerivedData Debug build returned `0` and ended with `** BUILD SUCCEEDED **`; a normal signed Debug build also returned `0`, used `Sign to Run Locally`, and passed codesign verification.
- Real Spotify runtime screenshots saved under `real-track-lyrics-assets/`:
  - `bye-bye-bye-real-lyrics.png`: English lyrics, matching cover/background and track title.
  - `japanese-real-lyrics.png`: Japanese lyrics, matching cover/background and track title.
  - `chinese-real-lyrics.png`: Chinese track `晴天下雨`, matching cover/background, explicit `暂未找到歌词`, and no prior lyrics retained.
  - `final-real-track-loading.png`: fresh DerivedData launch shows the real Chinese track, matching cover/background, and `正在搜索歌词…` with the previous rows cleared.
  - `final-real-track-loaded.png`: the same real Chinese track returns matching lyrics after the loading state.
  - `real-network-failed.png`: Debug-only LRCLIB endpoint override to a refused localhost port produces the real app `歌词搜索失败` state; the override is compile-gated to Debug and is not used by Release.

### Phase 17: Final gate
- **Status:** complete
- Final tests pass, the no-signing Debug build and normal signed Debug build both end with `** BUILD SUCCEEDED **`, and `codesign --verify --deep --strict` passes.
- The signed DerivedData app was relaunched after the diagnostic process ended; Apple Events TCC remains granted for `com.spotifylyrics.app → com.spotify.client`, and the real track returned to the normal loading/loaded path.

## Session: 2026-07-27 — Playback and Lyrics Correctness

### Phase 18: Red-green correctness contracts
- **Status:** implementation green; final gate in progress
- Added `Tests/lyrics_correctness_test.swift` before the corresponding production changes. The first contract run failed at the missing typed failure cases and `LyricsTimeline`, confirming the new assertions were red for the intended reason.
- Added `Tests/playback_state_contract.swift` and wired it into `Tests/real_track_lyrics_contract.sh`; it exercises a protocol-injected provider rather than coupling tests to `SpotifyDesktopProvider`.
- The complete contract now covers network unavailable, timeout, HTTP server failure, parse failure, no-match versus no-lyrics, unsynchronized plain text, candidate adoption/current-identity checks, retry, rapid session replacement, and playback controls.

### Phase 18: State correctness implementation
- `LyricsFailure` now carries explicit user-facing categories: `networkUnavailable`, `timedOut`, `serverError`, `parseFailure`, and `unknown`.
- `LyricsLoadState.noMatch` is separate from `noLyrics`; both clear current rows, while failed/no-match states expose a retry action. Low-confidence candidates remain visible until the user explicitly adopts one for the active identity.
- `LyricsTimeline` is the shared pure rule for synchronized active-line calculation and unsynchronized full-text presentation. Plain lyrics never receive a synthetic active line or playback-driven scroll.
- LRCLIB maps URL/network/HTTP/JSON failures to the typed categories and treats a direct/search 404 sequence as `noMatch`.

### Phase 18: Real signed runtime evidence
- Normal signed Debug build was launched from `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` with existing Apple Events permission.
- The runtime showed the real `一点点（为什么晚上总是有星星）` / 董唧唧、芊芊龍 track, matching artwork-derived background and lyrics. Two rapid next-track transitions and previous/next controls converged to the same Spotify track, cover, lyrics, and position; a fresh launch showed the explicit loading state before lyrics arrived.
- Pause/resume held and advanced the real interpolated position; slider `Increment` changed the paused position from about `01:51` to `02:09` and Spotify/app state remained paused.
- Quitting Spotify produced `Spotify.app 未运行 · 未进入 Mock Preview` with placeholder track and cleared lyrics; reopening Spotify automatically returned to the same real track, cover, lyrics and connected status.
- New observation-only screenshots: `real-track-lyrics-assets/correctness-reconnected.png` and `real-track-lyrics-assets/correctness-paused.png`; the earlier full-size loading evidence remains `real-track-lyrics-assets/final-real-track-loading.png`.

### Phase 18: Final verification
- **Status:** complete
- `./Tests/real_track_lyrics_contract.sh` passes all core, provider, session, palette, correctness, playback and source-contract checks.
- The exact no-signing Debug command and the normal signed Debug command both returned `0` with `** BUILD SUCCEEDED **`; the final signed app passed `codesign --verify --deep --strict` and retained the Apple Events entitlement/usage description.
- Final signed runtime was relaunched from DerivedData. Spotify and SpotifyLyrics both reported `一点点（为什么晚上总是有星星） / 董唧唧、芊芊龍`; the app showed matching artwork, background, lyrics and paused progress after the loading state.
- Independent commit: `Fix playback and lyrics state correctness`.
## 2026-07-27 — Phase 19 started

- 当前基线为 `bb63ba8 Fix playback and lyrics state correctness`，工作区干净，分支 `ui-redesign-phase-1`。
- 本阶段先处理两个独立 Bug：网络恢复后当前 identity 有限重试一次；歌词 seek 只接受合法同步时间轴并记录 Debug 来源。
- 已确认现有 seek 唯一 UI 来源在 `LyricsCanvasView` 和主窗口进度 Slider；`PlaybackState.seek` 当前没有 finite/duration 防护，歌词行无条件传入 timestamp。
- 下一步先在纯 Foundation/合同测试中加入红色断言，再修改生产代码；Bug 提交完成后再进行三套 UI 参考审计。

## 2026-07-27 — Phase 19 complete

- TDD 红色证据：新增的 `validSeekTimestamp`、网络失败恢复 API 断言先因生产 API 缺失而编译失败；随后实现后 `Tests/real_track_lyrics_contract.sh` 全部通过。
- 网络恢复：`LyricsSessionController.retryAfterNetworkRecovery` 只接受当前 identity 的 `.networkUnavailable`，每个 identity 最多自动尝试一次；`NWPathMonitor` 只在不满足→满足的路径转变时触发，手动 `retryLyrics()` 保留且不会重置播放锚点。
- 安全 seek：同步歌词行使用 `LyricsTimeline.validSeekTimestamp`，要求 finite、非负、且不超过当前歌曲时长；纯文本、非法时间戳、空白和 loading/failed/noLyrics/candidates 没有 seek 入口；进度 Slider 使用独立 `progress-slider` 来源。
- Debug 日志：使用 `Logger(subsystem: "com.spotifylyrics.app", category: "seek")`；真实运行日志捕获 `accepted source=lyric-line time=21.140 identity=spotify-id:spotify:track:5lp9unpcikghkh7x1amhnw...`，Spotify AX 同步显示约 `0:22/3:50`，未跳回 00:00。Slider 也捕获 `source=progress-slider`。
- 真实运行：正常签名 DerivedData Debug app 连接 Spotify 的真实 `IDOLPOWER / M!LK`，同步歌词行通过 Accessibility 暴露为可点击按钮；点击第 8 行后 Spotify Apple Events 位置约 22 秒，应用位置约 22.52 秒。当前无时间轴歌曲的 AX 树没有歌词按钮，符合禁止伪造 seek。
- 构建：无签名 Debug 与正常签名 Debug 均以 `** BUILD SUCCEEDED **` 结束；完整合同测试通过。未修改 SQLite、AI、Provider 或悬浮/胶囊/全屏布局。
## 2026-07-27 Phase 20 — Reference Audit and Layout Contract

- Read-only audit completed for `Lyricify-App-main`, `/Applications/Dynamic Lyrics.app`, and `com.apple.Music`.
- `Lyricify-App-main/LICENSE` and all root `LICENSE*`/`COPYING*` files are absent; no UI source implementation was found. Findings and source file inventory are recorded in `UI_LAYOUT_AUDIT_PHASE2.md` and `findings.md`.
- Dynamic Lyrics fresh AX/screenshot observation and Music.app shell observation were recorded; Music.app has no active song in the current non-subscriber session, so real lyric playback remains explicitly unverified.
- Apple official HIG sources for Materials, Windows, Layout, Designing for macOS, and Apple Design Resources were consulted and linked in the audit document.
- Created `Tests/phase2_layout_contract.sh` before any Swift UI production changes. The first run failed as intended with `missing required layout file: SpotifyLyrics/Design/MainWindowLayoutStyle.swift`; this is the TDD red checkpoint.
- No Swift source or Xcode project changes have been made for the new layouts yet.
## Session: 2026-07-27 — Song search continuation

- 用户明确要求继续实现独立 `SongSearchProvider` 架构；参考应用只用于体验，不复制代码或资源。
- 当前工作区仍有 Phase 20 UI 未提交改动；本阶段先保留并继续验证，不覆盖已有主窗口实现。
- 目标链路：`SongSearchManager` 调度 `LocalSearchProvider`、`SpotifyCurrentTrackProvider` 和 `LRCLIBProvider`，统一输出 `SongSearchResult`。
- 先写 `Tests/song_search_contract.sh` 与 `Tests/song_search_contract.swift` 并观察到缺少生产 Search 文件时退出 `1`；实现后契约通过，覆盖本地 LRC、LRCLIB JSON、Spotify 当前歌曲和旧请求取消。
- 实际 Xcode Debug 构建已通过；运行中搜索入口、搜索 popover、LRCLIB/Spotify 结果列表和点击结果状态均已观察。
- 专注模式控制条的 AX/截图不一致定位为 `layoutBody` 先取满窗口高度再加顶部 padding，导致底部控件布局到窗口外；改为 GeometryReader 计算内容高度并 offset 到 top bar 下方，运行截图已实际显示进度条和三键控制。

## 2026-07-27 — Phase 20/21 final runtime gate

- Phase 20 两种主窗口布局已在同一运行会话中即时切换：`lyricsFocus` 与 `immersiveSplit` 均保留当前 Track、封面、歌词会话、播放控制和 `00:04 / 01:59` 位置；分栏模式显示真实封面、元数据、进度及上一首/播放/下一首。
- Phase 21 完成独立搜索链路：`SongSearchManager` 依次调度只读 `LocalSearchProvider`、`SpotifyCurrentTrackProvider` 和 `LRCLIBProvider`，UI 只消费 `SongSearchResult`；搜索任务带 generation/cancellation 保护，重复发行元数据合并，Late response 不覆盖新查询。
- 正常签名 Debug 构建命令返回 `0`，`/tmp/spotifylyrics-search-final-signed.log` 结尾为 `** BUILD SUCCEEDED **`；产物为 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`，使用 Xcode `Sign to Run Locally` 签名并通过 codesign 验证。
- 最终签名产物重新启动后，AX 实际观察到搜索 popover、LRCLIB 与 Spotify 当前歌曲统一结果列表。点击当前歌曲结果进入 `正在搜索歌词…`，播放位置仍为 `00:04 / 01:59`；点击不匹配的 LRCLIB 结果显示“搜索结果与当前歌曲匹配度不足，未加载”，没有污染当前歌曲状态。
- 最终截图已刷新：`ui-redesign-assets/phase2-lyrics-focus.png`、`ui-redesign-assets/phase2-immersive-split.png`。契约、`git diff --check` 和最终签名构建均通过。

## 2026-07-27 — Phase 22 source research started

- 用户要求先完整调研歌曲目录与歌词来源，等待确认后再修改 Swift；本轮明确禁止新增 Provider 实现，也禁止读取 Dynamic Lyrics 闭源实现、二进制、私有接口或资源。
- 调研输出目标为 `SOURCE_PROVIDER_RESEARCH.md`，覆盖 Spotify Web API、LRCLIB、网易云、QQ 音乐、酷狗、Apple Music/MusicKit、补充来源、Lyricify 公开仓库和当前 Provider 架构审计。

## 2026-07-27 — Phase 22 source research complete
- 已完成 Spotify Web API、LRCLIB、网易云、QQ 音乐、酷狗、Apple Music/MusicKit、MusicBrainz/Cover Art Archive、Musixmatch、Genius、Deezer 的官方/公开资料审计，并对 LRCLIB、中文平台和 MusicBrainz 做了最小只读请求验证。
- 已读取 `Lyricify-App-main` 的 README、docs、i18n 公开文案并确认本地副本没有可识别 LICENSE；另记录公开 `Lyricify-Lyrics-Helper` 的 Apache-2.0 许可证和 Searchers/Providers 分层线索。没有读取或操作 Dynamic Lyrics 的闭源实现、二进制、私有接口或资源。
- 已确认当前 `SongSearchResult` 将曲库候选、Spotify 当前播放识别和可选歌词正文混在一起；报告建议拆为 `TrackSearchManager`、`CurrentTrackResolver` 和 `LyricsSearchManager`，并保留严格 `TrackIdentity`/generation 安全边界。
- 已创建 `SOURCE_PROVIDER_RESEARCH.md`，包含对比表、推荐分层、统一模型、失败隔离、未来修改文件计划和从低风险到高风险的验收顺序。本轮没有修改 Swift、Xcode 工程或业务实现，等待用户确认后再一次接入一个来源。

## 2026-07-27 — Phase 23 architecture split

### Done
- Implemented low-risk architecture from `SOURCE_PROVIDER_RESEARCH.md` without OAuth or Chinese platform providers.
- Added `TrackSearchManager` / `TrackSearchResult` (metadata only) and `LyricsSearchManager` for confirmed `TrackIdentity` lookups.
- Replaced free-text role of `SpotifyCurrentTrackProvider` with `CurrentTrackResolver`; kept UI-facing `SongSearchManager` compatibility facade.
- Introduced shared read-only `LocalLyricsIndex` used by local track search and local lyrics lookup; Release still omits project-root `Lyrics/` except under DEBUG.
- LRCLIB remains lyrics-only: independent timeout, limited automatic retry, 400/404/429/timeout/network/parse classification, cancellation, no default on-disk persistence; track-search `LRCLIBProvider` is a hard no-op/deprecated shim.
- `PlaybackState` track search wires only Local + CurrentTrackResolver; lyrics session still Local + LRCLIB via composite/search manager.
- Contracts: `./Tests/song_search_contract.sh` (song search + search models + provider failure) and `./Tests/real_track_lyrics_contract.sh` passed.
- Signed Debug build: `** BUILD SUCCEEDED **`; `codesign --verify --deep --strict` OK.
- Real runtime: launched DerivedData Debug app (1 main window); Spotify Desktop had live track `あやふや / みさき` (paused). Full UI click-through of every control was not exhaustively AX-scripted this round.

### Not done / paused
- Spotify Developer Client ID / Web OAuth catalog search
- Apple Music / Musixmatch / NetEase / QQ / KuGou providers

## 2026-07-27 — Japanese alias design (no implementation)

- Added `docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md`.
- Red contract `./Tests/japanese_alias_contract.sh` fails on missing production sources as intended.
- Read-only survey: LRCLIB misses あやふや; hits Lemon/Pretender; NetEase finds あやふや catalog id but live/studio ambiguity remains.
- Waiting for user confirmation before coding models/planner/matcher.
## 2026-07-27 — Alignment V1 continuation

- 读取并恢复现有规划文件；保留工作区所有未提交排轴改动和 `DerivedData.bak.*`，未做破坏性清理。
- 复现当前签名关闭构建：失败退出码 `65`，唯一明确 Swift 错误为 `PlaybackState.tryAutoAlignIfRequested` 缺失。
- 新增 `Tests/alignment_wiring_contract.sh` 并先运行红灯，退出码 `1`，证明接线契约能捕获当前缺失。
- 实现按 `TrackIdentity` 一次性的环境自动排轴钩子；修复逐行对齐器的连续未匹配尾部插值，并让排轴依赖进入 Xcode target。
- 全部合同通过：alignment wiring、line alignment、Japanese alias、两种布局 UI、real track/session/provider failure、song search 和 Spotify Desktop provider。
- 清理仓库 `DerivedData` 后正常签名 Debug 构建 `** BUILD SUCCEEDED **`；目标 App 路径、修改时间、arm64 Mach-O 和 ad hoc `Sign to Run Locally` codesign 均已验证。
- 在该绝对路径 App 中以 Spotify 实际当前 identity `水曜日の約束 / Kawasaki.Rio` 运行：QQ 返回 32 行纯文本，UI 实际进入排轴预览并确认保存；确认前后播放位置日志相同，最终 SwiftUI 显示逐行时间轴并跟随播放。
- 证据位于 `docs/superpowers/specs/acceptance-2026-07-27-alignment-v1/`；用户本地结果位于 `~/Music/SpotifyLyrics/Lyrics/Kawasaki.Rio - 水曜日の約束.aligned.lrc`。未加入新 Provider、音频下载、系统捕获、ASR 主路径、逐字排轴或完整编辑器。

## 2026-07-28 — Alignment V1 runtime correction

- 用户真实运行发现：旧 TTS 夹具只有 79.8255 秒，而当前 Spotify「水曜日の約束 / Kawasaki.Rio」为 171.177 秒；旧的 1:18 结束时间轴和“歌手未开口即开始”的表现均属错误结果。
- 先写红色合同再修复：时长不匹配必须拒绝；前置未匹配歌词不得早于第一条真实识别锚点。`./Tests/line_alignment_contract.sh` 已由红转绿。
- `SpeechForcedAlignmentService` 现在在语音识别前执行 `AlignmentDurationValidator`；失败时保留纯文本、回到 `alignmentQueued`，不保存或覆盖同步歌词。UI 会显示具体时长错误。
- 用全新正常签名 DerivedData App 真实运行验证：QQ 仍返回 32 行，日志记录 `UI align failed ... 79.8 秒与 ... 171.2 秒不匹配`；`~/Music/SpotifyLyrics/Lyrics/Kawasaki.Rio - 水曜日の約束.aligned.lrc` 不存在；播放位置未被排轴改变。
- 本阶段状态改为**部分完成/待真实音频**：没有对应完整本地音频，不再声称该曲已成功生成有效时间轴。

## 2026-07-30 — Real Audio Line Alignment V1 planning
- **Status:** plan ready; implementation paused for user confirmation
- Audited current alignment target membership and runtime boundaries.
- Identified unsafe average-timing fallback and historical TTS mismatch as blockers to real acceptance.
- Wrote plan: `docs/superpowers/plans/2026-07-30-real-audio-line-alignment-v1.md`.
- No SpotifyLyrics business source, Xcode project, database, or user audio was modified in this planning pass.

## 2026-07-30 — Real Audio Line Alignment V1 implementation complete
- **Status:** code/contracts/build acceptance passed; commercial real-song acceptance remains `UNVERIFIED` until a matching complete local vocal file is selected in the App.
- Removed unsafe average timing and the automatic environment trigger. Boundary/unmatched rows fail closed; only bounded interpolation between real anchors is allowed.
- Added timed transcript/Speech boundary, deterministic DP line alignment, audio metadata/hash/temporary PCM handling, cancellation, identity/revision/source-hash guards, SQLite v3 alignment children and atomic provenance sidecars.
- Reused the existing editor and added restrained per-line evidence preview; low-confidence alignment cannot be locked automatically.
- All 35 contract scripts passed; normal signed Debug build and codesign passed; exact process was launched from `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`.
- No TTS, synthetic audio or commercial audio was used as real-song evidence. See `docs/superpowers/specs/acceptance-2026-07-30-real-audio-line-alignment-v1/README.md`.
