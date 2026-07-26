# SpotifyLyrics 真实性审计

审计日期：2026-07-26
正式项目：`/Users/apple/backup/sptifylyrics`

## 范围与边界

- `/Users/apple/backup/sptifylyrics`：唯一允许修改的正式项目。
- `/Applications/Dynamic Lyrics.app`：只作为黑盒 UI/交互参考。本轮只读取 Info.plist。
- `Lyricify-App-main/`：只作为公开文档、截图、歌词格式和功能说明参考。
- 本轮未修改 Swift 源码、`SpotifyLyrics.xcodeproj` 的产品配置、参考目录或任何 `.app`。
- 本轮新增了标准 Xcode 构建验证，并只写入 `.gitignore`、本审计报告和现有规划记录。

## 结论摘要

当前项目是一个能实际运行的原生 SwiftUI 演示应用。主窗口、悬浮歌词、顶部胶囊和屏幕覆盖式歌词窗口都能真实创建，窗口开关、模拟播放计时和主窗口关闭/重开也能工作。

现有 `build/SpotifyLyrics.app` 仍不是 Xcode 工程构建产物，而是旧提交中的 `build.sh` 直接调用 `swiftc` 后手工拼装的 `.app`。在本轮用户完成 Xcode 许可和初始化后，真实 `xcodebuild -list` 与 Debug build 均已成功；新的标准产物位于 `DerivedData/Build/Products/Debug/SpotifyLyrics.app`。

产品功能目前仍是 Mock 演示：没有 Spotify 播放状态、歌词 Provider、SQLite、自动搜索匹配、AI 翻译、自动排轴、LRC/TTML 导入编辑导出等实现。

## 已真实验证

### Git 基线

- `pwd`：`/Users/apple/backup/sptifylyrics`
- 分支：`main`
- 最近提交只有两次：
  - `5461f44 Migrate project structure to SpotifyLyrics.xcodeproj`
  - `77956d1 Phase 1: Implement macOS SwiftUI independent Spotify Lyrics App with Mock lyrics and 4 display modes`
- 审计开始时状态：

```text
 M .gitignore
?? findings.md
?? progress.md
?? task_plan.md
```

`.gitignore` 的修改来自此前将 `Lyricify-App-main/` 设为本地只读参考目录，不是本轮产品代码修改。

### Xcode 工程静态结构

- `SpotifyLyrics.xcodeproj/project.pbxproj` 通过 `plutil -lint`。
- 工程声明一个 `SpotifyLyrics` application Target。
- Bundle Identifier：`com.spotifylyrics.app`
- Deployment Target：macOS 14.0
- Swift：5.0
- Build configurations：Debug、Release
- 现有 6 个 Swift 文件全部同时存在于：
  - PBXFileReference
  - PBXBuildFile
  - PBXSourcesBuildPhase
- 没有发现“代码文件存在但未加入 Target”的情况。
- 工程中没有共享 `.xcscheme` 文件。

### 现有 App Bundle（旧手工产物）

- 路径：`build/SpotifyLyrics.app`
- Info.plist 语法有效：
  - `CFBundleIdentifier = com.spotifylyrics.app`
  - `CFBundleExecutable = SpotifyLyrics`
  - `LSMinimumSystemVersion = 14.0`
- 可执行文件：thin arm64 Mach-O
- 签名：ad-hoc / linker-signed
- `Info.plist=not bound`
- 无密封资源。
- 二进制符号包含：
  - `MainWindowView`
  - `FloatingLyricsView`
  - `CapsulePlayerView`
  - `FullScreenLyricsView`
  - 三个 WindowManager 切换方法
  - `MockData`

### 产物来源

通过 `git show 77956d1:build.sh` 确认，现有 app 的生成方式是：

1. `swiftc` 直接编译六个 Swift 文件；
2. 指定 `arm64-apple-macosx14.0`；
3. 输出到 `build/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`；
4. shell 脚本手工写入 Info.plist。

迁移提交 `5461f44` 删除了 `build.sh` 和 `Package.swift`，但被 `.gitignore` 忽略的旧 build 产物仍留在本地。

### 运行时 UI

实际启动 `build/SpotifyLyrics.app` 后验证：

- 主窗口真实可见，显示硬编码的 YOASOBI《夜に駆ける》和 6 行示例歌词。
- 播放按钮可触发本地 Timer；时间从 0.2 秒推进到约 3.8 秒，暂停后停在约 27.6 秒。
- 原文、翻译、罗马音、假名开关真实存在。
- WindowServer 验证：

| 窗口 | 尺寸 | Layer | 结果 |
|------|------|-------|------|
| 主窗口 | 900×552/621 | 0 | 可见 |
| 悬浮歌词 | 600×180 | 3 | 可创建、关闭、重新打开 |
| 顶部胶囊 | 380×46 | 25 | 可创建、关闭、重新打开 |
| 屏幕覆盖歌词 | 2560×1440 | 8 | 可创建、关闭、重新打开 |

- 主窗口 `Cmd+W` 后进程继续存活。
- 以 Bundle ID `com.spotifylyrics.app` 重新激活后，主窗口重新出现并保留模拟播放状态。
- 审计结束时已退出 SpotifyLyrics，未留下运行进程。

### Xcode 标准构建基线（本轮新增）

环境输出：

```text
xcode-select -p
/Applications/Xcode.app/Contents/Developer

xcodebuild -version
Xcode 26.6
Build version 17F113
```

`xcodebuild -list -project SpotifyLyrics.xcodeproj` 真实列出：

- Target：`SpotifyLyrics`
- Build Configurations：`Debug`、`Release`
- Scheme：`SpotifyLyrics`

真实构建命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project SpotifyLyrics.xcodeproj \
  -scheme SpotifyLyrics \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

构建结果：退出码 `0`，日志结尾为 `** BUILD SUCCEEDED **`。Xcode 生成的标准 `.app` 绝对路径为：

`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`

本轮没有缺少 Scheme，也没有修改 Scheme 或工程配置。构建日志有两个非失败提示：多匹配 macOS destination 时使用首个目标，以及没有 `AppIntents.framework` 依赖时跳过 metadata extraction；它们不影响退出码为 0 的构建结果。

旧产物与新产物明确分开：

| 产物 | 来源 | 本轮结论 |
|------|------|----------|
| `/Users/apple/backup/sptifylyrics/build/SpotifyLyrics.app` | 旧 `build.sh` + 直接 `swiftc` + 手工 Info.plist | 保留用于对照，不是 Xcode 基线 |
| `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` | 本轮 `xcodebuild` Debug | 标准 Xcode 构建基线 |

### 新 Xcode 产物运行时验证

启动的是 DerivedData 中的新 `.app`，不是旧 `build/` 产物。Computer Use 读取到主窗口和歌词内容；只读 WindowServer 查询确认实际 on-screen 窗口：

| 窗口 | 尺寸 | Layer | 验证 |
|------|------|-------|------|
| 主窗口 | 900×621 | 0 | 干净启动可见；`Cmd+W` 后消失；重新启动后恢复 |
| 悬浮歌词 | 600×180 | 3 | 打开、关闭后消失、重新打开后恢复 |
| 顶部胶囊 | 380×46 | 25 | 打开、关闭后消失、重新打开后恢复 |
| 全屏覆盖歌词 | 2560×1440 | 8 | 打开、关闭后消失、重新打开后恢复 |

因此本轮只确认这些已有 Mock UI 在新的 Xcode 产物中可运行；没有把进程存在当作窗口验证，也没有开发 Spotify、歌词源、SQLite、AI 或自动排轴。

## 仅有代码但未验证

### Xcode Scheme 与真实工程构建（历史状态，已由本轮更新）

- 工程结构包含一个 `SpotifyLyrics` Target。
- 本轮 `xcodebuild -list` 已识别 `SpotifyLyrics` Scheme。
- 本轮 Debug `xcodebuild` 已退出码 0 并返回 `BUILD SUCCEEDED`。
- 本轮已创建 `DerivedData`，并确认其 `.app` 是标准 Xcode 产物。

### 多桌面与原生全屏 Space

- 悬浮和胶囊窗口代码设置了：
  - `.canJoinAllSpaces`
  - `.fullScreenAuxiliary`
- 本机当前活跃显示器只有一个 Space，`Ctrl+Right` 没有形成可验证的桌面切换。
- 没有真实验证它们能否跨多个桌面持续显示。
- 没有真实验证它们能否覆盖另一个应用的原生全屏 Space。

### 配置字段

- `PlaybackState.currentMode` 只声明，未参与 UI 或窗口逻辑。
- `DisplayPreferences.opacity` 没有应用到窗口或 View。
- `DisplayPreferences.alwaysOnTop` 没有控制窗口 level。
- `Track.isrc` 和 `spotifyId` 只用于模型和 MockData，没有接入搜索逻辑。

## 尚未实现

- Spotify 当前播放状态读取或授权。
- 真实歌曲切换、暂停、进度同步。
- 多歌词源 Provider。
- 网络请求层或 `URLSession`。
- SQLite 或其他永久歌词库。
- 自动歌词搜索与候选匹配。
- AI 整首歌词翻译。
- 日语假名生成与罗马音处理；当前内容为硬编码文本。
- 无时间轴歌词自动逐行排轴。
- LRC、TTML、QRC、KRC、YRC 导入/解析。
- 歌词编辑和导出。
- 专辑封面加载；当前使用 SF Symbol。
- 设置持久化。

## 错误或虚假实现（仍适用的边界）

### 1. 不能把旧 `build/` 产物声称为 Xcode 工程构建产物

`build/SpotifyLyrics.app` 是 `swiftc` 手工编译并由 shell 拼装，不是 `xcodebuild` 产物。本轮已证明工程本身可以由 Xcode Debug 构建，但这不会改变旧 `.app` 的来源。

### 2. “Spotify 播放”实际是 Mock Timer

`PlaybackState` 直接使用 `MockData.sampleTrack` 和 `MockData.sampleLyrics`。播放按钮只启动本地 Timer，没有读取 Spotify。

### 3. “全屏歌词”不是 macOS 原生全屏 Space

代码创建一个覆盖 `NSScreen.main.frame` 的 borderless NSWindow，layer 8。它是屏幕覆盖窗口，不是通过 `toggleFullScreen` 进入的独立原生全屏 Space。

### 4. 多桌面/全屏辅助能力不能仅凭 flags 宣称完成

代码 flags 存在，但本轮环境没有第二个活跃 Space，实际跨 Space 行为没有证据。

## Xcode 环境变化（审计历史记录）

审计开始时：

```text
xcode-select -p
/Library/Developer/CommandLineTools
```

且 `/Applications/Xcode*.app` 不存在。

审计期间外部环境发生变化：

- `/Applications/Xcode.app` 出现；
- `xcode-select -p` 改为 `/Applications/Xcode.app/Contents/Developer`；
- Xcode 版本为 26.6，Build 17F113。

这不是本轮 Codex 执行的修改。重新运行后：

```text
xcodebuild -version
Xcode 26.6
Build version 17F113
```

在用户接受许可之前，`xcodebuild -list` 和 build 均返回：

```text
You have not agreed to the Xcode license agreements.
```

当时未运行 sudo，也未替用户接受许可协议。用户随后已完成许可和首次初始化，本轮已在新的许可状态下完成标准构建。

## 执行过的主要命令

```bash
pwd
git status --short
git log --oneline -5
ls -d /Applications/Xcode*.app 2>/dev/null
xcode-select -p
plutil -lint SpotifyLyrics.xcodeproj/project.pbxproj
find SpotifyLyrics.xcodeproj -maxdepth 4 -type f
rg --files SpotifyLyrics -g '*.swift'
rg -n '...build settings...' SpotifyLyrics.xcodeproj/project.pbxproj

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -list -project SpotifyLyrics.xcodeproj

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project SpotifyLyrics.xcodeproj \
  -scheme SpotifyLyrics \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

plutil -p build/SpotifyLyrics.app/Contents/Info.plist
file build/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics
lipo -info build/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics
otool -L build/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics
codesign -dvvv build/SpotifyLyrics.app
git show 77956d1:build.sh
nm -nm build/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics | swift-demangle
pgrep -fl SpotifyLyrics
lsappinfo find bundleID=com.spotifylyrics.app
```

另外使用 Computer Use 实际操作窗口，并使用只读 WindowServer 查询核实窗口尺寸、层级和 on-screen 状态。

## 推荐的最小下一步

保持 `DerivedData/` 和 `build/` 只作为本地构建目录，不提交构建产物。后续如开始产品功能开发，应从新的独立分支开始，并继续把 `build/SpotifyLyrics.app` 仅作为旧手工产物对照。
