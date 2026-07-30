# Findings & Decisions

## Requirements
- 为当前 SpotifyLyrics 工作区规划 Git 管理方式。
- `/Users/apple/backup/sptifylyrics/Lyricify-App-main` 是他人项目，后续仅用于参考。
- 当前阶段不要求修改参考项目或开始功能移植。

## Research Findings
- 当前工作区：`/Users/apple/backup/sptifylyrics`。
- 当前 Git 分支：`main`。
- 当前已有提交：
  - `5461f44 Migrate project structure to SpotifyLyrics.xcodeproj`
  - `77956d1 Phase 1: Implement macOS SwiftUI independent Spotify Lyrics App with Mock lyrics and 4 display modes`
- 当前没有配置远程仓库（`git remote -v` 无输出）。
- 已跟踪的当前项目文件主要是 `SpotifyLyrics/`、`SpotifyLyrics.xcodeproj/` 和 `generate_xcodeproj.py`。
- `.gitignore` 当前仅忽略 `build/` 和 `.DS_Store`。
- `Lyricify-App-main/` 位于当前仓库内，整个目录目前显示为未跟踪：`?? Lyricify-App-main/`。
- `Lyricify-App-main/` 内没有独立 `.git` 目录；从该路径运行 Git 命令时会继承父仓库上下文，因此不能视为独立 Git 仓库。
- 参考项目包含 Lyricify 3/4/Mobile/Lite 的国际化、文档、主题、图片和其他资源，适合作为后续 UI、国际化和歌词产品设计参考。

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| 现有 `main` 作为当前项目基线 | 已有可追溯提交，不需要重新初始化仓库 |
| 参考项目与当前产品源码分开 | 避免把他人项目的全部历史/资源误纳入当前产品提交 |
| 后续功能工作优先使用独立分支 | 便于审查、回滚和保留 `main` 的稳定基线 |
| `Lyricify-App-main/` 加入 `.gitignore` | 用户确认继续保留在仓库内，同时避免误提交他人项目 |
| 后续功能工作优先使用 `codex/<topic>` 分支 | 保护 `main` 基线，便于审查、回滚和分阶段提交 |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| 参考目录名称与用户给出的参考路径相同，但实际位于当前仓库内 | 以实际路径和 Git 状态为准，标记为“仓库内只读参考目录” |

## Phase 25 Findings — 2026-07-27
- 当前工作区分支为 `ui-redesign-phase-1`，已存在未提交的 Alignment V1 源码和验收 fixture；未覆盖这些用户改动。
- 复现构建失败：`PlaybackState.swift:74` 调用了不存在的 `tryAutoAlignIfRequested()`。
- 该错误发生在 Swift 编译阶段，因此此前 DerivedData App 不包含本轮可运行的自动排轴接线。
- 计划的环境验收入口为 `SPOTIFYLYRICS_ALIGN_AUDIO` + `SPOTIFYLYRICS_AUTO_ALIGN=1`；自动触发必须按 TrackIdentity 去重，避免状态发布造成重复排轴。

## Resources
- 当前项目：`/Users/apple/backup/sptifylyrics`
- 参考项目：`/Users/apple/backup/sptifylyrics/Lyricify-App-main`
- 当前 Xcode 工程：`/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj`
- 当前源码目录：`/Users/apple/backup/sptifylyrics/SpotifyLyrics`

## Visual/Browser Findings
- 2026-07-26 实际启动 `build/SpotifyLyrics.app` 后，主窗口可见，标题为 SpotifyLyrics。
- 主窗口实际显示硬编码的 YOASOBI《夜に駆ける》、6 行示例歌词，以及“悬浮歌词窗口 / 顶部胶囊播放器 / 全屏歌词模式”三个按钮。
- 辅助功能树确认原文、翻译、罗马音、假名开关和播放按钮存在。
- 点击“悬浮歌词窗口”后，主窗口复选样式切换为已启用，证明按钮触发了状态变化；但当前 Computer Use 截图未显示独立悬浮窗，需进一步核实窗口是否实际创建/可见。
- 第一次尝试点击“顶部胶囊播放器”后，截图中该项仍未勾选，且焦点仍报告在悬浮歌词按钮；本次点击不能作为胶囊功能有效的证据，需换一种交互顺序重试。
- 坐标点击尝试误触了“假名”开关，说明 Computer Use 截图坐标与应用窗口坐标存在偏移；后续停止使用坐标点击，改用辅助功能索引和键盘焦点。
- 通过键盘焦点（Tab + Space）重新触发“顶部胶囊播放器”后，主窗口中该项成功显示为已启用；悬浮与胶囊两个状态均可切换。
- SpotifyLyrics 的应用级截图仍只捕获标准主窗口，未包含无边框辅助窗口；因此“状态已启用”与“辅助窗真实可见”必须分开记录。
- 切换到 Finder 后的截图同样只捕获 Finder 自身窗口，不能用来证明或否定其他应用的无边框窗口；改用只读 WindowServer 查询验证窗口数量、尺寸、层级和 on-screen 状态。
- WindowServer 真实确认主窗口、悬浮歌词和顶部胶囊都处于 on-screen：
  - 主窗口：900×552，layer 0。
  - 悬浮歌词：600×180，layer 3。
  - 顶部胶囊：380×46，layer 25。
- 辅助窗口位于另一块显示器坐标区域，因此 SpotifyLyrics 主窗口裁剪截图中看不到它们；这解释了先前“已启用但截图不可见”的现象。
- 通过键盘焦点触发“全屏歌词模式”后，主窗口中的全屏项显示为已启用；下一步用 WindowServer 验证其实际窗口尺寸和层级。
- WindowServer 确认全屏歌词窗口为 2560×1440、layer 8、on-screen；它是覆盖整个主屏的无边框窗口，并非 macOS 原生 full-screen Space 切换。
- 再次触发全屏按钮后，2560×1440 layer 8 窗口从 on-screen 列表消失，证明关闭动作有效。
- 第三次触发全屏按钮后，2560×1440 layer 8 窗口重新出现，证明全屏歌词窗口可关闭并重新打开。
- 顶部胶囊窗口关闭后，380×46 layer 25 窗口从 WindowServer on-screen 列表消失；重新打开后再次出现。胶囊关闭/重开已真实验证。
- 悬浮歌词窗口关闭后，600×180 layer 3 窗口从 WindowServer on-screen 列表消失；重新打开后再次出现。悬浮窗关闭/重开已真实验证。
- 在关闭三个辅助窗口后，后续 `swift -e` 查询突然被“尚未同意 Xcode license”阻止。按用户要求未运行 sudo，也未接受许可；此前成功采集的 WindowServer 证据仍有效。
- 主窗口截图确认三个辅助窗口状态都已恢复为关闭。
- 点击播放按钮后，按钮文本变为“暂停”，进度从 0.2 秒继续推进到约 3.8 秒，证明播放按钮和本地 Timer 模拟逻辑真实可用。
- 该播放只是 `PlaybackState` 内部计时器驱动的 MockData 演示，不是 Spotify 播放状态集成。
- 暂停点击期间，持续变化的计时器让 Computer Use 多次报告界面被改变；最终状态显示按钮恢复为“播放”、时间停在约 27.6 秒，说明暂停动作实际生效。
- 点击标题栏关闭按钮未形成可靠状态变化；改用标准 `Cmd+W` 后，Computer Use 返回 `noWindowsAvailable`，证明主窗口确实关闭。
- 主窗口关闭后进程仍存活（PID 39643，Bundle ID `com.spotifylyrics.app`）。
- 以 Bundle ID 重新激活应用后，主窗口重新出现，且模拟播放时间仍保持约 27.6 秒；主窗口关闭/重开已真实验证。

## 2026-07-26 Audit Findings

### Scope
- 唯一允许修改的正式项目：`/Users/apple/backup/sptifylyrics`。
- `/Applications/Dynamic Lyrics.app` 仅作为黑盒 UI/交互参考。
- Lyricify 仓库仅作为公开文档、截图、歌词格式和功能说明参考。
- 本轮未修改 Swift 源码、Xcode 工程、参考目录或应用包。

### Git and Xcode
- `pwd`：`/Users/apple/backup/sptifylyrics`。
- Git 只有两个提交；当前已有 `.gitignore` 修改和三个未跟踪规划文件。
- 系统没有 `/Applications/Xcode*.app`；`xcode-select -p` 为 `/Library/Developer/CommandLineTools`。
- `/usr/bin/xcodebuild` 存在，但执行时明确报错：当前开发者目录只是 Command Line Tools。
- 指定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 时，`xcodebuild -list` 和真实 build 都因路径不存在而失败。

### Xcode Project
- `project.pbxproj` 通过 `plutil -lint`。
- 工程声明一个 `SpotifyLyrics` app Target、Debug/Release 配置、Bundle ID `com.spotifylyrics.app`、macOS 14.0、Swift 5.0。
- 6 个现有 Swift 文件均有 PBXFileReference、PBXBuildFile 和 Sources Build Phase 项目。
- 工程目录没有共享 Scheme 文件；由于完整 Xcode 缺失，自动 Scheme 是否可被 `xcodebuild` 正确识别仍未验证。

### Existing App Bundle
- `build/SpotifyLyrics.app` 是手工产物：初始提交中的 `build.sh` 直接调用 `swiftc`，随后手工写 Info.plist 并拼装 `.app`。
- 迁移提交删除了 `build.sh` 和 Package.swift，但保留了被 `.gitignore` 忽略的既有 build 产物。
- 可执行文件是 thin arm64 Mach-O；Info.plist 语法有效，Bundle ID 为 `com.spotifylyrics.app`。
- 签名为 ad-hoc/linker-signed，Info.plist 未绑定，资源未密封。
- 二进制符号包含 Main/Floating/Capsule/FullScreen 四种 View、三个窗口切换方法和 MockData，说明当前源码曾被编入该手工产物。

### Static Feature Audit
- 6 个 Swift 文件全部同时出现在 PBXFileReference、PBXBuildFile 和 Sources Build Phase 中，没有发现“文件存在但未加入 Target”的情况。
- 没有共享 `.xcscheme` 文件；完整 Xcode 缺失，因此自动 Scheme 仍未通过 `xcodebuild -list` 验证。
- 所有可见按钮都有 action：三个辅助窗口切换、主窗口播放、胶囊播放、全屏关闭；没有发现纯外观空按钮。
- `currentMode` 只声明未使用；`DisplayPreferences.opacity` 和 `alwaysOnTop` 没有用于窗口/UI 行为；`isrc` 和 `spotifyId` 只存在于模型/MockData。
- 没有 Spotify API、Provider、URLSession、SQLite/数据库、AI 翻译、LRC/TTML 导入导出或歌词编辑实现。
- 现有全部播放状态和歌词内容来自 `MockData`。

### Reference Availability
- `/Applications/Dynamic Lyrics.app` 存在；只读取了 Info.plist，没有修改、签名、Patch 或提取资源。
- 当前仍是仓库内的 `Lyricify-App-main/` 参考副本；附件建议的 `References/Lyricify-App` 和 `References/Lyricify-Lyrics-Helper` 尚未建立。
- 本轮按“只审计”要求没有创建/克隆参考目录。

### Spaces Behavior
- 尝试用 `Ctrl+Right` 切换到相邻桌面，并在前后对比悬浮窗/胶囊窗的 WindowServer 状态。
- 当前 Spaces 配置显示活跃显示器各只有一个当前 Space，没有可切换的第二桌面；因此该按键没有形成可验证的桌面切换。
- 悬浮窗和胶囊窗代码设置了 `.canJoinAllSpaces` 与 `.fullScreenAuxiliary`，但“跨多个桌面”和“覆盖其他应用原生全屏 Space”本轮只能归类为代码存在、未真实验证。

### Environment Regression During Audit
- 审计后段不仅 `swift -e`，连 `/usr/bin/git`/`/usr/bin/python3` 也开始被 Xcode license 提示阻断。
- 未运行 `sudo xcodebuild -license`，未修改系统许可状态；最终报告将使用已在阻断前采集的 Git 证据，并明确这一限制。
- 随后发现外部环境在审计期间发生变化：`/Applications/Xcode.app` 于约 21:46 出现，`xcode-select` 也指向该路径；这不是本次 Codex 操作造成的。
- 新出现的是 Xcode 26.6（Build 17F113），但许可尚未同意。
- 使用明确的 `DEVELOPER_DIR` 后，`xcodebuild -version` 成功；`xcodebuild -list` 和真实 build 仍被许可协议阻断，且未创建 `DerivedData`。
- Git 最终状态改用 Codex runtime 的 fallback git 读取，避免受 `/usr/bin/git` 的无效开发者目录/许可状态影响。
- 直接调用 Xcode toolchain 的 Swift，并显式指定 macOS SDK 后，可继续进行只读 WindowServer 查询而不接受许可；第三次尝试成功。
- WindowServer `optionAll` 显示已关闭的辅助窗口对象仍被 `WindowManager` 保留，但不带 `kCGWindowIsOnscreen=1`；这与代码通过 `orderOut` 隐藏而非销毁窗口一致。

## 2026-07-27 Spotify Desktop Provider Findings

### Installed application and scripting dictionary
- `/Applications/Spotify.app` exists; `CFBundleShortVersionString` and `CFBundleVersion` are both `1.2.94.583`; bundle identifier is `com.spotify.client`.
- The real dictionary was read with `sdef /Applications/Spotify.app` before implementing the provider. It exposes:
  - application properties: `current track`, `player state`, `player position`;
  - track properties: `name`, `artist`, `album`, `duration`, `artwork url`, `spotify url`, `id`, and `album artist`;
  - commands: `play`, `pause`, `playpause`, `previous track`, and `next track`.
- The dictionary declares Apple Events access groups `com.spotify.playback` and `com.spotify.library`; `artwork` is deprecated and `artwork url` is the supported cover field.
- Player-state enumeration values in the installed dictionary are `stopped`, `playing`, and `paused`.

### Direct Apple Events probe
- A direct `osascript` probe using only the properties above succeeded against the running Spotify.app without assuming undocumented fields.
- Observed live snapshot: `playing`, position about `148.444` seconds, track `IDOLPOWER`, artist `M!LK`, album `IDOLPOWER`, duration `230453` (Spotify dictionary duration units are milliseconds), artwork URL `https://i.scdn.co/image/ab67616d0000b2730147cecbbbc8b8237ed95dc9`, Spotify URI `spotify:track:5LP9UNPCIkgHkh7x1AMHnw`, and the same track identifier from `id`.
- The first probe launched Spotify because it was not running before the probe; the Spotify process was present afterward. Permission behavior for the signed SpotifyLyrics app still requires a normal signed Debug build and an in-app first-run verification.

### Provider design decisions
- Use a `PlaybackProvider` protocol and keep `PlaybackState` dependent on that protocol, never on `SpotifyDesktopProvider` directly.
- Use Apple Events through `NSAppleScript`/`NSAppleEventDescriptor`, with scripts derived from the installed dictionary. This avoids depending on generated ScriptingBridge headers while retaining the real Apple Events contract.
- Map Spotify duration milliseconds to `TimeInterval` seconds at the provider boundary.
- Keep a local interpolation anchor (`providerPosition`, `providerSyncDate`, `isPlaying`) and refresh Spotify periodically; do not poll Apple Events at every UI tick.
- Use a cached asynchronous artwork loader for `artwork url`; the existing generated Mock artwork remains the fallback when Spotify cover loading fails.
- Preserve the current Mock lyrics array because this stage explicitly stops before LocalProvider/LRCLIB lyrics work.

### 2026-07-27 Verified Spotify Desktop runtime
- The normal signed Debug build was created without `CODE_SIGNING_ALLOWED=NO`. Xcode used the local `Sign to Run Locally` identity; `codesign --verify --deep --strict` passed, and the app contains `com.apple.security.automation.apple-events` plus `get-task-allow` in its entitlements.
- The generated Info.plist contains `NSAppleEventsUsageDescription`: `SpotifyLyrics 需要控制 Spotify 以读取当前歌曲、播放状态和封面。`.
- A read-only TCC query shows `kTCCServiceAppleEvents | com.spotifylyrics.app | auth_value=2 | auth_reason=3 | com.spotify.client`; its `last_modified` value converted to `2026-07-27 14:20:04 +0800`, during the first signed Debug launch. The first in-app state transitioned from the fallback/connecting state to `Spotify Desktop 已连接`, and subsequent reads/commands succeeded. No permission modal remained on screen when the state was captured; the timestamped TCC grant plus successful in-app Apple Events read are the reproducible permission evidence, and TCC was not reset.
- DerivedData app runtime connected to real Spotify and displayed asynchronously loaded covers. The connected status bar was visible in `spotify-provider-assets/status-fixed-connected.png`; the cover for `Die With A Smile` was loaded from Spotify's `artwork url`.
- Verified real songs through the app: `Missing` / `BE:FIRST` / `Missing` (172s), `夢中` / `BE:FIRST` / `夢中` (189s), `BE:FIRST ALL DAY` / `BE:FIRST` / `BE:FIRST ALL DAY` (155s), `Doesn't Really Matter (Remix)` / `Janet Jackson` / `Doesn't Really Matter (Remix)` (175s), `Why, Why` / `BE:FIRST` / `Missing` (187s), `Rondo` / `BE:FIRST` / `BE:FIRST ALL DAY` (200s), `Toyfriend` / `SB19` / `Wakas At Simula` (201s), and `Die With A Smile` / AppleScript artist `Lady Gaga` / `Die With A Smile` (251s). Each was a real Spotify track and produced a new cover/track snapshot; evidence screenshots are in `spotify-provider-assets/`.
- The Spotify UI shows `Die With A Smile` with `Lady Gaga, Bruno Mars`, but the installed AppleScript dictionary returns only `artist = Lady Gaga` and `album artist = Lady Gaga`. The provider keeps the exact value exposed by the approved desktop dictionary and does not invent secondary artists or call the Web API.
- Play/pause was verified with real Spotify state: time advanced by local interpolation while playing, then stopped at the calibrated position while paused, without the prior `missing value` false-error. Seek was verified by clicking the app slider around 75s; the app and Spotify converged near `74.94s`. Previous/next commands were issued through the provider, with next-track switching confirmed after Spotify's asynchronous update.
- Spotify was quit with Apple Events: the app displayed `Spotify.app 未运行 · 正在使用 Mock 预览`, disabled previous/next, and preserved the generated Mock cover (`spotify-provider-assets/spotify-quit-fixed.png`). Spotify was reopened, automatic polling reconnected, and the app returned to the real `Die With A Smile` track (`spotify-provider-assets/spotify-reopen-fixed.png`).
- Runtime screenshots contain only observations of the running SpotifyLyrics window. No Spotify.app resources, binaries, artwork files, or extracted bundle assets were copied into the repository.

## 2026-07-26 Verified Xcode Build Baseline

### Environment and Scheme
- `xcode-select -p`：`/Applications/Xcode.app/Contents/Developer`。
- `xcodebuild -version`：Xcode 26.6 / Build 17F113。
- `xcodebuild -list -project SpotifyLyrics.xcodeproj` 成功识别 Target `SpotifyLyrics`、Debug/Release 配置和 Scheme `SpotifyLyrics`。

### Build Evidence
- 指定的无签名 Debug `xcodebuild` 返回退出码 0，并输出 `** BUILD SUCCEEDED **`。
- Xcode 标准产物：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`。
- 旧手工产物：`/Users/apple/backup/sptifylyrics/build/SpotifyLyrics.app`；两者路径不同，旧产物没有被当作本轮构建结果。
- `DerivedData/` 和 `build/` 已加入 `.gitignore`，不应提交构建产物。

### New Product Runtime Evidence
- Computer Use 实际启动 DerivedData `.app`，主窗口显示标题、Mock 歌曲和歌词。
- WindowServer 实际确认 DerivedData `.app` 的主窗口（900×621/layer 0）、悬浮歌词（600×180/layer 3）、顶部胶囊（380×46/layer 25）和全屏覆盖歌词（2560×1440/layer 8）。
- 悬浮歌词、顶部胶囊和全屏覆盖歌词均完成打开→关闭→重新打开验证；主窗口完成 `Cmd+W` 关闭→重新启动验证。
- 这只是已有 Mock UI 的 Xcode 产物基线，不代表 Spotify、歌词 Provider、SQLite、AI 或自动排轴已实现。

## 2026-07-26 UI Reference Audit — Initial Public Reference Findings

### Branch and boundaries
- 当前分支已创建并切换为 `ui-reference-audit`，基点为 `e24fbb35ea8247f39d52e3a0772f34c4e8633454`。
- `Dynamic Lyrics.app` 只读黑盒；不修改、签名、Patch、反编译或提取专有素材。
- `Lyricify-App-main/` 只读 README、docs、images 和公开说明；不复制源码、品牌名称、图标或图片到正式产品。

### Lyricify public repository inventory
- README 明确将 Lyricify 4 描述为 Spotify 的自动滚动歌词和附加功能，并列出 Dynamic Lyrics Island、Magic Strip、动态专辑封面等产品概念。
- README 公开展示了歌词显示、Dynamic Lyrics Island、桌面歌词、竖屏、全屏、移动端 UI、演唱高亮和多行显示等截图入口。
- Lyricify 4 文档公开描述：歌词界面、桌面歌词、全屏界面、可自定义字体、性能/质量特效开关、歌词来源/搜索/导入/编辑和时间轴偏移。这些仅作为产品行为和信息架构参考，不作为当前 UI 的实现证据。
- 文档说明 `Lyricify-Lyrics-Helper` 的歌词处理库使用 Apache License 2.0；本轮不克隆或复制其代码。
- README 及文档中的产品/品牌图标、截图和专有配色不进入 SpotifyLyrics 设计资产。

### Lyricify screenshot observations (read-only)
- `images/readme/func-lyrics-display.png`：主歌词界面以整面动态背景承载大字号居中歌词；当前行高亮白色、上下行明显降低透明度；翻译紧随原文；底部固定歌曲信息与播放控制条，设置入口收进左上角菜单。
- `images/readme/func-lyrics-dynamic-lyrics-island.png`：顶部黑色胶囊收起/短态以歌曲标题、翻译、左右两侧媒体/封面提示为核心，胶囊本身保持极简；截图同时展示更宽的展开状态。
- `images/readme/func-lyrics-desktop.png`：桌面歌词是半透明大卡片叠在背景上，顶部左侧歌曲信息，右侧控制按钮；歌词原文与翻译居中，背景图像和卡片材质保持可见。
- `images/readme/func-lyrics-fulscreen.png`：全屏歌词使用整屏渐变/动态封面，当前行最大最亮，上下行通过透明度和模糊拉开层级；专辑信息位于左下，控制位于右下。
- `images/readme/func-lyrics-vertical.png`：竖屏/移动样式通过窄画布、底部播放卡片和底部导航重排信息；歌词层级仍保持当前行突出、相邻行退后。
- 公开图片尺寸从 1010×460 到 3072×1920 不等；它们只作为观察证据和方向参考，不复制到正式产品。

### Dynamic Lyrics bundle metadata (read-only)
- Bundle ID：`com.bing.lyrics`；版本：`1.9.9`，build：`169`；最低 macOS：`14.6`；`LSUIElement = true`。
- Info.plist 声明了 `spotify-lyrics`、`spotify-lyrics-quick-start` 和 `dynamic-lyrics` URL scheme，以及 Apple Events/Apple Music 媒体信息用途说明。
- 公开资源清单包含 AppIcon、Assets.car、Custom-Regular.otf、Localized strings、配置 plist、视频/音频和若干依赖 bundle；本轮只列清单，不读取/提取/复用品牌或专有素材。

### Dynamic Lyrics black-box initial state
- Computer Use 启动 `/Applications/Dynamic Lyrics.app` 后，窗口标题为本地化的“灵动歌词”。主窗口 AX 树包含歌曲封面、歌名/艺人、喜欢、更多、播放控制、进度文本、歌词滚动区、翻译和搜索按钮。
- 初始可见歌曲为「フレグランス」/茉ひる，时间约 `3:13 / 3:25`；当前行以白色大字突出，下一行及更远歌词逐级模糊/降低透明度；翻译紧随当前行。
- 初始截图显示绿色/青色动态背景取自封面，左侧封面卡片和底部控制区叠在半透明材质上，圆角窗口约 1000×650。
- 只读 WindowServer 查询显示主窗口 `1000×650`、layer 0；同时有两个无标题辅助窗口 `610×200`/layer 27 和 `600×78`/layer 24，说明应用启动时已有辅助层或胶囊状态对象，但需通过交互和截图进一步确认其语义。
- “更多”菜单公开了歌词延时、歌词模糊效果、字体大小（标准/小/特小）、左右/居中对齐、分享、报错和纯音乐标记；这说明设置入口被收进上下文菜单，而不是长期占据歌词画布。
- 播放/暂停按钮和歌曲内容会随外部媒体状态变化；观察期间歌曲从「フレグランス」切换到 `First Love`，因此动态应用不是固定演示数据，后续视觉结论只针对当前窗口状态，不推断数据源实现。
- 点击 macOS 全屏按钮后，Dynamic Lyrics 进入屏幕级歌词布局：截图显示左侧专辑/播放信息、中央当前行和模糊相邻行；WindowServer 主窗口扩展为 `2560×1440`，辅助层仍位于顶部。
- 使用 `super+ctrl+f` 后 AX 树恢复“标准窗口”描述，但截图/WindowServer 仍处于屏幕级布局，说明原生全屏/缩放状态切换需要以实际窗口帧和截图共同判定，不能只看 AX 文本。
- `Cmd+W` 关闭主窗口后，AX 树留下 `floating-lyrics` 系统对话框；这证明主窗口与辅助浮层是分开的。当前浮层截图呈空白/透明状态，不能把“窗口对象存在”误写成“歌词内容可见”。
- 主窗口关闭时 WindowServer 仍显示两个无标题辅助窗口（`610×200` layer 27、`600×78` layer 24）；它们的具体语义需要结合菜单/状态操作继续确认。
- macOS“显示”菜单提供系统级“进入全屏幕”命令；标题栏绿色全屏按钮和菜单命令都是系统窗口状态，不是独立歌词功能入口。
- 多次切换后辅助窗口之一会移动到不同屏幕坐标（例如 `600×78` 从 `1289,69` 到 `534,88`），说明胶囊/辅助窗口位置可能受当前显示器和状态影响；不能用固定坐标设计正式 UI。

### 2026-07-26 UI Reference Audit — clean Xcode runtime correction

- 为避免同名 Bundle ID 复用旧进程，先通过应用菜单退出了旧的 `/Users/apple/backup/sptifylyrics/build/SpotifyLyrics.app` 进程；随后才启动 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`。`ps` 实际显示的可执行文件路径为 DerivedData 路径。
- 干净 Xcode 进程的主窗口 WindowServer 帧为 `900×621`、layer 0；当前捕获保存为 `ui-reference-audit-assets/spotifylyrics-main-xcode.png`。视觉上仍是白色测试面板：左侧常驻歌曲/显示视图/多行开关，右侧歌词画布无封面背景、无模糊材质。
- 干净 Xcode 进程的悬浮歌词为 `600×180`、layer 3（截图 `spotifylyrics-floating-xcode.png`）；可见浅色圆角卡片、原文/罗马音/翻译三行，四周为透明黑色背景，未见上下相邻歌词或动态背景。
- 干净 Xcode 进程的顶部胶囊为 `380×46`、layer 25（截图 `spotifylyrics-capsule-xcode.png`）；可见极浅色胶囊、歌曲标题、第二行文字、左侧图标和右侧播放按钮。没有观察到独立的展开按钮或第二个更大内容态；本轮将“展开态”标为未验证，而不是推断为已实现。
- 干净 Xcode 进程的全屏覆盖为 `2560×1440`、layer 8（截图 `spotifylyrics-fullscreen-xcode.png`）；黑色覆盖层只显示一行蓝色罗马音，右上角有关闭圆钮。当前截图未呈现原文、翻译、相邻行、专辑信息或播放控件，因此与参考的层级式全屏歌词有明显差距。
- 通过应用菜单退出 Xcode 进程并重新用 DerivedData 路径启动，主窗口恢复且进程路径仍指向 DerivedData；这证明的是应用级关闭/重开。窗口级 `Cmd+W` 在辅助窗口同时存在时会把焦点转到最前面的辅助窗，因此本轮不把该次按键误写成主窗口关闭成功。
- `Dynamic Lyrics.app` 本轮已有初始/暂停/全屏黑盒截图和 WindowServer 记录；再次尝试读取时 Computer Use 服务超时，未新增胶囊内容截图。既有 `dynamic-floating.png` 仍只证明存在一个 `600×78` 辅助窗口对象，截图内容为空，不能声称浮动歌词内容可见。

## 2026-07-27 Real Track Visual and Lyrics Slice — initial findings

- `PlaybackState` currently initializes `lyrics` with `MockData.sampleLyrics` and `synchronize(with:)` only replaces `currentTrack`; a Spotify identity change therefore leaves the previous/mock lyrics visible.
- `MainLyricsWindowView` currently composes a fixed design gradient, material veil, and a right-aligned `TrackArtworkView`; it has no track-bound background identity, palette extraction, crossfade, or loading state.
- `Track` already carries `artworkURL` and stable Spotify `id`, so the next design can use those values as the background and lyrics request identity without changing the Spotify provider contract.
- No `.lrc` or local lyrics data files exist in the repository; `LocalProvider` needs an explicit, non-persistent local-file search policy before implementation.

### 2026-07-27 TDD red evidence
- The new core contract intentionally fails before implementation because `SpotifyLyrics/Lyrics/TrackIdentity.swift` does not exist. This confirms the test is exercising the new slice rather than passing against existing code.

### 2026-07-27 Core contract evidence
- Pure Foundation identity/LRC/matcher assertions pass. The first compile attempt exposed a test-harness-only top-level-code issue and an unwanted `MockData` dependency; both were fixed before the green run. No production UI or provider behavior was used to satisfy the core test.

### 2026-07-27 Provider contract evidence
- The LocalProvider temporary-directory test returns a matching document and verifies the original LRC bytes are unchanged after lookup.
- The LRCLIB stub test verifies URL query construction, JSON decoding, synced lyric parsing, absent translation layers, and composite provider ordering.
- A compiler issue in the first LRCLIB implementation was fixed by retaining the typed `LRCLIBError` in the nested 404/search catch; no network behavior was hidden by the test.

### 2026-07-27 Real Track Visual and Lyrics Runtime
- `TrackIdentity` prioritizes Spotify Track ID, then Spotify URI, then ISRC, then normalized title/artist/album/rounded-duration metadata. The stable key includes the metadata fingerprint even when a Spotify ID exists, so an ID-only collision cannot retain the wrong lyrics.
- `PlaybackState` now starts with an empty Spotify placeholder. A real identity transition invokes `LyricsSessionController.begin`, which clears the previous line layers immediately, increments a revision, and enters loading. Results are applied only when both identity and revision still match. Mock lyrics are available only after the explicit Mock Preview action.
- `TrackBackdropView` binds the background request to identity plus artwork URL, clears the current bound payload on key changes, and checks cancellation/key equality after artwork loading and palette generation. Old artwork is held only as a short visual crossfade snapshot and cannot become the current bound background.
- Read-only local lookup uses the approved order: `~/Music/SpotifyLyrics/Lyrics`, `~/Library/Application Support/SpotifyLyrics/Lyrics`, and Debug-only repository `Lyrics/`; it never copies, edits, or persists user files. LRCLIB direct lookup uses `/api/get` and falls back to `/api/search`; plain lyrics are loaded without synchronized playback highlighting.
- Real DerivedData runtime screenshots:
  - `real-track-lyrics-assets/bye-bye-bye-real-lyrics.png`: `Bye Bye Bye` / `*NSYNC`, matching orange cover and dark palette, English synchronized lyrics.
  - `real-track-lyrics-assets/japanese-real-lyrics.png`: `fragrance - Remix` / `茉ひる`, matching dark cover and Japanese synchronized lyrics.
  - `real-track-lyrics-assets/chinese-real-lyrics.png`: `晴天下雨` / `橙汁`, matching blue cover and blue palette, explicit `暂未找到歌词`; the prior Japanese/English rows are absent.
- Externally triggered Spotify track changes initially exposed a refresh gap: the timer only retried unavailable providers, so an outside Spotify next-track action did not update the app. The fix now periodically refreshes while Spotify is ready, which is required for real track identity changes.
- A Debug-only `SPOTIFYLYRICS_LRCLIB_BASE_URL` environment override was used with a refused localhost port to exercise the real app's network-failure path. The runtime tree showed `歌词搜索失败`, the connection error, and a `重新搜索` action; Release ignores the override and keeps `https://lrclib.net/api`.
- The final normal signed Debug build used `Sign to Run Locally`, passed `codesign --verify --deep --strict`, and retained the Apple Events entitlement. The default LRCLIB configuration was restored and a fresh runtime launch returned to the real track loading/loaded path.

## 2026-07-27 Playback and Lyrics Correctness Findings

- `LyricsLookupResult` previously collapsed errors to arbitrary strings and `LyricsSessionController` collapsed `noMatch` into `noLyrics`. The correctness slice now preserves typed categories and separate UI states, so retry/no-result/network/service/parse behavior is observable and testable.
- `LyricsTimeline.activeLineIndex` returns `nil` for plain text documents. `LyricsCanvasView` passes the synchronization flag into the line token calculation, so a plain document is shown as readable full text without a fabricated active row or automatic scroll target.
- The session controller still treats identity and revision as a pair: every provider result is ignored unless both match the active request, and cancellation is checked before applying. Candidate adoption also rejects a candidate whose identity is no longer active.
- A signed DerivedData runtime was tested against the user’s live Spotify queue. After two quick next-track transitions, the app eventually converged from `最人间` to `一点点（为什么晚上总是有星星）`; the final header, artwork-derived background, lyrics and progress all belonged to the latter. The intermediate loading state was captured on a fresh real-track launch.
- Pause/resume, seek, previous/next and exit/reopen were observed through the accessibility tree and screenshots. On Spotify quit, the app cleared the live track and lyrics instead of showing stale or Mock lyrics; after reopen, it reconnected and repopulated the same real track.
- No SQLite, AI, Web API, OAuth or additional lyric source was added. `LocalLyricsProvider` and `LRCLIBLyricsProvider` remain separate behind `LyricsProvider`.

## 2026-07-27 Phase 20 — Reference Audit Started

- `Lyricify-App-main/` has no root `LICENSE`, `LICENSE.*`, or `COPYING` file; the requested first read returned “No such file or directory”. Treat the checkout as reference-only and do not assume its source, screenshots, icons, or brand assets are licensed for copying.
- Continue with README/docs/images only for public behavior and interaction observations; inspect actual UI mode/persistence files read-only and implement an independent SwiftUI composition.

## 2026-07-27 Phase 20 — Fresh UI Reference Audit

### Lyricify public checkout
- Repeated the required first read: `Lyricify-App-main/LICENSE` is absent; `find` also found no `LICENSE*` or `COPYING*` within the checkout. This is a licensing boundary, not evidence of a permissive license for the screenshots or resources.
- The checkout contains documentation, screenshots, language strings, theme resources, and a settings example, but no Swift, C#, or XAML application implementation. Relevant files inspected read-only are `README.md`, `docs/Lyricify 4/README.md`, `docs/Lyricify 4/Lyrics.md`, `docs/Lyricify 4/settings.json`, and the public images under `images/readme/`.
- `docs/Lyricify 4/README.md` describes the main menu, bottom-left track information, bottom-center playback controls, and bottom-right feature controls including lyrics, Apple Music lyrics, Spotify Connect, volume, and fullscreen. It also documents vertical-layout switching, manual lyric import, and lyric-source management.
- `docs/Lyricify 4/settings.json` is an example of persisted settings rather than UI source. It names `window_main`, `apple_music_lyrics`, `dynamic_lyrics_island`, and `desktop_lyrics` sections and stores window position/size, typography, blur, animation, and open/closed state. There is no discoverable enum or switch implementation in this checkout.
- Public images show the generic interaction pattern of a full-window lyric canvas, contextual settings, a compact top island, a desktop lyric view, and an Apple-Music-like lyric view. No image, icon, brand name, or color recipe is copied into SpotifyLyrics.

### Dynamic Lyrics black-box
- Fresh AX state for `/Applications/Dynamic Lyrics.app` showed a standard main window with artwork, title `SAD SONG`, artist `CHANMINA`, favorite/more controls, elapsed/total time, previous/pause/next, a scrollable timed lyric list with bilingual rows, translation and search buttons, and standard macOS window controls.
- The fresh screenshot is a 1000×650 rounded window with a large artwork block on the left and lyrics on the right. The current bilingual row is bright and largest; nearby rows remain readable but dim/blurred; the background is a warm, cover-derived blurred field with a darkened readability veil. Playback controls and progress live at the bottom of the artwork column.
- Existing WindowServer evidence records the main window at 1000×650 and two separate auxiliary windows at 610×200 and 600×78 on higher layers. Their exact collapsed/expanded semantics are not inferred from size alone; the top-island expansion state remains unverified.
- The more menu is contextual and exposes lyric delay, blur, font-size choices, alignment, share/report, and a pure-music toggle. This supports moving infrequent controls into a menu rather than a permanent settings panel.
- Observation assets already in the repository are `ui-reference-audit-assets/dynamic-main-initial.png`, `dynamic-main-paused.png`, `dynamic-fullscreen.png`, and `dynamic-floating.png`; they are screenshots only and contain no extracted bundle resources.

### Music.app black-box
- Fresh AX state for `com.apple.Music` showed the real macOS shell: sidebar entries for Search/Home/Radio/Library/Recently Added/Artists/Albums/Songs/Store, an account button, and a mini-player with shuffle, previous, play, next, repeat, now-playing, lyrics, queue, AirPlay, and volume controls.
- No active song or lyrics were available in the current local Music.app session; transport controls were disabled and the home page showed the subscription marketing shelf. Therefore no playback/lyrics visual behavior is claimed as observed. The shell demonstrates a compact persistent transport bar and a dedicated lyrics entry, not a permanent settings panel.

### Apple official guidance consulted
- Apple HIG `Materials` recommends choosing system materials and blending modes (`behindWindow` or `withinWindow`) deliberately, using vibrancy to keep foreground content legible, and avoiding opaque regions that unnecessarily block content.
- Apple HIG `Windows` describes resizable macOS windows with system controls and distinct main/key states; content must remain usable while people resize and switch between apps.
- Apple HIG `Layout` requires layouts to adapt dynamically to context; SwiftUI layout tools are an approved way to keep relationships stable as the window changes size.
- Apple HIG `Designing for macOS` emphasizes spacious desktop canvases and user personalization. Apple Design Resources provides official macOS UI kits and system font references; this project will use system controls/fonts rather than importing Apple assets.

### Consequence for phase 2
- 设计参考范围已按用户确认收敛：主参考只保留 Dynamic Lyrics 黑盒与 Lyricify 的 Apple Music 歌词模式；Music.app/HIG 仅作平台约束，不作为视觉样板。
- Keep `lyricsFocus` as the current vertical lyric experience and add `immersiveSplit` as a compositional sibling. Both must consume the existing `PlaybackState`, lyric session, provider, artwork-bound backdrop, and playback actions.
- The split layout uses a responsive breakpoint: a cover/metadata/control column when wide, and a stacked cover-plus-lyrics composition when narrow. It does not clone the reference products' pixel measurements.
- Normal Spotify connection status moves to a compact toolbar/menu/status affordance; only actionable failures occupy content space. Adjacent lyrics use opacity first and only a light blur at farther distances.

## 2026-07-27 Song search implementation findings

- Neither reference application supplied a reusable search implementation. The formal implementation uses an independent `SongSearchProvider` protocol and a single `SongSearchResult` model.
- Provider order is Local → Spotify current track → LRCLIB. `SongSearchManager` cancels the previous task, increments a generation, merges duplicate metadata while preferring results that include lyrics, and ignores late results from an older generation.
- `LocalSearchProvider` is read-only and uses the same approved user/application/Debug Lyrics directories as the lyric provider. `LRCLIBProvider` only decodes public search JSON; it does not persist results.
- A selected result with lyrics is loaded only after high-confidence metadata matching against the active Spotify track; the active playback time and track are not mutated. A Spotify-current-track result triggers a normal lyric retry for that identity.
- Runtime observation on the Japanese track `あやふや` showed the search popover, an LRCLIB result (`Ambiguous`) and a Spotify-current-track result. Selecting the mismatched LRCLIB result was rejected with an explicit identity message; selecting the current-track result entered the loading state without changing the `00:04 / 01:59` playback anchor.
- The focus-mode playback-control bug was reproduced in screenshots despite AX nodes being present. The root cause was the order of `.frame(maxHeight: .infinity)` and top padding on `layoutBody`; an explicit GeometryReader content height now keeps the control panel inside the visible window.

### 2026-07-27 Song search final signed runtime

- After the final signed rebuild, the exact DerivedData app was relaunched and the search popover was opened through its AX button. Querying the real Japanese track `あやふや` produced a unified list with LRCLIB candidates and the Spotify current-track result; repeated LRCLIB release rows were merged by normalized title/artist while preserving the best candidate metadata.
- Selecting the Spotify current-track result displayed `已重新搜索当前歌曲歌词` and `正在搜索歌词…` while the same live track and `00:04 / 01:59` remained visible. Selecting an LRCLIB result for another artist displayed `搜索结果与当前歌曲匹配度不足，未加载`; it did not replace the track, cover, playback anchor, or lyrics identity.
- The final signed runtime switched from `lyricsFocus` to `immersiveSplit` and back without restarting. Both modes exposed the real cover, track metadata, progress slider, previous/play/next controls, and the same paused position. Final screenshots are `ui-redesign-assets/phase2-lyrics-focus.png` and `ui-redesign-assets/phase2-immersive-split.png`.
- Search result IDs now use real interpolation for local file paths, Spotify identity keys, and LRCLIB record IDs. Search de-duplication intentionally ignores release album and duration differences, while TrackIdentity remains strict and still includes metadata/duration for playback and lyric session safety.

## 2026-07-27 Phase 22 — local reference audit preliminary

- `/Users/apple/backup/sptifylyrics/Lyricify-App-main` has no `LICENSE`, `LICENSE.*`, or `COPYING*` file at the checked depth. It is a reference copy inside the formal repository rather than an independent Git checkout (`git ls-files` returns zero there), so its README claims must not be treated as a source license.
- The public README says Lyricify 3 historically supported Spotify, iTunes/Apple Music, QQ Music, Netease Cloud Music, Music Center and YesPlayMusic; Lyricify 4 is Spotify-only, and Lyricify Lite consumes Windows SMTC metadata from apps including QQ Music, Netease and Kugou rather than exposing a cross-platform catalog API.
- The README links `WXRIW/Lyricify-Lyrics-Helper` as the only explicitly open-sourced lyrics-processing code and identifies it as Apache License 2.0. The Lyricify 3 language strings mention QQ Music/Netease retrieval by platform IDs and a Lyricify server, but do not expose a reusable provider implementation in this copy.
- The custom Spotify API-client docs are legacy/migrated documentation and warn about removed Spotify APIs, redirect-URI changes and Premium requirements; this is evidence of upstream maintenance/API drift, not a license to reuse code or credentials.

## 2026-07-27 Phase 22 — current architecture audit preliminary

- `SongSearchManager` currently mixes three responsibilities: free-text catalog-like search, current Spotify-track refresh, and lyric-bearing result selection. Its `SongSearchResult` may carry a `LyricsDocument`, so a search result is both a track candidate and a lyric version.
- `SpotifyCurrentTrackProvider` is not a catalog provider: it only refreshes the already-playing Desktop snapshot and scores it against the query. It should become a `CurrentTrackResolver`/playback adapter rather than a long-term `TrackSearchProvider`.
- `LocalSearchProvider` is actually a local LRC-file search and returns lyric-bearing tracks; `LocalLyricsProvider` separately resolves local files for a known `TrackIdentity`. The duplicate file scanning and different identity behavior should be unified behind a read-only local index in a future refactor.
- `LRCLIBProvider` combines song-result search and lyric document parsing, while `LRCLIBLyricsProvider` separately resolves and scores lyric versions. This confirms the requested split: catalog/search providers should return metadata only; lyric providers should return `LyricsCandidate`/`LyricsDocument` after identity matching.
- `TrackIdentity` is appropriately strict (Spotify ID/URI, ISRC, or normalized metadata with duration), but `SongSearchResult.searchMergeKey` intentionally drops album/duration for UI de-duplication. That key must never be used as playback/lyrics identity.
- `LyricsMatcher` and `LyricsSessionController` already provide the right boundary for lyric-version confidence, candidate presentation, cancellation, and active-identity checks. The next architecture should preserve these while moving orchestration into separate `TrackSearchManager` and `LyricsSearchManager`.

## 2026-07-27 Phase 22 — Apple Music/MusicKit evidence

- Apple’s current MusicKit documentation exposes `MusicCatalogSearchRequest` for catalog search and `Song`/catalog-song attributes for title, artist, album, duration, artwork, `isrc`, persistent ID, URL and `hasLyrics`; the catalog is storefront-specific and the request has limit/offset controls.
- Apple requires a signed developer token from an Apple Developer Program member for Apple Music API requests; MusicKit can manage token generation for Apple-platform apps. User-library/personal operations require a Music User Token and macOS apps must declare `NSAppleMusicUsageDescription`/request user authorization.
- Apple’s public Apple Music API reference documents `hasLyrics` but no public catalog-lyrics content endpoint or `LyricsProvider` response in the current API collection. The official public path therefore supports catalog metadata and an availability hint, not retrieval of ordinary, synced, or word-synced lyric text. Treat private Music-app endpoints or reverse-engineered TTML feeds as out of scope.
- Apple documents rate limiting as temporary HTTP 429 for developer-token requests; no fixed public quota was found in the reviewed pages. Catalog search is native-macOS-friendly through MusicKit, but app signing/entitlements, developer membership, and storefront behavior add setup and release risk. Apple Music subscription is relevant to playback/personal capabilities, not basic public catalog metadata.

## 2026-07-27 Phase 22 — LRCLIB technical verification

- The public `https://lrclib.net/api/search?q=Bohemian%20Rhapsody` request returned HTTP 200 and JSON records containing `id`, `trackName`, `artistName`, `albumName`, `duration`, `plainLyrics`, and `syncedLyrics`. The direct `/api/get` request with title/artist/album/duration also returned HTTP 200 with both plain and synced lyric text. A malformed/unsupported Japanese query in the first probe returned HTTP 400 and an exact metadata miss returned HTTP 404, so callers must classify 4xx separately from network failures.
- The upstream server repository is public MIT-licensed, describes itself as a free synchronized-lyrics service with machine-friendly APIs, and had a latest GitHub API push on 2026-06-24. At the 2026-07-27 check it reported 62 open issues, 1,887 stars and 70 forks. This shows active maintenance but also that the hosted API/data service is an external dependency; the repository license does not grant rights to redistribute the lyric database or guarantee its service/data terms.
- Recommendation remains Local first, LRCLIB second for opt-in desktop use, with bounded timeouts, no automatic user-file writes, memory/disk caching only after an explicit retention policy, provider health classification, and a manual retry. Do not treat LRCLIB as a rights-cleared lyric source for an App Store/commercial release without separate review.

## 2026-07-27 Phase 22 — Chinese platform evidence

- NetEase Cloud Music: no official public third-party catalog/lyrics API or native-macOS SDK was found in the reviewed official/public sources. The well-known `Binaryify/NeteaseCloudMusicApi` project has no detectable license file/license metadata, last pushed 2024-02-28, and reports 147 open issues at this check. Its README/npm description exposes search, song detail, lyrics and login by proxying undocumented NetEase endpoints with `weapi`/`eapi` request encryption. A read-only probe of `https://music.163.com/api/search/get/web` returned HTTP 200 song metadata and `/api/song/lyric` returned LRC plus translated LRC for a public Queen track, but this proves availability of an undocumented endpoint, not permission or stability. Cookies, anti-bot behavior, regional availability and terms make it an experimental/local-only source.
- QQ Music: Tencent Cloud’s official “音乐服务” H5 SDK documents authenticated QQ Music search, song detail, artwork/duration/IDs and `describeLyric`, but it is a Tencent 连连 H5-panel SDK; other than login/anonymous endpoints, calls require QQ Music authorization. It is not a general native macOS REST/Swift API, and the reviewed docs do not provide App Store distribution terms or a standalone lyric-data license. An undocumented `c.y.qq.com` search probe returned HTTP 200 metadata for a Queen track; the corresponding lyric probe returned HTTP 200 with `retcode:-1310`, demonstrating session/anti-abuse requirements. The commonly used `jsososo/QQMusicApi` is a GPL-3.0 Node proxy (last push reported 2024-06-25, 62 open issues) that changes referers and depends on QQ cookies; it is not a drop-in native provider and GPL/credential/terms risk must be isolated.
- KuGou: KuGou’s official Open Platform documents an approved mini-player integration for H5/iOS/Android with appid/appkey/ticket and platform review; it exposes search/play metadata and playback but not a general public lyrics API for a native macOS app. The maintained `MakcRe/KuGouMusicApi` project is MIT-licensed, published v1.5.1 on 2026-02-05 and pushed 2026-06-30, but its README explicitly says study-only/non-commercial and asks users to clear copyright data within 24 hours. It calls undocumented platform endpoints and includes LRC/KRC-style lyric flows. A read-only mobile search probe returned HTTP 200 metadata, while a lyric-detail probe returned no data for the sampled hash; endpoint and certificate behavior varied. This is not suitable for the core or public-release path.

## 2026-07-27 Phase 22 — supplemental official/licensed sources

- Musixmatch’s current official Postman API documentation requires an API key in every request and documents matcher endpoints using title/artist/ISRC. The examples expose platform identifiers, album/artist/title, duration, `has_lyrics`, `has_subtitles`, `has_richsync`, translations and region restrictions; `matcher.lyrics.get` returns ordinary lyrics and `matcher.subtitle.get` returns timestamped subtitle/LRC-style lines. This is a licensed/commercial API surface, not a free anonymous endpoint: pricing, allowed storage and redistribution must be agreed with Musixmatch before release. It is the best rights-oriented later replacement for LRCLIB if the project obtains a plan, but never embed a private key in a desktop binary.
- Genius’s public developer surface is suitable for song/artist/search metadata and canonical URLs, but the reviewed public documentation does not provide a licensed raw lyric-text endpoint. Acquiring lyric text by scraping Genius pages or using an unofficial scraper would introduce terms, copyright and breakage risk; therefore Genius is metadata-only/optional and not a lyrics provider.
- Deezer exposes a developer portal/API entry point, but the current developer page redirects to login and the reviewed public material did not establish an unauthenticated macOS catalog contract, lyric-text endpoint, storage terms or stable quota. Treat it as a possible metadata-only adapter after account/terms review, not as a current lyric source.
- Apple Music remains the only additional first-party native-macOS catalog option verified in this pass. Its public catalog has song metadata and `hasLyrics`, but not lyric text; MusicKit therefore cannot replace a lyrics provider by itself.

## Phase 23 architecture findings
- Track search and lyrics search are now separate managers; UI still binds to `SongSearchManager` which mirrors metadata-only track results.
- Shared `LocalLyricsIndex` prevents double directory scans between local track search and local lyrics lookup and never writes user files.
- LRCLIB must stay out of free-text track search; personal-desktop lyrics path keeps opt-in style isolation and does not persist online lyrics by default.

## Phase 25 alignment V1 acceptance findings — corrected after runtime audit
- `AlignmentService` is the SwiftUI-independent boundary. `AudioPCMConverter` validates/read-probes the selected local file, creates a temporary 16 kHz mono PCM WAV, hashes the original, and cleans the temporary directory without modifying the source audio.
- `SpeechForcedAlignmentService` uses macOS Speech tokens and `LineForcedAligner` for deterministic kana-normalized dynamic/fuzzy matching. Original kanji lines remain separate from kana and romaji layers; no word-level timestamp tags are emitted.
- A contiguous unmatched tail is interpolated as a group between the prior anchor and audio end. This fixed a real defect where multiple tail lines collapsed to the same timestamp.
- Runtime audit found that the earlier preview/confirmation was invalid: the checked-in `kawasaki_tts.wav` is 79.8255 seconds, while the live Spotify track is 171.177 seconds. Its 32 timestamps therefore ended near 1:18 and could move before the real singer's onset. Those results and screenshots are not acceptance evidence.
- The clean signed DerivedData binary `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` now rejects this mismatch before Speech recognition. The real App retained QQ's 32 plain lines, returned to `alignmentQueued`, displayed the explicit duration error, and did not create an `.aligned.lrc`.
- `AlignmentDurationValidator` allows only small edit/intro/outro differences; the leading unmatched interpolation rule also forbids scheduling a row before the first timed recognition anchor.
- The duration-mismatch log and screenshot are in `docs/superpowers/specs/acceptance-2026-07-27-alignment-v1/`. A valid full-song alignment remains unverified until a matching 171-second local audio file is supplied.
- Standalone contracts emit only Swift 6 Sendable warnings for existing test doubles and AVFoundation's non-Sendable buffer API; Xcode normal signed Debug build succeeded and `codesign --verify --deep --strict` passed with `Sign to Run Locally` / ad hoc signature.

## 2026-07-30 — Real audio line alignment V1 plan audit

- 基线为 `f5c0c9ba8ee26d1e5d9c6cc97aba711711652bd8`；当前工作区无业务源码未提交改动，已有参考目录/旧审计文档仍为未跟踪文件。
- 现有 `AlignmentService`、`AudioPCMConverter`、`SpeechForcedAlignmentService`、`LineForcedAligner`、`LyricsSessionController`、`LocalAlignedLyricsStore` 已进入 App target 并接入主路径。
- 现有 `LineForcedAligner.spreadLowConfidence` 会在无识别证据时平均铺开时间，和新阶段安全边界冲突；历史 `kawasaki_tts.wav` 时长不匹配，不能作为真实验收证据。
- 当前 SQLite v3 已有 `parent_version_id`，但没有 alignment provenance 列；计划不执行 migration v4，改用独立 provenance sidecar，并在实现前向用户明确这个边界。
- 真实商业歌曲逐行排轴仍未验收，必须等待用户提供与当前 TrackIdentity 对应的完整本地人声音频。

## 2026-07-30 — Real Audio Line Alignment V1 implementation gate

- 已实现并接入 `TimedTranscriptProvider`、Speech adapter、全局单调 DP 逐行对齐、逐行 evidence/confidence、音频 hash/预检/临时 PCM 生命周期和取消保护。
- 已移除 `spreadLowConfidence`、自动环境触发和所有全局/首尾平均铺轴；无边界证据的行保持 unresolved，不写入时间轴。
- 已使用 `AlignmentSessionGuard` 绑定 TrackIdentity、父版本、源内容 hash 和 revision；切歌、取消、迟到进度/结果不会写入新歌曲，也不改变播放位置。
- SQLite 继续使用 v3；确认排轴建立 `automaticAlignment` 子版本，provenance 写入 `~/Library/Application Support/SpotifyLyrics/AlignmentProvenance/<lyricsVersionID>.json`，缺失 sidecar 显示 unavailable。
- 所有 35 个合同脚本在正确解释器下通过；新增音频/DP/会话/持久化合同使用 TEST fixture，不代表商业歌曲验收。
- 正常签名 Debug 构建、codesign 和绝对路径进程来源验证通过。详细记录见 `docs/superpowers/specs/acceptance-2026-07-30-real-audio-line-alignment-v1/README.md`。
- **Code/contracts/build acceptance：PASS；real commercial-song acceptance：UNVERIFIED。**
