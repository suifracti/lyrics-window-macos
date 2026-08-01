# 顶部胶囊最终版 V1 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有顶部胶囊从直接创建的旧 `NSWindow` 升级为一个复用共享播放/歌词/翻译状态的单例 `NSPanel`，支持收起、Hover 轻展开和明确展开三种状态，同时不建立第二套播放器或歌词状态链。

**Architecture:** 保留 `WindowManager.shared` 作为窗口总入口，新增独立的 `CapsuleLyricsWindowController`、`CapsuleLyricsPanel` 和轻量 `CapsuleLyricsView`。胶囊只读取 `PlaybackState` 的 live track、live lyrics projection、共享当前行和 `AppSettingsStore`；状态机、窗口 frame 和屏幕回位属于胶囊自身，但播放时钟、歌词会话、翻译会话和显示偏好不复制。

**Tech Stack:** SwiftUI、AppKit `NSPanel`/`NSWindowDelegate`、Combine/Observation、现有 `PlaybackState`、`LyricsSessionController`、`TranslationSessionController`、`ArtworkView`、`LyricLineView`、Xcode macOS 14 target。

## Global Constraints

- 只修改顶部胶囊正式路径；不修改悬浮歌词视觉/业务、不重做 V2/V3 主窗口、不新增 Provider、AI、QueryPlanner、SafeMatcher、自动排轴或数据库 migration。
- 胶囊必须复用 `PlaybackState → LyricsSessionController → TranslationSessionController`，不得创建第二个 Spotify polling timer、歌词搜索、歌词缓存、当前行计算或翻译状态。
- 搜索预览不得泄漏到胶囊；胶囊只能消费当前 live session，不读取会被搜索预览替换的 `PlaybackState.lyrics` 投影。
- 不使用高于 `.floating` 的窗口层级；不得使用 `.statusBar`、`.modalPanel` 或抢占系统安全界面的层级。
- 胶囊关闭/隐藏不退出 App；同一时刻只能有一个胶囊 panel；Controller、panel、事件 monitor 和 async task 都必须可以释放。
- 纯文本歌词不得显示第一行作为伪当前行，不按总时长切换，不自动滚动；同步歌词才显示当前行/下一行。
- 所有新增文件必须加入 `SpotifyLyrics` target；不把 DerivedData、测试数据库、token 或完整歌词正文写入提交。

---

## 1. 现有实现审计

### 当前真实调用路径

```text
SpotifyLyricsApp
  └─ @StateObject PlaybackState(settings: AppSettingsStore.shared)
       └─ MainLyricsWindowView / AppleMusicImmersiveV3WindowView
            ├─ windowModeMenu → WindowManager.shared.toggleCapsulePlayer(state:)
            └─ LyricsPreferencesPopover → 同一入口
                 └─ WindowManager.capsuleWindow: NSWindow?
                      └─ NSHostingView(CapsulePlayerView().environmentObject(state))
```

`CapsulePlayerView` 当前读取：

- `state.currentTrack.title` 和 `state.currentTrack.artworkName`；
- `state.currentLineIndex`、`state.lyrics`、`state.lyricsAreSynchronized`；
- `state.isPlaying`；
- `state.togglePlayPause()`。

播放位置和歌词当前行实际由 `PlaybackState` 的唯一 `Timer.scheduledTimer`、provider anchor 和 `LyricsTimeline.activeLineIndex` 驱动。胶囊没有第二个 timer，但它目前读取的 `state.lyrics` 可能在搜索预览期间切换到 preview session，不符合正式胶囊的 live-only 边界。

### 文件逐项结论

| 文件 | 当前用途 | 结论 |
|---|---|---|
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift` | 直接创建并持有 `capsuleWindow: NSWindow?`，固定 380×46，定位 `NSScreen.main.visibleFrame` 顶部 | **需要重新接线**：保留统一入口，改为持有独立 `CapsuleLyricsWindowController`；不与悬浮 controller 共用 frame 或 panel |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift` | `CapsulePlayerView` 旧胶囊；同时包含 `LineDisplayView`、`PlainLyricsListView`、全屏/兼容渲染器 | `LineDisplayView` 等共用组件**可保留**；旧 `CapsulePlayerView` **冻结为 legacy，完成新路径后删除或仅保留无引用兼容标记**，不得继续作为正式入口 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/PlaybackState.swift` | 唯一播放状态、timer、provider 命令、live/preview lyrics projection、`showCapsulePlayer` | **直接复用**；仅在实现阶段必要时增加 capsule 的纯 projection 访问器，不增加 timer 或第二次当前行计算 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/LyricsSessionController.swift` | 当前歌词版本、identity、revision、时间轴、切歌/取消/迟到结果保护 | **直接复用，不改职责** |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/TranslationSessionController.swift` | AI/已有翻译版本选择、锁定、source hash 校验和 projection | **直接复用，不让 View 直接调用 repository** |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Settings/AppSettingsStore.swift` | 现有显示偏好、窗口恢复设置和共享 UserDefaults | **需要小幅扩展**：加入胶囊专用 frame/screen/visible keys；不新增 Settings store，不立即增加用户可见显示器选择项 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift` | 主窗口模式菜单，当前直接调用 `toggleCapsulePlayer` | **保留入口，重接 WindowManager facade**；启动 task 增加恢复胶囊的调用，但只在持久化为可恢复显示时执行 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift` | V3 工具菜单中的顶部胶囊入口 | **保留入口，重接同一 facade**；不改 V3 视觉和歌词布局 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift` | 设置 popover 中的顶部胶囊按钮 | **直接复用入口**；按钮状态继续绑定共享 `showCapsulePlayer`，不复制偏好 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/ArtworkView.swift` | 共享 artwork URL 加载、缓存、fallback | **直接复用**；胶囊不重新下载或解码封面 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Providers/ArtworkImageLoader.swift` | 共享 `NSCache` artwork loader | **直接复用** |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricLineView.swift` | 共享原文/Ruby/罗马音/翻译层和显示偏好渲染 | **直接复用**，限制为当前行和下一行 projection，不渲染完整歌词文档 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/TrackMetadataView.swift` | 主窗口歌曲 metadata 排版 | **可选择复用排版思路**，胶囊使用独立紧凑 summary，不直接嵌入主窗口布局 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Providers/PlaybackProvider.swift` | 播放/暂停/上一首/下一首/seek 协议 | **直接复用**，胶囊只调用 `PlaybackState` 命令方法 |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/MockData.swift` 与 `MockPlaybackProvider.swift` | Mock Preview 和离线合同测试 | **仅 Mock/回退路径**，不作为胶囊数据源；胶囊必须在 Mock Preview 中仍遵循同一 `PlaybackState` projection |
| `/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj/project.pbxproj` | 当前所有 Swift 文件的 target 编译清单 | **需要加入新增胶囊模型、View、Controller、Persistence 和测试相关生产源** |
| `/Users/apple/backup/sptifylyrics/Tests` | 当前无独立 capsule contract；只有 floating contract 静态检查 legacy capsule 保留 | **需要新增 capsule pure/window contracts**，并保留悬浮相关测试不变 |

### 当前明确缺陷

1. 旧胶囊只显示标题、图标、一个播放按钮和一行原文；不显示艺人、封面 URL、翻译、假名、罗马音、下一行或失败/加载状态。
2. `state.currentLineIndex` 在纯文本时为 `nil`，但旧实现会显示 `state.lyrics.first`，会把第一行误呈现为当前歌词。
3. 旧窗口固定放到 `NSScreen.main`，没有屏幕身份、frame 持久化、屏幕排列变化、菜单栏自动隐藏、刘海安全区或全屏 Space 回位策略。
4. 旧窗口使用 `.statusBar` level，可能遮挡系统菜单或系统提示；正式版应降为 `.floating`。
5. 旧窗口是普通 `NSWindow`，没有非激活 panel 语义；`makeKeyAndOrderFront` 可能抢夺键盘焦点。
6. `showCapsulePlayer` 只是内存布尔值，窗口被系统关闭/屏幕变化后可能与真实可见状态不同；没有 delegate 生命周期回传。
7. 旧窗口虽然由 `WindowManager` 保留并可重复显示，但没有专用 controller、outside-click collapse、hover state、展开 state 或任务取消边界。

## 2. 正式状态与数据投影设计

### 2.1 胶囊状态机

新增 `CapsulePresentationState`，只表达胶囊 UI 状态，不表达歌词或播放状态：

```swift
public enum CapsulePresentationState: Equatable, Sendable {
    case collapsed
    case hover
    case expanded
}
```

状态转移：

```text
show → collapsed
pointer enters → hover
pointer leaves while not expanded → collapsed (with short debounce)
user clicks body / explicit expand action → expanded
user clicks outside / close action / track changes → collapsed
hide / close / app termination → no visible state
```

实现约束：

- Hover 只改变尺寸和信息密度，不触发播放操作、seek、歌词搜索或网络请求。
- 明确展开必须由点击胶囊或菜单动作触发；不因 hover 自动进入完整展开。
- 外部点击只收起，不改变播放状态；global monitor 只在 panel visible 且状态为 hover/expanded 时安装，收起或隐藏时移除。
- 不使用无限循环动画；尺寸和透明度动画使用一次性的 ease-in-out，动画任务取消后不能遗留。

### 2.2 共享数据 projection

胶囊 View 只读取下列共享值：

```swift
state.currentTrack
state.providerStatus
state.hasLiveTrack
state.isPlaying
state.currentTime
state.canControlSpotify
state.liveLyrics
state.liveLyricsState
state.liveLyricsAreSynchronized
state.liveCurrentLineIndex
state.liveLyricsStatusMessage
state.preferences
```

新增纯函数 `CapsuleLyricsPresentation.selection`，签名固定为：

```swift
public struct CapsuleLyricsSelection: Equatable, Sendable {
    public let current: LyricLine?
    public let following: LyricLine?
    public let isSynchronized: Bool
    public let status: String?
}

public enum CapsuleLyricsPresentation {
    public static func selection(
        lines: [LyricLine],
        currentIndex: Int?,
        isSynchronized: Bool,
        state: LyricsLoadState
    ) -> CapsuleLyricsSelection
}
```

该函数只使用已有 `currentIndex`，不按时间重新计算。规则：

- 同步歌词且有 current index：返回当前行和 `index + 1` 的下一行；不渲染整首歌词。
- 同步歌词但前奏尚未到第一行：current/following 均为 `nil`，返回“前奏”或空的克制状态，不提前显示歌词。
- 纯文本/`alignmentQueued`/`alignmentRunning`：current/following 均为 `nil`，只返回“纯文本 / 未排轴”；不取第一行，不滚动。
- `loading`、`noLyrics`、`noMatch`、`candidates`、`failed`：只返回对应短状态；候选只提示“请回主窗口选择”，不在胶囊复制候选管理。
- 切歌时由 `PlaybackState`/session revision 清空 live projection；胶囊不缓存上一首的 line、translation、artwork 或展开内容。

翻译、假名和罗马音全部由 `state.liveLyrics` 的共享 projection 提供，显示层继续复用 `state.preferences`。因此切换翻译版本、读音模式、人工编辑版本、TXT/LRC 导入版本或 automaticAlignment 子版本时，胶囊只需响应同一个 `PlaybackState.objectWillChange`。

## 3. WindowController 与屏幕策略

### 3.1 新增窗口文件

新增：

- `SpotifyLyrics/Windows/CapsuleLyricsWindowController.swift`
- `SpotifyLyrics/Windows/CapsuleLyricsWindowPersistence.swift`
- `SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift`
- `SpotifyLyrics/Views/Capsule/CapsuleLyricsStatusView.swift`
- `SpotifyLyrics/Lyrics/CapsuleLyricsPresentation.swift`

`CapsuleLyricsPanel: NSPanel` 使用：

```swift
styleMask: [.borderless, .nonactivatingPanel]
isReleasedWhenClosed = false
isOpaque = false
backgroundColor = .clear
level = .floating
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
hidesOnDeactivate = false
```

Controller 必须持有单一 panel，并公开：

```swift
@MainActor
final class CapsuleLyricsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible: Bool
    @Published private(set) var presentationState: CapsulePresentationState

    func toggle(state: PlaybackState, settings: AppSettingsStore)
    func show(state: PlaybackState, settings: AppSettingsStore)
    func hide()
    func expand()
    func collapse()
}
```

Controller 不拥有 `PlaybackProvider`、`LyricsSessionController`、`TranslationSessionController` 或 timer，只持有 weak/shared state 引用和窗口生命周期资源。

### 3.2 三种尺寸与交互

默认建议值（实现时根据可见 frame clamp）：

| 状态 | 默认尺寸 | 内容 |
|---|---:|---|
| collapsed | 360×46 | 小封面、标题/艺人、同步当前句的单行摘要或播放状态 |
| hover | 520×82 | 上一首、播放/暂停、下一首、标题/艺人、当前句/下一句摘要 |
| expanded | 620×220 | 封面、标题/艺人/专辑、当前句与下一句、读音/翻译层、播放控制、明确的主窗口/悬浮歌词/编辑入口 |

尺寸不是歌词数据；窗口只在状态转换时改变 frame，播放进度更新不重新计算尺寸。

交互：

- collapsed/hover/expanded 都不默认鼠标穿透，点击控件可用但不抢键盘焦点。
- expanded 允许通过背景拖动位置；默认不提供自由 resize，避免胶囊因拖拽变成不可读的任意面板。
- 播放/暂停、上一首、下一首调用 `PlaybackState.togglePlayPause()`、`previousTrack()`、`nextTrack()`；按钮 disabled 条件使用 `state.canControlSpotify`，Mock Preview 仍走同一 state 命令。
- expanded 的进度 Slider 只有用户完成拖动时调用 `state.seek(to:source:)`；展开、收起、hover、点击歌词文本均不调用 seek。
- “打开主窗口”“打开悬浮歌词”“编辑当前歌词”均是明确动作；执行后按状态机收起，不改变当前播放位置。

### 3.3 顶部位置与多屏比较

| 策略 | 优点 | 风险 | 结论 |
|---|---|---|---|
| 永远固定 `NSScreen.main` | 行为简单、不会意外跳屏 | 主窗口在外接屏时胶囊脱离工作屏；主屏排列变化后容易错位 | 仅保留为 fallback |
| 跟随鼠标/当前活动屏 | 适合多屏临时操作 | 鼠标移动或后台活动会使胶囊突然跳屏 | 不推荐 |
| 跟随主窗口所在屏 | 与当前播放/歌词工作区一致；不会因鼠标移动跳屏 | 主窗口被移动后需要平滑重定位 | **推荐，无新增用户设置** |
| 用户手动选择显示器 | 控制最强 | 增加设置、持久化和屏幕失效分支 | 本轮不做 |

推荐实现：胶囊显示时跟随主窗口所在屏；无法取得主窗口屏幕时回退 `NSScreen.main`，再回退 `NSScreen.screens.first`。保存 screen ID 仅用于恢复 frame，不把显示器选择暴露为新的设置项。

定位规则：

1. 使用目标屏的 `visibleFrame`，该 frame 不覆盖菜单栏；在顶部保留 8pt 间距。
2. 对带刘海屏使用 `safeAreaInsets.top`（可用时）进一步降低 y；外接屏无 inset 时保持 visibleFrame 规则。
3. 计算 `x = visibleFrame.midX - width/2`，再通过 `clamp` 保证完整 frame 位于 visibleFrame 内。
4. 监听 `NSApplication.didChangeScreenParametersNotification`、主窗口移动/激活和菜单栏可见区域变化，重新 clamp；不重新创建 panel。
5. full-screen Space 使用 `.fullScreenAuxiliary`；不把 level 提升到 status bar 或 modal。
6. 屏幕身份失效时恢复到当前主窗口屏幕的顶部中央；保存 frame 不覆盖悬浮歌词的 frame key。

### 3.4 持久化键

通过现有 `AppSettingsStore` 增加内部 keys，不新建 settings store 或 UI 分类：

```swift
general.capsuleWindowFrame
general.capsuleWindowScreenID
general.capsuleWindowWasVisible
```

不持久化 hover/expanded 临时状态；重启只恢复可见性和安全位置，初始状态总是 collapsed。 `restoreWindowState == false` 时不读取 frame，也不自动显示胶囊。

## 4. Capsule View 内容与状态展示

### collapsed

- `ArtworkView(track: state.currentTrack, size: 28, showsAlbumLabel: false)`，复用 `ArtworkImageLoader` 的缓存和 URL key。
- 标题和艺人单行截断；无 live track 时显示 provider 状态。
- 同步歌词且已有 current index 时显示当前原文短句；纯文本、前奏、无歌词、候选和失败时显示状态，不显示第一行歌词。
- 只保留小型播放状态图标，不常驻完整按钮。

### hover

- 显示上一首、播放/暂停、下一首；按钮不执行 optimistic seek 或虚假的长期播放状态。
- 显示标题、艺人和同步当前句/下一句；使用 `CapsuleLyricsPresentation.selection`。
- 纯文本只显示“纯文本 / 未排轴”，不循环歌词。

### expanded

- 显示紧凑封面、标题、艺人、专辑和播放位置。
- 同步歌词：当前行使用 active 层级，下一行使用邻近层级；层内容从 `LyricLineView` 读取原文、Ruby、罗马音、翻译设置。
- 纯文本：显示“纯文本 / 未排轴”和“回主窗口查看全文”入口；不高亮、不自动滚动。
- loading/no lyrics/candidates/failed 使用 `CapsuleLyricsStatusView`；候选不在胶囊内列出。
- 提供打开主窗口、打开正式悬浮歌词和编辑当前歌词的明确动作；编辑按钮只有 `state.canOpenLyricsEditor` 时可用。

## 5. WindowManager 与主路径接线

修改 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift`：

```swift
private var capsuleController: CapsuleLyricsWindowController?

public func toggleCapsulePlayer(state: PlaybackState)
public func restoreCapsuleWindowIfConfigured(state: PlaybackState)
public func collapseCapsulePlayer()
public func expandCapsulePlayer()
public var capsuleWindowIsVisible: Bool
```

`toggleCapsulePlayer` 不再直接构造 `NSWindow`；只创建一次 controller 并转发到 controller。 `floatingController` 保持现有实现，不共享 panel、frame key、screen observer 或 presentation state。

修改 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift` 的 `.task`，在已有 `startProvider` 和 floating restore 后调用 capsule restore；V3 只保留现有模式菜单入口，不改 V3 视觉布局。

修改 `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Main.swift`，加入不抢焦点的 App 菜单入口：

- 显示/隐藏顶部胶囊；
- 收起顶部胶囊；
- 展开顶部胶囊。

保留 `LyricsPreferencesPopover` 的现有按钮，确保它与菜单、主窗口模式菜单操作的是同一个 controller。

## 6. 性能、取消和生命周期

- 不新增播放计时器；胶囊不调用 provider refresh，不创建 `Task` 去轮询 currentTime。
- `CapsuleLyricsPresentation.selection` 为纯函数，使用已有 `liveCurrentLineIndex`；播放位置变化只改变 current/next 两个稳定行 projection。
- 胶囊不渲染完整歌词列表；切歌或歌词版本/revision 变化时才重建内容层，普通 tick 只更新摘要/当前行。
- 封面只通过 `ArtworkView`/`ArtworkImageLoader` 共享缓存；不得在 capsule View 中重新解码或做背景 blur。
- `CapsuleLyricsWindowController` 只在状态需要时启动收起 debounce/动画 Task；每次新事件先取消旧 Task，hide/deinit 时取消全部 Task。
- outside-click monitor、screen-change observer、Combine cancellable 均在 controller `deinit` 或对应状态结束时移除。
- `WindowManager` 强引用 controller 作为单例窗口所有者；panel `isReleasedWhenClosed = false`，hide 使用 `orderOut`；App 退出时 controller/panel 可以随 manager 释放，不产生隐藏窗口任务。
- 使用 `Equatable` selection/row projection 和稳定 `LyricLine.id`，避免每个 tick 重建完整 SwiftUI 行树。

## 7. 拟修改文件

### 新增

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/CapsuleLyricsPresentation.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Capsule/CapsuleLyricsStatusView.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/CapsuleLyricsWindowController.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/CapsuleLyricsWindowPersistence.swift`
- `/Users/apple/backup/sptifylyrics/Tests/capsule_lyrics_contract.swift`
- `/Users/apple/backup/sptifylyrics/Tests/capsule_lyrics_contract.sh`
- `/Users/apple/backup/sptifylyrics/Tests/capsule_window_behavior_contract.sh`

### 修改

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Settings/AppSettingsStore.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/PlaybackState.swift`（仅补充 live projection 接口时修改）
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`（仅接线，不改视觉）
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift`（保留入口，必要时改状态绑定）
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Main.swift`
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj/project.pbxproj`

### 冻结/清理候选

- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift` 中旧 `CapsulePlayerView`：新 controller 接通并通过真实验收后删除无引用旧实现；`LineDisplayView`、`PlainLyricsListView`、`FullScreenLyricsView` 和当前正式 V1 悬浮兼容边界不能一起删除。
- `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift` 中旧 `capsuleWindow: NSWindow?` 和直接创建 `NSWindow` 的代码：新 controller 接通后删除；不能保留两条胶囊创建路径。

## 8. 合同测试计划

### 纯 projection 合同

`Tests/capsule_lyrics_contract.swift` 覆盖：

1. 同步歌词 current index=2 时只返回第 2 行和第 3 行，不返回整首。
2. current index 为 `nil` 的前奏不返回第一行作为 current。
3. 纯文本/`alignmentQueued` 不返回 current/following，不自动滚动。
4. loading、no lyrics、noMatch、candidates、failed 映射到短状态。
5. 相同标题但不同 identity/revision 的迟到 projection 不被接受。
6. 翻译/读音层只改变显示 projection，不改变原文、时间戳或 active line index。

`Tests/capsule_lyrics_contract.sh` 编译真实 production model、presentation helper 和必要的 session 状态，禁止使用 Mock 歌词作为“实现已接线”的唯一证据。

### Window/生命周期合同

`Tests/capsule_window_behavior_contract.sh` 静态检查：

- 单一 `CapsuleLyricsWindowController` 创建入口和单一 retained panel；
- `NSPanel`、`.nonactivatingPanel`、`.floating`、`.canJoinAllSpaces`、`.fullScreenAuxiliary`；
- 不出现 `.statusBar`/`.modalPanel`；
- frame/screen/visible keys 与 floating keys 不同；
- screen-change clamp、outside-click monitor 清理和 deinit 清理存在；
- capsule files 不创建 `PlaybackProvider`、`LyricsSessionController`、`TranslationSessionController`、`Timer.scheduledTimer` 或网络请求；
- `WindowManager` 不再直接创建胶囊 `NSWindow`，且 capsule/floating controller 分离；
- 隐藏不退出 App，不创建多个 panel。

### 回归

运行全部现有 `Tests/*.sh`，并追加 capsule contracts。重点确保 floating `38/38` 基线、SQLite、翻译、编辑器、读音、排轴和播放合同不回归。

## 9. 真实验收矩阵

| 场景 | 操作 | 必须观察 |
|---|---|---|
| 恋風 / Lilas | 同步播放、暂停、恢复、seek、切换翻译/Ruby/罗马音 | 当前行/下一行来自共享 session；暂停不动；seek 立即更新；不显示 search preview |
| 水曜日の約束 / Kawasaki.Rio | 使用隔离数据库保留 QQ 32 行纯文本 | 显示未排轴状态；不出现第一行伪高亮；不自动轮换歌词 |
| あやふや / みさき | 所有 Provider 无正文 | 不残留上一首歌词、封面或展开内容；显示 no lyrics/noMatch 短状态 |
| 人工导入/编辑 | 保存 manualImport/manualEdit 后切回胶囊 | 原文/读音/翻译立即刷新；未排轴仍不伪同步 |
| automaticAlignment 子版本 | 用户确认已有排轴子版本 | 由共享 session 自动进入同步 current/next 展示，不新增胶囊时间轴 |
| 快速 A→B→A | 连续切歌并等待迟到 Provider/翻译结果 | A 的迟到结果不能写入 B；回到 A 后只显示 A 当前版本 |
| 三种显示状态 | 收起、hover、点击展开、外部点击 | 尺寸/信息层级正确；不抢键盘焦点；外部点击可收起 |
| 播放控制 | 上一首/播放暂停/下一首，展开状态拖动 Slider | 只明确操作触发 provider 命令或 seek；展开/收起/点击歌词不 seek |
| 双窗口 | 胶囊和悬浮歌词同时开启，切歌/暂停/改设置 | 两者显示同一首歌/同一翻译/同一读音；不互相关闭；只有一个 PlaybackState timer |
| 多屏/Space | 移动主窗口到外接屏、改变屏幕排列、进入 full-screen Space | 胶囊跟随主窗口屏幕并保持可见；失效屏幕安全回位；不覆盖系统菜单 |
| 重启 | 胶囊可见后退出/重启 App | 仅在 restoreWindowState 开启且上次可见时恢复；初始 collapsed；frame 不与 floating 冲突 |

真实商业歌曲没有对应歌词或音频时，记录状态，不用 Mock/TTS 代替真实验收。

## 10. 需要用户决定的产品行为

以下行为当前规格没有唯一答案，建议采用括号中的默认值；开始实现前由用户确认即可：

1. **屏幕策略：** 固定主屏幕、跟随主窗口屏幕（推荐）、跟随鼠标活动屏幕或新增显示器选择设置。推荐跟随主窗口屏幕，不新增设置项。
2. **启动恢复：** 上次可见时自动恢复，还是每次启动默认隐藏（推荐遵守现有 `restoreWindowState` 与 `capsuleWindowWasVisible`）。
3. **拖动/缩放：** 只在 expanded 状态允许背景拖动、固定三档尺寸（推荐），还是允许用户 resize。
4. **hover 离开：** 离开后立即回到 collapsed，还是保留短暂 delay（推荐 0.35 秒，避免鼠标经过时闪烁）。
5. **expanded 是否带 Slider：** 带一个明确拖动才 seek 的进度条（推荐），还是只显示时间不提供 seek。
6. **胶囊与悬浮歌词同时显示：** 默认允许并分别管理（规格已要求允许）；不提供互斥模式开关。

## 11. 交付门槛

实现阶段完成以下步骤后才可声称顶部胶囊 V1 完成：

- 新增合同先红后绿；
- 全部现有合同和新增 capsule 合同通过；
- 正常签名 Debug `xcodebuild` 输出 `BUILD SUCCEEDED`；
- `codesign --verify --deep --strict` 通过；
- 进程来自 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`；
- 真实 App 完成恋風、水曜日の約束、あやふや、快速 A→B→A、双窗口和至少一次屏幕排列变化验证；
- `git diff --check` 通过；
- 只提交胶囊实现、合同和验收记录，不提交 DerivedData、参考项目或敏感信息；
- 独立 commit，且最终报告区分“源码存在”“进入 target”“真实窗口可操作”“真实歌词状态已验证”。


## 12. 按任务实施顺序

### Task 1: 先写胶囊红色合同并冻结旧入口

**Files:**

- Create: `/Users/apple/backup/sptifylyrics/Tests/capsule_lyrics_contract.swift`
- Create: `/Users/apple/backup/sptifylyrics/Tests/capsule_lyrics_contract.sh`
- Create: `/Users/apple/backup/sptifylyrics/Tests/capsule_window_behavior_contract.sh`
- Modify: none in production source

**Interfaces:**

- Contract imports `LyricLine`、`LyricsLoadState`、`CapsuleLyricsPresentation` once the pure helper exists.
- Window contract scans only the capsule implementation and `WindowManager`; it must not require a second state source.

**Steps:**

- [ ] 编写 projection red cases：同步 current/next、前奏、纯文本、loading/noMatch/candidates/failed。
- [ ] 编写静态窗口 red cases：旧直接创建路径、缺少 controller、错误 window level、缺少屏幕回位和生命周期清理时明确失败。
- [ ] 运行 `sh Tests/capsule_lyrics_contract.sh` 和 `sh Tests/capsule_window_behavior_contract.sh`，记录它们因新增 production types/path 不存在或旧路径仍存在而失败。
- [ ] 不修改现有 floating contracts；确认基线悬浮歌词测试仍保留。

### Task 2: 实现纯歌词 projection

**Files:**

- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/CapsuleLyricsPresentation.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Services/PlaybackState.swift` only if a live-only accessor is missing

**Interfaces:**

```swift
public struct CapsuleLyricsSelection: Equatable, Sendable {
    public let current: LyricLine?
    public let following: LyricLine?
    public let isSynchronized: Bool
    public let status: String?
}

public enum CapsuleLyricsPresentation {
    public static func selection(
        lines: [LyricLine],
        currentIndex: Int?,
        isSynchronized: Bool,
        state: LyricsLoadState
    ) -> CapsuleLyricsSelection
}
```

**Steps:**

- [ ] 用已有 `state.liveCurrentLineIndex` 传入 index；helper 内禁止读取 `currentTime`、创建 timer 或重新调用 `LyricsTimeline.activeLineIndex`。
- [ ] 对同步歌词只选择 current 和 following；对纯文本和前奏返回无 current 的状态。
- [ ] 对候选/失败/加载返回短消息，不复制候选数组或错误面板。
- [ ] 运行 Task 1 projection contracts，确认纯 helper 变绿。
- [ ] 保存原文、时间戳、Ruby、romaji 和 translation 的不可变语义，不在 projection 中写回歌词。

### Task 3: 实现 panel、frame persistence 和三态 controller

**Files:**

- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/CapsuleLyricsWindowPersistence.swift`
- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/CapsuleLyricsWindowController.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Settings/AppSettingsStore.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Windows/WindowManager.swift`

**Interfaces:**

```swift
@MainActor
final class CapsuleLyricsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible: Bool
    @Published private(set) var presentationState: CapsulePresentationState

    func toggle(state: PlaybackState, settings: AppSettingsStore)
    func show(state: PlaybackState, settings: AppSettingsStore)
    func hide()
    func expand()
    func collapse()
}
```

**Steps:**

- [ ] 创建单一 `CapsuleLyricsPanel: NSPanel`，使用 `.nonactivatingPanel`、`.floating`、`.canJoinAllSpaces` 和 `.fullScreenAuxiliary`；明确不使用 `.statusBar` 或 `.modalPanel`。
- [ ] 为胶囊写入独立的 `frame`、`screenID`、`wasVisible` keys；不得复用 floating frame keys。
- [ ] 实现主窗口屏幕优先、`NSScreen.main` fallback、visibleFrame/safe-area clamp 和 screen parameter observer。
- [ ] 实现 outside-click monitor、hover debounce task 和 screen observer 的安装/清理；hide/deinit 时取消和移除所有资源。
- [ ] 让 `WindowManager.toggleCapsulePlayer` 只转发到 controller；删除旧的直接 `NSWindow` 构造路径。
- [ ] 运行 window contracts，确认单例、层级、回位、清理和 floating controller 分离全部通过。

### Task 4: 实现三态 SwiftUI 内容和显式播放操作

**Files:**

- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Capsule/CapsuleLyricsStatusView.swift`
- Create: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Capsule/CapsuleLyricsView.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/LyricsViews.swift` only to freeze/remove the old unreferenced capsule view

**Interfaces:**

- View consumes `@ObservedObject var state: PlaybackState` and `@ObservedObject var windowController: CapsuleLyricsWindowController`.
- View uses `ArtworkView`、`LyricLineView`、`CapsuleLyricsPresentation.selection` and `state.preferences`.
- Play commands call only `state.togglePlayPause()`、`state.previousTrack()`、`state.nextTrack()`；seek calls only `state.seek(to:source:)` after explicit Slider editing.

**Steps:**

- [ ] 实现 collapsed、hover、expanded 三种信息密度；hover 不等于完整展开。
- [ ] 同步歌词显示 current/next；纯文本显示“纯文本 / 未排轴”，不取第一行、不滚动、不伪高亮。
- [ ] 加入封面、标题、艺人、专辑、播放状态、原文/Ruby/罗马音/翻译和状态信息的最小布局。
- [ ] 所有播放按钮以 `state.canControlSpotify` 为 disabled 条件；展开/收起/点击歌词文本不调用 seek。
- [ ] 通过 stable line ID、Equatable selection 和子视图限制每次 tick 的更新范围；不渲染整首歌词。
- [ ] 运行 pure/window contracts，并用源码扫描确认 capsule files 没有 provider、session、translation service、network request 或第二 timer。

### Task 5: 接入 App、主窗口菜单和共享设置

**Files:**

- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Main.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift`
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift` only for existing menu action wiring
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift` only for shared visibility binding
- Modify: `/Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj/project.pbxproj`

**Interfaces:**

- All entry points call `WindowManager.shared`; no view creates `CapsuleLyricsWindowController` directly.
- App menu and existing mode menu call the same show/hide/collapse/expand methods.
- `MainLyricsWindowView.task` calls `restoreCapsuleWindowIfConfigured(state:)` once, parallel to existing floating restore.

**Steps:**

- [ ] 将新增 Swift 文件加入 `SpotifyLyrics` target 和 Sources build phase。
- [ ] 保留 V2/V3 现有菜单外观和行为，只替换顶部胶囊实际实现。
- [ ] 加入“显示/隐藏”“收起”“展开”菜单命令，不把胶囊变成第二套设置窗口。
- [ ] 验证胶囊与悬浮歌词可以同时显示，两个 controller 不共享 frame、screen observer 或 visibility state。
- [ ] 运行全量合同，确认既有 38/38 基线及新增合同均通过。

### Task 6: Debug build、真实运行和独立提交

**Files:**

- Create: `/Users/apple/backup/sptifylyrics/docs/superpowers/specs/acceptance-2026-08-01-top-capsule-final-v1/README.md`
- Modify: production source only when a failing acceptance reveals an in-scope capsule defect

**Steps:**

- [ ] 清理当前 Debug DerivedData，使用正常签名 Debug 构建：
  `xcodebuild -project /Users/apple/backup/sptifylyrics/SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug -derivedDataPath /Users/apple/backup/sptifylyrics/DerivedData build`
- [ ] 运行 `codesign --verify --deep --strict /Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`。
- [ ] 只启动 `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`，用 `ps` 确认可执行文件来自同一绝对路径。
- [ ] 真实运行恋風、水曜日の約束、あやふや；记录同步、纯文本、无正文、翻译/读音切换和切歌清空结果，不记录 token/API key/完整歌词。
- [ ] 运行快速 A→B→A、胶囊与悬浮歌词同时打开、暂停/恢复/seek、三态切换和无隐式 seek 检查。
- [ ] 移动主窗口到外接显示器、改变屏幕排列并进入 full-screen Space，记录胶囊的回位和可见性。
- [ ] 运行 `git diff --check` 和全量 contracts；把尚未实测的行为明确写入验收记录。
- [ ] 只 stage 胶囊实现、合同和验收记录；检查 staged diff 无 token、Authorization header、API key 或完整歌词。
- [ ] 创建独立 commit，最终报告区分源码、target、真实窗口和真实歌曲状态。
