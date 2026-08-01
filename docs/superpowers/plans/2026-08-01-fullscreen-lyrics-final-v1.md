# 全屏歌词最终版 V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有可运行但过时的全屏歌词入口升级为一个单例、可追踪、使用共享 Playback/Lyrics/Translation 状态的 macOS 全屏歌词窗口，并同时保留纯文本未排轴的真实性。

**Architecture:** 保留 `WindowManager` 作为兼容 façade，但把旧的直接 `NSWindow` 创建路径替换为唯一的 `FullScreenLyricsWindowController`。控制器只管理一个无边框 `NSPanel` 的生命周期、屏幕定位、键盘和控件显隐；歌词 View 只读取 `PlaybackState` 的 live projection，不创建 Provider、session、翻译状态或播放计时器。背景直接复用 V3 已有的封面快照、色板和缓存管线。

**Tech Stack:** Swift 5 / SwiftUI / AppKit `NSPanel` + `NSWindowDelegate` / Combine `ObservableObject` / 现有 `PlaybackState`、`LyricsSessionController`、`TranslationSessionController`、`AppSettingsStore`、`AppleMusicImmersiveV3BackdropCache`。

## Global Constraints

- 基线 commit：`a9edc600b685a8c82e780769001d6e87a4d1496f`。
- 本计划只覆盖全屏歌词；不得新增歌词 Provider、AI、排轴算法、逐字歌词或 Track Identity migration v4。
- 不修改主窗口 V2/V3、悬浮歌词和顶部胶囊的视觉/业务行为；只复用它们已经存在的共享状态和背景基础设施。
- 全屏窗口必须复用 `PlaybackState → LyricsSessionController → TranslationSessionController → AppSettingsStore`，不得创建第二个 Spotify polling timer、歌词搜索、歌词缓存、当前行计算、翻译状态或显示偏好存储。
- 正式全屏渲染只允许读取 `PlaybackState.liveLyrics`、`liveLyricsState`、`liveLyricsAreSynchronized`、`liveCurrentLineIndex`、`currentTrack`、`currentTrackIdentity`、`currentTime`、`isPlaying` 和既有显示设置；禁止读取可能被搜索预览替换的 `state.lyrics`、`state.lyricsState`、`state.currentLineIndex`。
- 纯文本、`alignmentQueued`、`alignmentRunning` 和未确认的 `alignmentPreview` 不得伪造当前行、滚动同步或平均铺开时间。
- 播放位置只有用户明确操作进度控件时才能改变；进入、退出、展开控件、点击歌词和移动窗口都不得隐式 seek。
- `NSPanel` 最高使用 `.floating`；不得使用 `.statusBar`、`.modalPanel` 或抢占系统安全界面的层级。
- 任何迟到的 Provider、翻译、编辑、排轴或封面结果必须经过当前 identity/revision/session guard，不能闪回旧歌曲。
- 本轮第一轮交付只写计划；实施前必须得到用户确认。当前不修改 Swift、Xcode 工程、不构建、不提交。

---

## 1. 现有全屏代码审计

### 1.1 当前入口和真实调用路径

当前入口不是独立全屏 Scene，而是两个主窗口 UI 里的菜单，以及旧的设置 popover：

```text
Main.swift WindowGroup
  → MainLyricsWindowView
      → legacyWindowBody.windowModeMenu
      → AppleMusicImmersiveV3WindowView.toolBar.windowModeMenu
      → LyricsPreferencesPopover
          → WindowManager.shared.toggleFullScreen(state: playbackState)
  → WindowManager.fullScreenWindow: NSWindow?
      → NSHostingView(rootView: FullScreenLyricsView().environmentObject(state))
      → FullScreenLyricsView
```

代码证据：

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift:76-99` 直接创建 `NSWindow`，并把全屏 View 注入同一个 `PlaybackState`。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift:300-345` 和 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift:220-265` 都调用同一个 `WindowManager` façade。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift:38-40` 还有一条旧入口。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift:224-290` 的 `FullScreenLyricsView` 是当前真正挂载到 App target 并能运行的全屏渲染器。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj/project.pbxproj` 将 `WindowManager.swift` 与 `LyricsViews.swift` 放入 `SpotifyLyrics` target；目前没有独立的 fullscreen controller、projection 或 contract 文件。

### 1.2 当前实现的功能事实

当前旧路径已经具备：

- 一个懒创建的 `NSWindow` 引用；重复 toggle 不会在同一进程内无限创建窗口。
- `.borderless` 样式和覆盖屏幕的初始 frame。
- `canJoinAllSpaces` 与 `fullScreenAuxiliary` collection behavior。
- 一个右上角关闭按钮；关闭动作再次调用 `toggleFullScreen`。
- 同步歌词时尝试显示 `state.currentLineIndex` 对应的一行；无同步时间轴时使用 `PlainLyricsListView`。
- 共用 `PlaybackState` 对象，因此没有第二个播放器 Provider 或 polling timer。

当前旧路径明确存在的问题：

- `window.level = .modalPanel`，层级过高，与正式辅助歌词窗口的 `.floating` 规则冲突。
- `WindowManager` 直接持有 `NSWindow`，没有专用 `WindowController`、`NSWindowDelegate`、screen observer、关闭生命周期和释放边界。
- 使用 `makeKeyAndOrderFront(nil)`，没有控制是否激活 App 或影响其他 App 焦点。
- 固定使用 `NSScreen.main?.frame`，没有跟随主窗口屏幕、屏幕断开回位、visible/safe area clamp 或屏幕排列变化处理。
- `FullScreenLyricsView` 读取 `state.lyrics`、`state.lyricsState` 的兼容层和 `state.currentLineIndex`，可能把搜索预览或非 live 状态带入辅助窗口；这违反 live-only 边界。
- 直接读取 `state.lyricsAreSynchronized`，没有单独验证时间戳证据；旧数据带有乐观同步标记时可能把零时间第一行当成当前歌词。
- 通过 `LineDisplayView` 和 `PlainLyricsListView` 形成另一套旧渲染器，和现行 `LyricLineView` 的 Ruby、三种假名模式、重复罗马音保护、响应式字号不一致。
- 全屏显示固定 `fontSize: 32` 的临时 `DisplayPreferences`，没有真正复用字号、辅助字号、Ruby 大小、远处辅助层显隐等持久化设置。
- 同步状态只显示单行，没有前后行 projection、前奏无当前行、seek 后定位、暂停动画停止、尾奏状态和候选/失败/加载等完整状态层级。
- 无封面、背景、色板、噪点或 V3 异步缓存；当前运行证据 `ui-reference-audit-assets/spotifylyrics-fullscreen-xcode.png` 显示的是黑色覆盖层、单行蓝色罗马音和关闭按钮，不能作为正式视觉实现。
- 没有鼠标移动控件显隐、自动淡出、Esc 退出、主窗口/悬浮歌词/胶囊/编辑器入口或显式进度 Slider。
- `PlaybackState.showFullScreen` 只是一个公开可变布尔值；`LyricsDisplayMode.fullScreen` 存在，但当前 toggle 没有统一更新 `currentMode`，因此两者不是可靠的全屏状态机。
- 没有全屏专属测试；现有 `/Users/apple/backup/sptifylyrics/Tests/floating_window_behavior_contract.sh` 只要求旧 `FullScreenLyricsView` 保留，属于兼容性保护，不是全屏验收。

### 1.3 当前调用路径中的共享状态事实

`/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/PlaybackState.swift` 已经提供全屏所需的大部分正式接口：

- 只有 `PlaybackState` 持有 `Timer.scheduledTimer`；当前 polling 间隔为 0.2 秒，Spotify 校准间隔为 2 秒。
- `lyricsSession` 和 `translationSession` 在 `PlaybackState` 内只创建一份；session 的 `objectWillChange` 被转发到 `PlaybackState`。
- `liveLyrics` 在 `PlaybackState.projectedLyrics(...)` 中合并当前选定翻译，且已有按 identity、revision、歌词版本、source hash、翻译版本和行数的 projection cache。
- `liveCurrentLineIndex` 使用现有 `LyricsTimeline.activeLineIndex` 二分查找，不需要全屏重复计算。
- `liveLyricsState`、`liveLyricsAreSynchronized`、`liveLyricsSessionRevision` 和 `currentTrackIdentity` 已经隔离搜索预览，适合正式辅助窗口使用。
- 切歌时 `synchronize(with:)` 会先取消排轴和搜索预览，再启动新的歌词 session；`LyricsSessionController` 会清空旧行并递增 revision。
- 翻译、编辑器、TXT/LRC 导入和排轴保存后，`PlaybackState` 会重新投影 session；全屏只需观察同一个 state 即可即时刷新。

因此本阶段优先不修改 `PlaybackState`、`LyricsSessionController` 或 `TranslationSessionController` 的业务逻辑；只有 contract 暴露正式 live projection 不足时，才增加只读 accessor，禁止在全屏 View 中补第二套状态源。

---

## 2. 文件处置审计

| 文件 | 当前角色 | 处置 | 实施时的边界 |
|---|---|---|---|
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift` | 所有辅助窗口的 façade；当前直接创建旧全屏 `NSWindow` | **需要重新接线** | 保留 public toggle/visibility façade；属性改为 `FullScreenLyricsWindowController?`；新 controller 验收通过后删除直接 `NSWindow` 创建代码 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift` | `LineDisplayView`、`PlainLyricsListView`、旧胶囊和旧全屏兼容 View | **全屏旧实现应冻结，验收后删除** | 不在正式 fullscreen path 继续使用 `FullScreenLyricsView`；`LineDisplayView`/`PlainLyricsListView` 若无其他引用再清理，否则先保留为兼容代码 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricLineView.swift` | 当前正式 Ruby、假名替换、罗马音和翻译渲染 | **可直接复用** | 全屏传入动态可用宽度和共享 preferences；不复制 Ruby renderer，不创建全屏专属 UserDefaults |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/FloatingLyricsPresentation.swift` | 悬浮歌词的有限行 projection 规则 | **机制可参考，不直接复用** | 全屏另设自己的 visible range，因为屏幕尺寸、控件和滚动语义不同；仍接收 `liveCurrentLineIndex`，不自行按 time 求 index |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/CapsuleLyricsPresentation.swift` | 胶囊 current/following 与无时间轴 fail-closed 规则 | **可复用纯规则，需抽取共享证据 helper** | 复用“没有 timing evidence 就是纯文本/未排轴”和“前奏无 current”语义；不把胶囊的两行上限照搬到全屏 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Floating/FloatingLyricsView.swift` | 正式悬浮歌词 live-only 状态分支和可见行 projection 示例 | **机制可参考** | 不修改悬浮实现；全屏必须避免引入其独立滚动/窗口状态 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/FloatingLyricsWindowController.swift` | 已验收的 NSPanel、delegate、screen observer、关闭/隐藏生命周期 | **可直接复用架构模式** | 不共享 panel、frame key 或 visibility state；fullscreen 使用独立 controller 和屏幕策略 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/CapsuleLyricsWindowController.swift` | 单例 panel、鼠标/键盘 monitor、生命周期清理的最新模式 | **可直接复用架构模式** | 全屏只复制 monitor/task 清理方法，不复制胶囊的三态尺寸和顶部 frame 算法 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/FloatingLyricsWindowPersistence.swift` | 悬浮窗可调 frame 和屏幕回位 | **不直接复用持久化 key** | fullscreen 不保存普通 frame；可复用 clamp/fallback 思路或抽取无状态 ScreenResolver |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/CapsuleLyricsWindowPersistence.swift` | 胶囊顶部安全区和主窗口屏幕选择 | **可复用 screen resolver 思路** | fullscreen 以完整目标屏幕/安全内容区为目标，不共享 capsule offset 或 frame key |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Settings/WindowStatePersistence.swift` | 主窗口 attach、主窗口 screen anchor、visible frame 和 keep-on-top | **可直接复用 screen anchor** | 不给 fullscreen 新增普通窗口恢复 frame；使用 `attachedMainWindow?.screen → NSScreen.main → NSScreen.screens.first` |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift` | V3 异步封面缩略图、色板、噪点、缓存和 stale-key guard | **可直接复用** | full-screen 用 `.id(identity|artworkURL)` 重置旧视图状态；不按 playback tick 重新生成背景 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/BackdropPalette.swift` | 颜色采样和 actor cache | **可直接复用** | 不新增 fullscreen palette cache，不保存完整封面数据到数据库 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Providers/ArtworkImageLoader.swift` | 共享 artwork URL 内存缓存 | **可直接复用** | 不在全屏再解码一套远程图片；只按 artwork URL 读取共享 cache |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/ArtworkView.swift` | 封面展示和共享 artwork loader | **可直接复用** | 复用现有封面 metadata/URL，不创建全屏封面模型 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift` | V3 主窗口结构、同步滚动和视觉参考 | **仅复用内部组件/规则** | 不把 V3 主窗口作为全屏 root，不改 V3 布局；背景组件单独复用 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift` | 主窗口和现有窗口菜单 | **最小重接线** | 保留现有菜单调用 façade；如需增加 accessibility 或 `open/close` 入口只做最小改动 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Main.swift` | App Scene 和命令菜单 | **需要修改** | 增加明确的显示/隐藏全屏命令和 Esc/快捷键配套入口；不新增第二 Scene 或第二 PlaybackState |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift` | 保留的显示设置与窗口入口 | **最小重接线** | 继续调用 WindowManager façade；状态显示改为 controller 真值后再更新，不复制设置 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Models/Models.swift` | `LyricsDisplayMode.fullScreen` 和共享 Track/LyricLine/DisplayPreferences | **可复用，默认不改** | `showFullScreen` 是辅助窗口可见状态，不把它改造成第二套 mode persistence |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/PlaybackState.swift` | 唯一 playback clock、live session 和 display mirror | **默认不修改** | 若需要只增加只读 live projection；绝不新增 timer、计算器或 fullscreen state copy |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/LyricsSessionController.swift` | 当前歌词版本/identity/revision/取消 | **不修改** | 全屏不直接创建或持有 controller；所有切歌和迟到保护由此处继续负责 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/TranslationSessionController.swift` | 共享翻译版本选择和 projection | **不修改** | 全屏通过 `state.liveLyrics` 显示已选翻译，不直接发请求 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj/project.pbxproj` | App target sources | **需要修改** | 仅加入新的 controller/view/presentation/test harness 文件；不改变现有 target 边界 |
| `/Users/apple/backup/sptifylyrics/Tests/floating_window_behavior_contract.sh` | 悬浮兼容契约 | **需要更新兼容断言** | 新正式 fullscreen 通过后，不再用“旧 FullScreenLyricsView 必须存在”作为长期正式约束；保留直到删除旧代码的同一提交 |

早期 `MockData`、旧 `CapsulePlayerView` 和旧 `FullScreenLyricsView` 不作为正式全屏数据源。Mock Preview 仍由共享 `PlaybackState` 决定是否显示，只能作为明确的预览状态，不得被旧 View 误当真实歌词。

---

## 3. 标准系统全屏 vs 无边框独立全屏

| 方案 | 优点 | 风险/不适配点 | 结论 |
|---|---|---|---|
| 标准 macOS 系统全屏：对主窗口调用 `toggleFullScreen(_:)` | 符合系统窗口语义；系统负责 Space、交通灯和退出；键盘 Esc/绿色按钮行为天然存在 | 会改变主窗口本身的 Space 和生命周期；主窗口、悬浮歌词、胶囊与编辑器的共存关系难以稳定；`WindowGroup` 的真实 NSWindow 获取和恢复时机复杂；全屏退出可能影响主窗口 frame、focus 和设置恢复；不适合作为独立歌词画布 | **不推荐 V1** |
| 无边框独立全屏窗口：专用 `NSPanel` + `NSWindowController`，覆盖目标屏幕 | 不改主窗口；可从同一个 `WindowManager` 显示/隐藏；可精确跟随主窗口 screen、在屏幕断开时回位；能与悬浮/胶囊共存；关闭只 order out，不退出 App；便于 live-only content 和背景缓存 | 需要自己处理 Esc、控件淡入淡出、screen observer、panel 生命周期和非激活行为；必须严格限制 window level 和 monitor | **推荐 V1** |

### 推荐的独立全屏策略

实施时只保留第二种方案，不与系统 `toggleFullScreen` 混用：

1. 新增 `FullScreenLyricsWindowController`，内部只保留一个 `FullScreenLyricsPanel`。
2. panel 使用 `.borderless` + `.nonactivatingPanel`，`isReleasedWhenClosed = false`，`hidesOnDeactivate = false`，`canBecomeMain = false`；显式控件交互需要时才允许成为 key，不在 show 时强制激活其他 App。
3. `level = .floating`，不使用 `.modalPanel`/`.statusBar`；`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`。
4. `show` 使用 `orderFrontRegardless()`，不使用无条件 `makeKeyAndOrderFront(nil)`；只有用户明确操作全屏控件时才让 SpotifyLyrics 接收必要的键盘焦点。
5. panel frame 覆盖目标 `NSScreen.frame`；内容通过 safe-area/可见区域 inset 放置顶部工具、封面和歌词，避免菜单栏/刘海区域造成遮挡。系统警告、菜单和安全界面不由本窗口抢占。
6. 不保存全屏普通 frame，也不新增全屏显示器设置；每次显示按当前目标屏幕重新计算，关闭时只保留 transient `showFullScreen` 为 false。

---

## 4. 推荐 WindowController 与状态机

### 4.1 控制器接口

计划新增：

`/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/FullScreenLyricsWindowController.swift`

```swift
@MainActor
final class FullScreenLyricsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false
    @Published private(set) var controlsVisible = false

    func toggle(state: PlaybackState)
    func show(state: PlaybackState)
    func hide()
    func toggleControls()
    func revealControls()
    func scheduleControlsHide()
}
```

控制器职责只有：

- 延迟创建并长期保留一个 `FullScreenLyricsPanel`；
- 注入同一个 `PlaybackState` 和 controller 自身到 `FullScreenLyricsView`；
- 管理 show/hide、delegate、Esc、鼠标控件显隐和屏幕 observer；
- 在 `windowWillClose`、`hide`、`deinit` 时取消 monitor/task，清理引用并同步 `state.showFullScreen`；
- 不读取歌词 Provider，不调用 `LyricsSessionController`，不计算当前行，不持有翻译版本。

### 4.2 WindowManager 接线

修改 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift`：

- `private var fullScreenWindow: NSWindow?` 改为 `private var fullScreenController: FullScreenLyricsWindowController?`。
- `toggleFullScreen(state:)` 只负责 lazy 创建 controller 并转发 `toggle`。
- 增加 `showFullScreen(state:)`、`hideFullScreen()`、`fullScreenWindowIsVisible`，供菜单、测试和其他窗口入口使用。
- controller 完全验收后，删除旧的 `NSWindow(contentRect:...)`、`.modalPanel` 和 `FullScreenLyricsView().environmentObject(state)` 直接创建路径。
- 不修改 floating/capsule controller 的 panel、frame key 或 visibility state；三者只由同一个 façade 管理但互不互斥。

### 4.3 可见性状态

全屏 V1 不新增第二个全局 AppMode。状态分为：

```text
hidden
  └─ show/toggle → visible(content)
        ├─ controlsVisible（鼠标移动/明确操作后临时）
        └─ controlsHidden（约 3 秒无操作后淡出）
  └─ Esc / 菜单 / 关闭按钮 → hidden
```

`controlsVisible` 不是歌词模式，不写入 UserDefaults，不影响 `currentMode`，不改变播放状态。窗口重启不自动恢复全屏；`restoreWindowState` 继续只作用于已经存在的窗口恢复约定，不新增 `fullScreenWasVisible`。

---

## 5. 屏幕、Space 和生命周期方案

### 5.1 目标屏幕

默认解析顺序：

```text
WindowStatePersistence.shared.attachedMainWindow?.screen
→ NSScreen.main
→ NSScreen.screens.first
```

理由：全屏是从主窗口发起的歌词辅助窗口，优先跟随主窗口所在显示器；主窗口暂不可用时才使用系统当前屏幕，不额外增加显示器选择设置。

### 5.2 屏幕变化

controller 订阅 `NSApplication.didChangeScreenParametersNotification`，只在窗口可见时执行：

- 目标屏幕仍存在：重新把 panel frame 设为该屏幕 frame，并让内容 safe area 重新布局；
- 目标屏幕消失：切到主窗口当前 screen，再回退 `NSScreen.main`/首屏；
- 屏幕排列和缩放变化：不保留旧坐标，重新按 screen frame 计算，不允许负尺寸或屏外窗口；
- 主窗口移动到另一屏：在下一次屏幕参数变化或明确重新显示时跟随主窗口，保持与胶囊相同的用户直觉；
- 物理多屏若当前环境无法实测，必须用纯 screen resolver/clamp contract 覆盖并报告 `UNVERIFIED`。

### 5.3 Space 与退出

- `canJoinAllSpaces` 使窗口可见性跨 Space；`fullScreenAuxiliary` 允许在其他 App 的系统全屏内容上作为辅助内容显示。
- 不调用主窗口 `toggleFullScreen`，不创建新的系统全屏 Space。
- Esc 只隐藏全屏歌词，不退出 App、不关闭悬浮歌词、不关闭胶囊、不改变 Spotify 播放。
- 菜单命令和主窗口窗口模式菜单都能重新显示；关闭按钮同样只 `hide`。
- 重复 show/hide 使用同一个 controller/panel，不创建多个 NSWindow 或 SwiftUI state tree。

---

## 6. 共享 Playback / Lyrics / Translation 接线

计划新增：

`/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Fullscreen/FullScreenLyricsView.swift`

根 View 只接受：

```swift
struct FullScreenLyricsView: View {
    @ObservedObject var state: PlaybackState
    @ObservedObject var windowController: FullScreenLyricsWindowController
}
```

正式读取清单：

| 需求 | 唯一来源 |
|---|---|
| 当前歌曲标题/艺人/专辑/封面 | `state.currentTrack`，并以 `state.hasLiveTrack` 判断是否有效 |
| 当前 TrackIdentity | `state.currentTrackIdentity` |
| 当前歌词行 | `state.liveLyrics` |
| 歌词状态 | `state.liveLyricsState` |
| 是否有可靠同步标记 | `state.liveLyricsAreSynchronized`，同时进行 timing evidence fail-closed 检查 |
| 当前行 | `state.liveCurrentLineIndex`，全屏不再按 `currentTime` 建立第二套 index |
| 播放位置/暂停 | `state.currentTime`、`state.isPlaying` |
| 原文/Ruby/假名/罗马音/翻译 | `state.liveLyrics` 已经由 shared `TranslationSessionController.project` 合并，显示层由 `state.preferences` 控制 |
| 播放控制/显式 seek | `state.togglePlayPause()`、`previousTrack()`、`nextTrack()`、`seek(to:source:)` |
| 版本/编辑/翻译/排轴变化 | `PlaybackState` 转发的 `objectWillChange` 与 `liveLyricsSessionRevision` |

禁止：

- `FullScreenLyricsView` 持有 `LyricsSessionController` 或 `TranslationSessionController`；
- 直接调用 Provider、AI service、repository 或 `LyricsSearchManager`；
- 读取 `state.lyrics`/`state.lyricsState`/`state.currentLineIndex`；
- 在 View 或 controller 内启动 `Timer`；
- 将搜索预览 `searchPreviewSession` 的内容投影到全屏；
- 为全屏增加新的 `@AppStorage`/UserDefaults key。

当 `state.currentTrackIdentity` 变化或 `hasLiveTrack` 变为 false 时，fullscreen content 使用 identity/revision key 立即清空旧歌曲的歌词、翻译、封面和背景引用；新 session 结果只能由 PlaybackState 的既有 revision guard 写入。

---

## 7. 同步与纯文本展示策略

计划新增：

`/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/FullScreenLyricsPresentation.swift`

它是纯值 projection，不拥有时钟，输入当前共享 index，输出渲染所需范围：

```swift
enum FullScreenLyricsSurface: Equatable, Sendable {
    case loading(String)
    case synchronized(currentIndex: Int?, visibleIndices: [Int])
    case plainText(status: String, visibleIndices: [Int])
    case status(title: String, detail: String)
    case candidates
    case failed(String)
}

static func surface(
    lines: [LyricLine],
    state: LyricsLoadState,
    isSynchronized: Bool,
    currentIndex: Int?,
    visibleRowBudget: Int
) -> FullScreenLyricsSurface
```

### 7.1 synchronized

- 只有 `.loaded` 且 timing evidence 存在、`liveLyricsAreSynchronized == true` 时进入同步表面。
- `currentIndex` 直接来自 `state.liveCurrentLineIndex`；不能由全屏用 `currentTime` 另算。
- 有当前行时只渲染当前行附近 projection，默认前 2 行、后 3 行；窗口高度变化时根据固定 row budget 调整，不一次创建整份文档。
- 播放前奏、第一条有效 timestamp 之前：`currentIndex == nil`，显示开头附近歌词但不高亮、不自动滚到第一句、不显示“当前句”。
- 当前行居中锚定约 48% 高度；开头和结尾由 `ScrollViewReader` 自然 clamp，不制造空白大跳。
- 当前行清晰、邻近行可读、远处行只做克制 opacity/轻微 blur；具体文字层直接复用 `LyricLineView`、Ruby token、共享 display preferences。
- 暂停时不启动/继续全屏动画；当前行仍保持可见。seek 后由共享 `currentTime` 和现有 `liveCurrentLineIndex` 立即更新 projection。
- 默认不让点击歌词行 seek；只有显式进度 Slider 或未来明确标记为“跳转到此行”的操作才调用 `state.seek`。

### 7.2 plain text / 未排轴

以下全部采用自然全文阅读：

- `alignmentQueued`
- `alignmentRunning`
- 未确认 `alignmentPreview`
- `.loaded` 但没有任何有效 timestamp/endTime evidence

行为：

- 顶部或底部显示小型“纯文本 / 未排轴”状态，不占据画布中心；
- `LazyVStack` 保留全部行的可手动滚动能力；
- 所有行使用相同的普通层级，不设置 current、distance opacity、自动滚动或平均时间；
- 不把第一行作为播放中的当前句；
- 采用并保存 automaticAlignment 子版本后，live session 更新为 synchronized，下一次 View 状态变化自动切换同步表面。

### 7.3 loading/no lyrics/candidates/failed/track transition

- `loading`：显示歌曲 metadata 或轻量加载状态，不保留上一首歌词。
- `noLyrics`/`noMatch`：显示无歌词状态；如果可创建人工歌词，只提供返回主窗口/编辑入口，不在全屏复制候选和导入流程。
- `candidates`：只显示“请回主窗口选择歌词候选”，不在全屏显示第二套候选选择器。
- `failed`：显示错误分类和“回主窗口重试”提示，不让失败覆盖已有锁定版本。
- `hasLiveTrack == false` 或 identity transition：先清空内容，再显示“正在切换歌曲/等待 Spotify”，不得继续显示 A 歌的标题、封面或翻译。
- Mock Preview 若被用户明确开启，只显示“Mock Preview”状态；不把它当作商业歌曲验收证据。

---

## 8. 显示层、封面和背景管线

### 8.1 显示层

不新增 fullscreen preferences。`FullScreenLyricsView` 通过 `LyricLineView` 使用现有：

- 原文开关；
- 翻译开关；
- 罗马音开关；
- `KanaDisplayMode.independentLine`；
- `KanaDisplayMode.inlineRuby`；
- `KanaDisplayMode.kanaReplacement`；
- Ruby 大小、辅助字号、当前字号和 distant auxiliary 隐藏规则。

宽度策略：

- 计算可用内容宽度，作为 `LyricLineView.availableWidth`；
- 根据窗口宽度、当前文本长度和启用层数使用既有 `LyricsDesignTokens` 动态字号；
- 长句允许换行，不把原文、Ruby、罗马音和翻译压到不可读的小字号；
- Ruby 继续走 `RubyTokenFlowLayout` 的 overhang/last baseline 逻辑；不重新实现注音排版；
- full-screen 只增加一个 renderer context 或 token 调整时，必须扩展现有 `LyricLineView`/`LyricsDesignTokens`，不复制另一套 `LineDisplayView`。

### 8.2 背景复用

全屏根 View 直接使用：

```swift
AppleMusicImmersiveV3BackdropView(
    track: state.currentTrack,
    identity: state.currentTrackIdentity
)
.id("fullscreen|\(identityKey)|\(artworkURL)")
```

复用范围：

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Providers/ArtworkImageLoader.swift` 的 artwork URL 内存缓存；
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/BackdropPalette.swift` 的异步色板 actor cache；
- `AppleMusicImmersiveV3BackdropCache` 的 320px 缩略图、程序噪点、主色渐变、局部柔光、暗幕和暗角；
- identity/artwork key 的取消与 stale-return guard。

切歌时使用 fullscreen identity key 重新挂载 backdrop，使旧 `@State` 和 outgoing artwork 不进入新歌曲；播放进度不参与 key，播放 tick 不触发图片解码、色板提取或高半径 blur。

封面展示复用 `ArtworkView`；封面 URL、Track metadata 和背景 key 均来自当前 `Track`，不得缓存独立的 fullscreen Track 副本。

---

## 9. 播放控制、鼠标和键盘交互

计划在 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Fullscreen/FullScreenLyricsView.swift` 内放置一组克制的 overlay controls：

- 顶部：关闭/退出全屏、打开主窗口、设置入口；
- 底部：上一首、播放/暂停、下一首、显式播放 Slider、时间文字；
- 可选入口：打开悬浮歌词、编辑当前歌词；只调用 `WindowManager`/现有 `PlaybackState`，不创建新窗口状态；
- 不在 V1 增加音量控制；音量需要独立 provider API 和权限体验，列入产品决定而不是隐藏的半成品。

行为规则：

- `onContinuousHover`/controller `revealControls()` 显示 controls；约 3 秒无鼠标移动后通过 cancellable `Task.sleep` 淡出；不使用重复 playback Timer。
- 鼠标移动、进入/退出、点击关闭、打开主窗口和展开控件不得 seek。
- Slider 使用 `draftPosition`：拖动中只改变本地临时 thumb；`onEditingChanged(false)` 时才调用 `state.seek(to:source: "fullscreen-slider")`；普通 tick 只更新显示值。
- 播放按钮只调用共享 `togglePlayPause`；上一首/下一首只调用共享 provider command；不做长期乐观状态覆盖。
- 默认歌词行不是 Button；点击歌词不会 seek。若未来增加“跳转到该行”，必须是显式按钮/菜单并使用既有 `LyricsTimeline.validSeekTimestamp`。
- Esc 只调用 `controller.hide()`；重复 Esc 安全无副作用；不退出 App、不关闭主窗口、不改变 Spotify 播放。
- 菜单增加“显示/隐藏全屏歌词”命令和稳定快捷键；主窗口菜单、V3 toolbar、显示设置入口都调用同一个 `WindowManager` façade。
- 全屏显示期间主窗口、悬浮歌词和顶部胶囊默认仍可同时存在；它们各自有 controller/panel/visibility，不互相 order out、不共享 frame key。

---

## 10. 性能和生命周期方案

### 10.1 播放 tick 与歌词 projection

- 不添加任何 Timer；0.2 秒 tick 仍只有 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/PlaybackState.swift` 一处。
- `state.liveLyrics` 使用 PlaybackState 已有 projection cache；全屏不复制数组、不再合并翻译。
- `FullScreenLyricsPresentation` 只接收共享 `liveCurrentLineIndex`，不会在 full-screen 中按 time 排序或二分搜索。
- 同步表面仅使用当前行附近的 stable `LyricLine.id`；长歌词文档使用 `LazyVStack` 和 `ScrollViewReader`，避免每个 tick 重建整份文档。
- `currentTime` 变化只触发当前行/Slider 相关的小区域刷新；滚动只在 current index 变化时发生，使用 `lastScrolledLineIndex` 去重。
- lyrics session revision、选定翻译版本、source content hash、display preference 或 identity 变化时才重建行 projection；播放位置变化不重建背景/metadata。

### 10.2 背景和文本布局

- artwork/background 任务只以 identity + artwork URL 为 key；V3 cache actor 合并同 key in-flight 请求。
- background view 在 hidden 时不启动新加载任务；显示后按当前 key 恢复。没有每秒 blur、palette 或 image decode。
- Ruby、罗马音和翻译直接使用现有 row layout；如果新增 full-screen context，缓存键必须包含 lyric line id、可用宽度、显示层数和字号，而不是 currentTime。
- 远处行使用 opacity/轻微 blur 的既有规则，不创建无限循环动画。

### 10.3 controller、monitor 和 task 清理

- `FullScreenLyricsWindowController` 强持有 panel，panel 的 root view 弱/观察共享 state；不让 state 反向强持有 controller。
- `NSWindowDelegate`、screen parameter observer、local key monitor、hover-hide task 都由 controller 保存并在 `hide`/`deinit` 对称清理。
- `NSHostingView` root view 只创建一次；重复 show 不创建第二个 View tree。
- window close 被转成 hide；关闭 fullscreen 不释放 `PlaybackState`、不退出 App、不关闭其他辅助窗口。
- 隐藏后取消 controls-hide task、停止 ScrollView 自动动画和短期 transition；无需取消共享 PlaybackState timer。
- contract 通过 `deinit`/observer-count、single controller、single panel 和 no-second-timer 静态/纯逻辑断言；无法在当前环境观察的 WindowServer 细节标记为 `UNVERIFIED`。

---

## 11. 拟新增和修改文件

### 新增

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/FullScreenLyricsWindowController.swift`：单例 panel、delegate、show/hide、Esc、screen observer、controls lifecycle。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Fullscreen/FullScreenLyricsView.swift`：V1 全屏画布、V3 背景、metadata、live-only lyric surface、controls overlay。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/FullScreenLyricsPresentation.swift`：纯 projection/status/timing-evidence 规则，不持有时钟或 session。
- `/Users/apple/backup/sptifylyrics/Tests/fullscreen_lyrics_contract.sh`：target/source/live-only/no-second-clock 静态契约。
- `/Users/apple/backup/sptifylyrics/Tests/fullscreen_lyrics_presentation_test.swift`：同步、前奏、纯文本、状态和可见范围的纯 Foundation 契约。
- `/Users/apple/backup/sptifylyrics/Tests/fullscreen_window_behavior_contract.sh`：单例 panel、层级、screen fallback、Esc、关闭和无隐式 seek 契约。

### 修改

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift`：旧直接 NSWindow path → `FullScreenLyricsWindowController` façade。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Main.swift`：增加全屏显示/隐藏命令和快捷键，复用已有 `playbackState`。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift`：只在必要时同步 accessibility/入口状态，保留现有 V2/V3 视觉。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`：只在必要时让 toolbar 入口读取 controller 真值，不重做 V3。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift`：保留入口，去除对旧全屏实现细节的依赖。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricLineView.swift` 或 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/LyricsDesignTokens.swift`：仅在全屏动态字号/宽度 contract 证明现有接口不足时，增加共享 presentation context；不加入全屏专属字号设置。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj/project.pbxproj`：加入上述新增 target source/test harness。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift`：新路径验收后删除旧 `FullScreenLyricsView`；保留仍有调用者的兼容渲染器，或者在同一提交中一并删除已无引用的旧 helper。
- `/Users/apple/backup/sptifylyrics/Tests/floating_window_behavior_contract.sh`：从“旧 FullScreenLyricsView 必须存在”过渡到“旧直接入口不存在、新 controller 存在”的最终断言。

明确不修改：

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/PlaybackState.swift` 的 timer/provider/session 业务路径；
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/LyricsSessionController.swift`；
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/TranslationSessionController.swift`；
- Provider、QueryPlanner、SafeMatcher、SQLite schema、AI HTTP、自动排轴和其他窗口的正式视觉。

---

## 12. 合同测试与真实验收矩阵

### 12.1 合同测试

实施顺序采用红-绿：先让新合同在缺少 controller/view 时失败，再实现最小代码。合同至少覆盖：

| 契约 | 验证内容 |
|---|---|
| 单例与 target | `WindowManager` 只有一个 fullscreen controller；新 panel/view/presentation 进入 `SpotifyLyrics` target；旧直接 `NSWindow` 创建和 `.modalPanel` 消失 |
| 共享数据 | FullScreen View 使用 `liveLyrics`、`liveLyricsState`、`liveCurrentLineIndex`、`currentTrackIdentity`；不得出现 `state.lyrics`、第二 Provider/session/TranslationController/Timer |
| timing fail-closed | 零时间/无时间轴/`alignmentQueued`/`alignmentRunning`/未确认 preview 不产生 current index、自动滚动或第一行高亮 |
| synchronized projection | 前奏 current 为 nil；时间进入有效行后 current/前后 visible indices 正确；窗口预算改变不破坏稳定行 id |
| plain text | 全文可滚动、没有 distance opacity/自动滚动/平均分配；状态文本为“纯文本/未排轴”或等价语义 |
| state coverage | loading、noLyrics、noMatch、candidates、failed、track transition 均清空旧歌词并显示克制状态；candidates 只提示回主窗口 |
| live-only stale guard | 搜索预览不能进入全屏；identity/revision 切换后旧 session/翻译/封面结果不能回写 |
| display settings | 原文、翻译、罗马音、三种假名模式、Ruby/assistant size 和 distant auxiliary 均读取现有 `AppSettingsStore`，不出现新的持久化 key |
| controls | 播放/暂停/上一首/下一首复用 `PlaybackState`；Slider 只有结束拖动才 seek；打开/关闭/hover/点击歌词/拖动窗口不 seek |
| lifecycle | show/hide/reopen 使用一个 panel；delegate、screen observer、key monitor、hide task 对称清理；关闭不退出 App、不关闭 floating/capsule |
| window safety | `.floating`、`canJoinAllSpaces`、`fullScreenAuxiliary`、screen fallback/clamp；没有 `.statusBar`/`.modalPanel`；Esc 和菜单均可恢复 |
| background | V3 cache/artwork loader 被复用；key 包含 identity/artwork，不包含 currentTime；旧背景在 identity 变化时不显示为新歌曲当前背景 |
| no second clock | `PlaybackState.swift` 仍只有一处 `Timer.scheduledTimer`；fullscreen sources 不包含 Timer/provider/session creation |

执行阶段将把以上 contract 纳入现有 `Tests/*.sh` 回归，不把截图或合同静态通过当作真实歌曲完成证明。

### 12.2 真实 App 验收

使用正常签名 Debug App 和 Spotify Desktop，必须记录当前 App 绝对路径、HEAD、进程来源和每个场景结果；不需要在计划阶段构建。

| 场景 | 操作 | 必须观察到 |
|---|---|---|
| 恋風 / Lilas | 42 行同步歌词；显示原文、Ruby、罗马音、翻译；暂停/恢复/seek/切歌 | current/next 与共享播放位置一致；暂停不继续滚动；seek 后立即定位；切换显示层不丢翻译或 session |
| 水曜日の約束 / Kawasaki.Rio：纯文本 | 选中 QQ 32 行纯文本版本 | 只显示全文和“纯文本/未排轴”；不显示第一行 current，不按 2:51 平均切行 |
| 水曜日の約束：同步子版本 | 选择已有同步子版本 | 自动切换 synchronized；current 行来自共享 `liveCurrentLineIndex`，不是 fullscreen 自己计时 |
| あやふや / みさき | noMatch | 全屏不残留水曜日的标题、封面、背景、歌词或翻译；显示无歌词/noMatch 状态 |
| 人工导入/编辑 | 保存 TXT/LRC/manualEdit 后不关闭全屏 | 全屏从共享 session 立即刷新；source/纯文本状态和锁定结果正确 |
| automaticAlignment | 采用已确认的排轴子版本 | 全屏进入同步模式；不生成自己的时间轴、不改变 Spotify position |
| 快速 A→B→A | 连续切歌并让 Provider/翻译延迟返回 | 不闪回 A/B 的旧歌词、翻译、封面或背景；最终 A 状态来自 A 的当前 revision |
| 多窗口 | 主窗口、悬浮歌词、顶部胶囊、全屏同时打开 | 四者显示同一 live track/session/translation/settings；没有第二 polling timer；退出全屏不关闭其他窗口 |
| 播放控制 | 在全屏点击播放、上一首、下一首和 Slider | 调用共享 PlaybackProvider；普通 tick 不 seek；Slider 只在完成拖动时 seek |
| 控件生命周期 | 鼠标移入、停留、移出；点击 outside；Esc；反复打开关闭 | controls 约 3 秒淡出；Esc/菜单可靠退出；没有多个 panel 或残留 monitor |
| 屏幕/Space | 主窗口所在屏幕切换、进入其他 Space、屏幕失效 | 遵循目标屏幕和 fallback；窗口可见、不出屏、不抢系统警告；无法物理验证的部分标记 `UNVERIFIED` |

真实商业歌曲自动排轴的真实性仍以现有 alignment V1 规则为准；本阶段只消费已存在的时间轴，不把任何合成音频、Mock 或旧截图当作排轴证据。

---

## 13. 需要用户决定的产品行为

以下不是代码缺口，而是实施前需要确认的产品边界；每项都给出推荐默认值：

1. **全屏实现方案：** 推荐无边框独立 `NSPanel`；不采用系统 `toggleFullScreen`，也不混用两套实现。
2. **目标屏幕：** 推荐跟随主窗口所在屏幕；主窗口不可用时 `NSScreen.main`，再回退首屏；本轮不新增显示器选择设置。
3. **覆盖范围：** 推荐 panel 覆盖目标 `screen.frame`，内容控件遵守 safe area；若产品更重视不遮菜单，也可以选择 `visibleFrame`，但视觉上会保留菜单栏高度的边界。
4. **多窗口共存：** 推荐全屏显示时不自动关闭悬浮歌词、顶部胶囊或主窗口；它们可能被全屏画布遮住，但 controller 和状态继续存活，退出全屏后立即恢复。
5. **启动恢复：** 推荐 App 重启不自动恢复全屏，避免启动时抢占屏幕；`restoreWindowState` 不新增 fullscreen visibility key。
6. **控件淡出：** 推荐鼠标无操作约 3 秒后淡出，鼠标移动立即显示；控件显隐不影响歌词状态。
7. **Esc 行为：** 推荐只隐藏全屏歌词，不退出 App、不暂停 Spotify、不关闭其他窗口。
8. **全屏音量：** 推荐 V1 不加入音量控制，沿用现有播放/seek 控件；待 PlaybackProvider 有稳定音量 API 后另行评估。
9. **点击歌词：** 推荐默认不 seek；只提供 Slider 的明确 seek，避免浏览歌词时误跳播放位置。
10. **键盘快捷键：** 推荐加入一个窗口菜单快捷键与 Esc；快捷键由实现时避开现有悬浮歌词 `⌘⌥F`，避免同键冲突。若用户希望固定快捷键，需要在确认时指定。

---

## 14. 实施顺序和完成门槛

### Task 1: 冻结旧路径并写红色合同

**Files:**
- Create: `/Users/apple/backup/sptifylyrics/Tests/fullscreen_lyrics_contract.sh`
- Create: `/Users/apple/backup/sptifylyrics/Tests/fullscreen_lyrics_presentation_test.swift`
- Create: `/Users/apple/backup/sptifylyrics/Tests/fullscreen_window_behavior_contract.sh`
- Test only: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift`, `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift`

**Steps:**

- [ ] 写入 live-only、单 controller、无 modalPanel、无第二 Timer、纯文本不伪同步和旧入口消失的红色断言。
- [ ] 用当前旧代码运行并确认至少在缺少新 controller/presentation 或检测到 `.modalPanel` 时失败；记录红灯原因，不用静态替换绕过。
- [ ] 对纯逻辑 projection 编写前奏、同步、纯文本、无 timing evidence、状态和 stable index 测试。

### Task 2: 实现纯 projection 和正式 View

**Files:**
- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/FullScreenLyricsPresentation.swift`
- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Fullscreen/FullScreenLyricsView.swift`
- Modify only if needed: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricLineView.swift`, `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Design/LyricsDesignTokens.swift`

**Interfaces:**

- `FullScreenLyricsPresentation.surface(...)` 接收共享 live state 和当前 index，不接收 PlaybackProvider 或 timer。
- `FullScreenLyricsView` 接收 `PlaybackState` 和 `FullScreenLyricsWindowController`，只使用 live-only accessor。

**Steps:**

- [ ] 先实现 timing evidence 和状态映射，保证 plain/alignmentQueued/alignmentPreview 不进入同步 surface。
- [ ] 使用现有 `LyricLineView`、Ruby token 和 `DisplayPreferences`，实现同步邻近行 projection、纯文本全文滚动和克制 status。
- [ ] 接入 `AppleMusicImmersiveV3BackdropView`、`ArtworkView`、metadata 和动态控件；用 identity/artwork `.id` 清理旧背景。
- [ ] 用 `onChange(currentTime)` 只重试当前行 scroll target，用 `lastScrolledLineIndex` 去重；不新增时钟。
- [ ] 让测试从红色 projection contract 变绿。

### Task 3: 实现单例 NSPanel controller 和 screen lifecycle

**Files:**
- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/FullScreenLyricsWindowController.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift`
- Reuse: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Settings/WindowStatePersistence.swift`

**Interfaces:**

- controller 的 `toggle/show/hide` 均接收共享 `PlaybackState`；controller 不创建任何 Provider/session/translation/timer。
- controller 对外只发布 `isVisible`、`controlsVisible`，不发布歌词副本或 current index。

**Steps:**

- [ ] 写 `FullScreenLyricsPanel` 和固定单例 controller；配置 `.floating`、Space behavior、delegate、nonactivating 和 retained lifecycle。
- [ ] 实现 main-window screen → NSScreen fallback、screen frame/safe area、屏幕失效回位和 screen observer。
- [ ] 实现 Esc、menu/close hide、hover controls task、monitor/task 对称清理。
- [ ] 用 `state.showFullScreen` 兼容现有 popover 状态，但不新增持久化 key。
- [ ] 让 window behavior contract 变绿。

### Task 4: 接入入口并删除旧正式路径

**Files:**
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Main.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj/project.pbxproj`

**Steps:**

- [ ] 所有入口统一调用 `WindowManager` 新 façade；增加无冲突菜单快捷键。
- [ ] 删除旧 `WindowManager.fullScreenWindow` 直接创建路径和旧 `FullScreenLyricsView` 正式挂载。
- [ ] 静态搜索确认 App target 中只剩一条 fullscreen NSPanel/window creation path；保留的旧 helper 必须无正式引用并标记兼容/冻结。
- [ ] 更新旧 floating regression contract，避免它继续强制旧全屏 View 存在。

### Task 5: 完整回归和真实运行门槛

**Files:**
- Modify: `/Users/apple/backup/sptifylyrics/Tests/fullscreen_lyrics_contract.sh`
- Modify: `/Users/apple/backup/sptifylyrics/Tests/fullscreen_window_behavior_contract.sh`
- Add acceptance notes under: `/Users/apple/backup/sptifylyrics/docs/superpowers/specs/acceptance-2026-08-01-fullscreen-lyrics-final-v1/`

**Steps:**

- [ ] 运行新增 fullscreen contracts、现有 lyrics/SQLite/translation/editor/alignment/floating/capsule/search contracts 和 `git diff --check`。
- [ ] 清理并正常签名 Debug 构建，验证 `codesign --verify --deep --strict`，确认进程来自 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`。
- [ ] 按恋風、水曜日两种歌词版本、あやふや、人工编辑/导入、排轴子版本、A→B→A、多窗口和播放控制矩阵进行真实 App 验收。
- [ ] 物理多屏、屏幕排列、Space 和屏幕拔出无法实测时，保留模拟合同并在报告中明确 `UNVERIFIED`，不得写成 PASS。
- [ ] 所有完成门槛通过后才删除旧路径并提交一个独立 commit；本计划阶段不提交。

## 当前审计结论

当前全屏功能是“已写源码、已进入 App target、已有真实菜单入口、但仍是旧实验/兼容实现”；不能认定为正式全屏最终版。最小安全路线是：复用现有 shared live projection、现有 V3 background cache、现有 `LyricLineView` 和已验收的 WindowController 生命周期模式，新增一个独立 fullscreen controller/view/presentation，再删除旧的直接 `NSWindow` 路径。
