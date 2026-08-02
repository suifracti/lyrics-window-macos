# Dynamic Island 官方与开源实现审计

**日期：** 2026-08-02  
**范围：** 只读研究、设计语法对照和实现风险审计。  
**本轮结论：** 未修改 Swift、Xcode Target、PlaybackState、LyricsSession、现有 mockup 或数据库；未构建、未导入第三方源码、未提交 commit。

## 1. 结论先行

Apple 的 Dynamic Island 是 **iPhone/iPad Live Activities 的系统承载和布局语法**，不是 macOS `NSPanel` 的 API。Lyric Island 可以吸收它的内容分层、边距、圆角、动画和信息优先级原则，但不能把 `DynamicIsland`、`DynamicIslandExpandedRegion` 或 iPhone 的 point 尺寸直接移植到 macOS。

推荐的 macOS 方向是：

1. 胶囊继续作为一个独立的非激活 `NSPanel`，使用现有 `CapsuleLyricsWindowController` 和共享 live projection。
2. 桌面歌词继续是另一个独立表面，使用现有 `FloatingLyricsWindowController`；它不是胶囊的“更大版本”。
3. 两个表面由 WindowManager 统一协调，但分别拥有 frame、screen、visibility、锁定、穿透和 hover 状态。
4. 胶囊采用 Apple 的“语义区域”思想：收起状态只保留 leading identity 与 trailing playback state；展开状态最多保留一行当前歌词，不在胶囊中塞入多行字幕。
5. 桌面歌词采用透明文字层或轻材质层，而不是复制一个 iPhone Dynamic Island 外壳。

Apple 的 `keylineTint` 可以作为“极弱边缘色”的设计参考，但不应转化为粗描边或灰色卡片。Apple Design Resources 只用于 mockup，不把模板资源打包到 App。

## 2. 审计对象与快照

### 2.1 官方资料

- [Human Interface Guidelines — Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [`DynamicIsland`](https://developer.apple.com/documentation/widgetkit/dynamicisland)
- [`DynamicIsland.init(expanded:compactLeading:compactTrailing:minimal:)`](https://developer.apple.com/documentation/widgetkit/dynamicisland/init%28expanded%3Acompactleading%3Acompacttrailing%3Aminimal%3A%29)
- [`DynamicIslandMode`](https://developer.apple.com/documentation/widgetkit/dynamicislandmode)
- [Apple Design Resources](https://developer.apple.com/design/resources/)
- [Apple Design Resources License](https://developer.apple.com/support/downloads/terms/apple-design-resources/Apple-Design-Resources-License-20230621-English.pdf)
- [WWDC23 — Design dynamic Live Activities](https://developer.apple.com/videos/play/wwdc2023/10194/)
- [ActivityKit](https://developer.apple.com/documentation/ActivityKit/)

### 2.2 开源项目

本轮以只读 clone 和仓库公开页面为准。clone 位于 `/tmp/dynamic-island-reference-audit-1785633115/`，不属于 SpotifyLyrics，也没有被加入 Xcode Target。

| 项目 | 本地审计路径 | 审计快照 | 根许可证 |
|---|---|---:|---|
| boring.notch | `/tmp/dynamic-island-reference-audit-1785633115/boring.notch` | `8dd02e7555cbe48899524c61d24e50703e68ff68` | GPL-3.0 |
| Atoll / DynamicIsland | `/tmp/dynamic-island-reference-audit-1785633115/Atoll` | `fd3dafcb8661ac02bd47569405feb5340db2c73c` | GPL-3.0；并明确声明源自 boring.notch |
| DynamicNotch | `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch` | `c03ce83df1f2ae820ec44c5511290f42286138d3` | MIT |

“快照”仅用于本报告可复现定位，不代表上游永远不变。许可证结论以仓库根目录、NOTICE、THIRD_PARTY_LICENSES 和资源声明共同判断，不能用某个依赖的许可证代替整个仓库的许可证。

## 3. Apple 官方设计规则摘要

### 3.1 四种信息模式

Apple 的 Live Activity 必须考虑系统可能使用的 Compact、Minimal、Expanded 和 Lock Screen 等承载状态。Dynamic Island 的 compact 由两个互相独立的区域组成：`compactLeading` 与 `compactTrailing`。它不是一条从左到右的普通横向列表。

| Apple 语义 | 官方意图 | 对 Lyric Island 的可用转译 |
|---|---|---|
| `compactLeading` | 左侧身份或最关键状态；窄、紧贴系统承载体 | 封面缩略图、短歌名或当前播放身份 |
| `compactTrailing` | 另一组独立的最新状态 | 播放/暂停状态、短进度或必要状态图标 |
| `minimal` | 多个 Live Activity 同时存在时的最小表示，仍要传达信息 | 仅作为未来极小浮动状态的参考；当前产品不必强行新增运行态 |
| `expanded` | 用户明确展开后，呈现本次活动的本质和必要操作 | 胶囊展开；最多一行当前歌词，不承担多行字幕 |
| expanded leading | 展开区左侧语义位置 | 封面与歌曲身份 |
| expanded trailing | 展开区右侧语义位置 | 播放、上一首、下一首等必要控制 |
| expanded center | 展开区中心主信息 | 一行当前歌词或播放状态 |
| expanded bottom | 展开区底部辅助信息 | 紧凑进度条、少量入口图标 |

`DynamicIslandExpandedRegion` 的 leading/trailing/center/bottom 是布局区域的语法，不是建议把所有内容全部放进去。每个区域都要服从信息优先级和动态尺寸约束。

### 3.2 内容最小化

官方原则可归纳为：

- Compact 尽可能窄，不留下没有意义的空白。
- 不要只留下 logo 而让用户失去当前状态；Minimal 仍要具有信息量。
- Expanded 既不能过空，也不能把完整 App 搬进来。
- 低优先级内容应先截断、降级精度或隐藏，而不是把容器无限撑大。
- Compact 与 Expanded 中相同信息的相对位置应尽量保持，帮助用户理解展开前后是同一件事。
- Expanded 高度可以根据内容变化，但要避免卡在尴尬的中间高度或形成上方“额头”空白。

对 Lyric Island 的直接结论：歌曲身份和播放状态必须比歌词辅助层更稳定；当前行优先于下一行；罗马音、翻译和设置入口不能挤占胶囊的主要信息位。

### 3.3 同心圆角、边距与 keyline tint

Apple 在 HIG 和 WWDC 设计讲解中反复强调：内容应与外层承载体同心，边距均匀，避免文字或控件贴到边墙和圆角；嵌套形状要保持同心圆角关系。SwiftUI 场景可以用 `ContainerRelativeShape` 一类的系统语义保持内外圆角协调，但这不是 macOS 胶囊必须直接复制的 API。

`keylineTint` 是围绕 Dynamic Island 的轻微色彩提示。它适合被转译成非常弱的边缘色或封面主色光晕，不适合做成一圈高对比描边、灰色边框或永久发光。

Apple Design Resources 中有 Live Activities 的 Figma/Sketch 模板。其许可允许软件界面 mockup 使用，但不应把模板中的图形资源、组件文件或专有素材打包进 Lyric Island。

### 3.4 Compact → Expanded 动画

动画的重点不是“弹得像灵动岛”，而是：

- 保留共享元素的锚点和相对位置；
- 让容器宽高、裁切和内容显隐连续变化；
- 不在展开瞬间把阅读顺序完全重排；
- 内容先减法，再补充次要信息；
- Reduce Motion 下禁用弹簧、明显位移和 blur morph，保留短促 opacity/crossfade 即可。

macOS 实现应以现有窗口控制器的 frame 动画和 SwiftUI 内容过渡为基础，不引入第二个播放计时器或独立歌词行计算器。

### 3.5 macOS 边界

Live Activities 可用于 iPhone/iPad；Dynamic Island 形态只出现在支持该形态的设备上。附近 iPhone 的 Live Activities 也可以显示在 Mac 菜单栏等系统承载位置。这个跨设备展示能力不等于 macOS 普通 App 获得了创建系统 Dynamic Island 的公开窗口 API。

因此：**使用 Apple 的信息架构语法，不使用 Apple 的 iPhone Dynamic Island API 作为 macOS 窗口实现。** Lyric Island 的顶部胶囊仍必须是自有 AppKit 窗口，自己处理 `NSScreen`、safe area、Space、鼠标事件和窗口层级。

## 4. 三个开源项目对比

### 4.1 总表

| 维度 | boring.notch | Atoll / DynamicIsland | DynamicNotch |
|---|---|---|---|
| 许可证 | GPL-3.0 | GPL-3.0；NOTICE 明确由 boring.notch 改编 | MIT |
| UI 技术 | SwiftUI 内容 + AppKit `NSPanel` | SwiftUI 内容 + AppKit `NSPanel` | SwiftUI + AppKit `NSWindow`/`NSWindowController` |
| 产品性质 | 多功能 notch 工具，含音乐控制、文件架、HUD 等 | 更大型的 Dynamic Island/notch 工具，含音乐、提醒、终端等 | 文件投递/临时存储 notch，不是音乐播放器 |
| 主要窗口 | `BoringNotchWindow` | `DynamicIslandWindow` | `NotchWindow` |
| 顶部定位 | 以屏幕 frame 顶部居中；使用 display UUID 等屏幕识别 | 屏幕 frame 顶部居中；部分路径使用 `localizedName` | 顶部居中，优先内建屏；无 notch 使用 fallback 尺寸 |
| notch / 无 notch | 有 notch 信息和外接屏路径；有 hide-on-closed 逻辑 | 有 Dynamic Island/外接屏 fallback；按屏幕调整尺寸 | 从 `safeAreaInsets` 推断 notch；无 notch 用约定尺寸 |
| 状态 | 主要是 closed/open，hover、拖动和 popover 会影响展开 | closed/open 加大量 tab、live activity、popover 状态 | closed/popping/opened，另有 click/drag/boot 原因 |
| 尺寸动画 | SwiftUI spring/custom shape，窗口 frame 同步调整 | smooth/spring、多种 tab 和内容高度变化 | interactive spring，打开尺寸约 600×160 |
| 形状 | `NotchShape`，顶部/底部圆角可动画 | `DynamicIslandPillShape`、`NotchShape`，continuous rounded rect | 自定义 mask，按 notch 形状和内外边距拼接 |
| 鼠标/点击 | `onHover` + 可取消延迟任务，点击/拖动打开 | onHover、全局/局部事件、快捷键和大量功能手势 | global/local monitor、outside click、拖拽文件、Option 键事件 |
| 音乐布局 | `MusicManager`、专用音乐 View、控制键和 TimelineView | `MinimalisticMusicPlayerView`、`NotchHomeView` 等 | 无音乐控制；核心是文件 drop |
| 多屏 | 可按屏幕 UUID 创建/重建窗口，监听屏幕参数变化 | 可创建每屏窗口，监听屏幕变化并清理重建 | 主要选择内建屏幕，监听屏幕参数变化 |
| 对 Lyric Island 的价值 | 窗口生命周期、屏幕 UUID、hover debounce、形状思路 | 内容驱动尺寸和协调器思路；但复杂度很高 | safe-area/notch 检测、明确状态机、outside click/mask 思路 |
| 不适合之处 | GPL、私有 SkyLight、过高 window level、独立音乐计时 | GPL、从 GPL 项目派生、私有空间/权限/大型功能耦合 | 文件投递产品逻辑、`statusBar + 8` 层级、无歌词模型 |

### 4.2 boring.notch

关键源码位置：

- `/tmp/dynamic-island-reference-audit-1785633115/boring.notch/boringNotch/components/Notch/BoringNotchWindow.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/boring.notch/boringNotch/models/BoringViewModel.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/boring.notch/boringNotch/ContentView.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/boring.notch/boringNotch/boringNotchApp.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/boring.notch/boringNotch/components/Notch/NotchShape.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/boring.notch/boringNotch/components/Notch/NotchHomeView.swift`

观察到的机制：

- `BoringNotchWindow` 是 `NSPanel`，设置了透明背景、不可成为主窗口、`fullScreenAuxiliary`、`canJoinAllSpaces` 和 `stationary`。
- 它使用 `.mainMenu + 3`，这对 Lyric Island 不适合；正式产品应继续使用已经确认的 `.floating`，避免遮盖系统提示和菜单。
- ViewModel 以 `closed/open` 管理尺寸，结合屏幕 UUID、`visibleFrame`、`safeAreaInsets.top` 和屏幕变化重建窗口。
- `ContentView` 的 hover 逻辑有可取消任务，离开 hover 后延时关闭；这类 debounce 思路可以吸收。
- `NotchShape` 使用可动画的顶部/底部圆角；只能作为概念参考，不能复制实现。
- 音乐页使用独立的 `MusicManager` 和 `TimelineView` 更新进度/歌词，这正是 Lyric Island 必须避免的第二套播放器和歌词时钟。
- `BoringNotchSkyLightWindow`/相关私有 SkyLight 路径用于更强的系统层显示，超出本项目需求，不应引入。

### 4.3 Atoll / DynamicIsland

关键源码位置：

- `/tmp/dynamic-island-reference-audit-1785633115/Atoll/DynamicIsland/components/Notch/DynamicIslandWindow.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/Atoll/DynamicIsland/models/DynamicIslandViewModel.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/Atoll/DynamicIsland/DynamicIslandApp.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/Atoll/DynamicIsland/components/Notch/DynamicIslandPillShape.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/Atoll/DynamicIsland/components/Notch/MinimalisticMusicPlayerView.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/Atoll/DynamicIsland/components/Notch/NotchHomeView.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/Atoll/DynamicIsland/sizing/matters.swift`

观察到的机制：

- `DynamicIslandWindow` 是 `NSPanel`，由 `DynamicIslandApp` 创建并承载 SwiftUI `ContentView`。
- 项目有 per-screen window/view-model 结构，监听 `didChangeScreenParametersNotification`，屏幕变化时清理旧窗口并重建；这是可借鉴的生命周期原则。
- `positionWindow` 以 screen frame 顶部居中，窗口尺寸会根据内容重新计算并 clamp 到屏幕尺寸。
- ViewModel 维护 `closed/open`，并根据 lyrics、tab、reminder 等内容动态增高；这种“内容驱动尺寸”符合 Apple 原则，但它把很多产品功能混进一个大窗口，不能直接搬到 Lyric Island。
- `DynamicIslandPillShape` 使用 `.continuous` 圆角，解决无 notch 外接屏的 pill 形状问题；可独立重新实现相同设计思想。
- 音乐 View 有独立状态、hover/popover 和 `TimelineView`；对 Lyric Island 来说只能参考信息分组，不能复制数据或计时逻辑。
- 代码包含大量功能、权限、锁屏窗口、私有空间和屏幕行为，整体复杂度不适合作为本项目依赖。

许可证补充：Atoll 的 `NOTICE` 明确写着产品包含从 boring.notch 派生并修改的代码；`COPYRIGHT_ASSETS` 对原创素材和第三方素材另作说明。因此不能只看 Atoll 的某个 Swift 文件或某个依赖来绕过 GPL 和资产归属问题。

### 4.4 DynamicNotch

关键源码位置：

- `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch/NotchDrop/NotchWindow.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch/NotchDrop/NotchWindowController.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch/NotchDrop/NotchViewModel.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch/NotchDrop/NotchView.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch/NotchDrop/NotchViewModel+Events.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch/NotchDrop/EventMonitors.swift`
- `/tmp/dynamic-island-reference-audit-1785633115/DynamicNotch/NotchDrop/Ext+NSScreen.swift`

观察到的机制：

- `NotchWindowController` 明确拥有窗口、ViewModel 和屏幕；`destroy()` 对 ViewModel、window 和 hosting controller 做对称清理。这种生命周期边界值得参考。
- ViewModel 使用 `closed/popping/opened` 状态，区分 click、drag、boot 等打开原因；这比把 hover、拖动和展开混成一个 Bool 更清晰。
- `Ext+NSScreen.swift` 根据 `safeAreaInsets.top`、左右辅助区域判断 notch，并给无 notch 屏幕 fallback 尺寸。
- `NotchView` 使用自定义 mask 和嵌套圆角处理顶部 notch 与底部圆角，能作为形状设计的研究样本。
- 事件监视器包含 local/global mouse move/down/drag，并处理 outside click 和拖动期间不关闭。
- `NotchWindow` 使用 `.statusBar + 8`，源码注释也承认这是很高的层级；Lyric Island 明确不能采用。
- 项目是文件投递工具，没有歌曲、歌词、封面或播放状态；其拖放区域、文件暂存和 Option 删除行为不适合本项目。

## 5. 我们当前 mockup 与 Dynamic Island 语法的偏差

现有 mockup 位于：

`/Users/apple/backup/sptifylyrics/docs/design/phase-2-3-visual-mockups/`

其中 `capsule-states.svg` 是静态设计稿，不是 Apple API 实现。当前规格值为 collapsed 约 `120–220pt × 36–40pt`、hover 约 `260–340pt × 48–52pt`、expanded 约 `300–360pt × 156–196pt`；这些是 Lyric Island 的 macOS 视觉 envelope，不是 iPhone Dynamic Island 的系统尺寸。

| 当前 mockup | 与 Apple 语法一致之处 | 仍需明确的偏差 |
|---|---|---|
| collapsed | 内容少、封面/标题/播放状态紧凑 | 目前是一个普通横向组，没有明确表达 `compactLeading` 与 `compactTrailing` 两个独立语义区域 |
| hover | 控件在歌曲信息之后，避免把播放键放在阅读起点 | Hover 不是 Apple 的正式模式；它是 macOS 的交互触发层，应保持为本地状态，不冒充 Live Activity mode |
| expanded | 有封面、metadata、紧凑控制、进度和一行歌词；符合“最小必要信息” | 当前图是线性排版，尚未明确 leading/trailing/center/bottom 的语义锚点和共享元素的过渡路径 |
| 一行歌词 | 遵守“胶囊不显示下一行/多行歌词”的产品决定 | 要定义歌词长句截断和宽度压缩优先级，不能靠增高胶囊变成迷你主窗口 |
| 圆角与阴影 | 视觉上使用圆角和轻材质 | 下一版需明确外层/内层同心 inset、corner token 和 keyline tint 的弱化范围 |
| 背景 | 封面色驱动轻沉浸，复杂背景有轻材质 fallback | 不应把 Apple keyline tint 画成粗边框，也不能复制 Apple 模板素材 |
| 桌面歌词 | 已拆为独立透明/轻材质表面 | 桌面歌词不是 Dynamic Island expanded；不能套成一张更大的控制卡片 |
| minimal | 当前未作为正式运行态呈现 | 可以在研究 mockup 里画极小信息状态，但暂不强行加入 App 状态机，除非未来需要处理多个浮动活动 |

现有 mockup 已经有两个重要正确方向：一是 Expanded 最多一行歌词，二是桌面歌词负责多行字幕。下一步只需用 Apple 的区域语法整理信息锚点，不应再画成 Control Center 风格播放器卡片。

## 6. Lyric Island 可采用的窗口结构

### 6.1 代码结构

```text
PlaybackState / live projection
            │
            ▼
    FloatingSystemCoordinator
       ┌────┴────┐
       ▼         ▼
CapsuleLyrics  FloatingLyrics
WindowController WindowController
       │         │
       ▼         ▼
 capsule surface  desktop subtitle surface
```

协调器只发送窗口命令和临时编排命令，不拥有第二份歌词、播放或翻译状态。两个 Controller 继续独立：

- 独立 panel；
- 独立 frame key；
- 独立 screen identity；
- 独立 visibility/lock/pass-through；
- 独立 hover/local event 生命周期；
- 共享 `liveLyrics`、`liveCurrentLineIndex`、`currentTrack`、`currentTime` 和 `AppSettingsStore` 的只读 projection。

### 6.2 胶囊的 macOS 语义区域

```text
collapsed / compact analogue
┌────────────────────────────────────────────┐
│ compactLeading: cover + short title        │ compactTrailing: play state │
└────────────────────────────────────────────┘

hover / local interaction layer
┌─────────────────────────────────────────────────────────────┐
│ leading: cover + title/artist        trailing: prev play next  │
└─────────────────────────────────────────────────────────────┘

expanded
┌─────────────────────────────────────────────────────────────┐
│ leading: cover + metadata              trailing: transport   │
│                                                             │
│                 center: one-line live lyric                 │
│                                                             │
│ bottom: short progress + small icon entries                 │
└─────────────────────────────────────────────────────────────┘
```

这里的 leading/trailing/center/bottom 是 Lyric Island 自己的语义分区，不是把 `DynamicIslandExpandedRegion` 直接调用到 macOS。Expanded 仍然不得显示下一句、完整翻译段落或多行字幕。

### 6.3 桌面歌词的区域

桌面歌词不采用 Apple Dynamic Island 的 expanded shell。它应保持独立字幕层：

- 默认只显示歌词文字和必要的层级；
- transparent 模式无大面积灰底；
- light material 只提供可读性背景，不变成主窗口；
- unlocked hover 时才出现轻量拖动/锁定/穿透/关闭控制；
- locked 或 pass-through 时完全隐藏非必要控件；
- 多行、Ruby、罗马音和翻译继续由共享 live lyric projection 驱动。

## 7. 建议复用、重写、禁止复制

### 可以复用的设计思想

- 用稳定 display UUID 或等价屏幕身份，不用 `localizedName` 作为唯一键。
- 用 `NSScreen.visibleFrame`、safe area 和统一 clamp 计算顶部安全位置。
- 用一个 Controller 管理一个 panel 的创建、显示、隐藏、销毁和订阅清理。
- 用显式 `collapsed / hover / expanded` 状态机，并对 hover debounce 任务做取消。
- 用 content-driven 的尺寸 envelope，内容变化只影响必要的宽高。
- 用嵌套 shape 的同心 inset、连续圆角和低对比阴影。
- 用 screen-parameter notification 对屏幕变化做重定位或安全回位。
- 将 outside click、mouse monitor 和拖动生命周期绑定到窗口 Controller，退出时对称移除。

### 必须由我们独立重写

- 读取 `PlaybackState` 的 live-only projection；
- 胶囊的一行当前歌词投影；
- 透明桌面歌词的多行字幕布局；
- 与 `LyricsSessionController`、`TranslationSessionController`、`AppSettingsStore` 的共享接线；
- 不产生第二个 polling timer、歌词计时器或音乐管理器；
- `.floating` window level、非激活行为、穿透恢复和现有 WindowManager 协调；
- Apple 语义区域在 macOS 尺寸和用户设置下的响应式规则。

### 本项目禁止复制或引入

- boring.notch 或 Atoll 的 GPL-3.0 Swift 源码、Shape、ViewModel、音乐管理器、动画库和资源；
- Atoll 的派生代码、NOTICE 中涉及的上游实现和其原创素材；
- DynamicNotch 的 MIT 源码，即使 MIT 允许再使用，本项目本轮也不复制；如果未来单独复用，必须保留版权和许可证文本，并重新审计其依赖；
- SkyLight/CGSSpace 等私有或未必要的窗口空间 API；
- `.mainMenu + 3`、`.statusBar + 8`、屏幕保护级别等过高 window level；
- 其他项目的 `TimelineView` 音乐计时路径；
- Apple Design Resources 模板、图标、组件或其他资源文件进入正式 App。

## 8. 许可证和授权风险

### Apple 资源

Apple Design Resources 的许可面向软件界面 mockup 和设计表达，不应理解为允许把模板资源作为 App 资源发布。本项目可以用它研究区域、边距和信息层级；实现时使用自己的 SwiftUI/AppKit 代码和自己的视觉资源。

### GPL-3.0 项目

boring.notch 和 Atoll 均为 GPL-3.0；Atoll 还明确说明其部分实现源自 boring.notch。将其代码或实质性派生代码嵌入当前项目，会引入源代码提供、衍生作品许可和交互界面法律通知等义务，和当前项目的分发策略未必兼容。因此本轮只研究机制，不复制任何代码。

### MIT 项目

DynamicNotch 根目录为 MIT，原则上允许使用、修改和再分发，但必须保留版权与许可证声明；其依赖、素材和衍生项目仍需单独检查。许可证允许并不等于本项目适合直接采用。本轮不导入源码，以避免把文件投递逻辑和高层级窗口行为带进正式实现。

## 9. 下一轮 mockup 的明确输入

下一轮如果继续绘制 mockup，应按以下输入，不再重新画 Control Center 播放器卡片：

1. **语义区域版胶囊：** 在 collapsed 图中明确标注 compact-leading 与 compact-trailing；在 expanded 图中标出 leading、center、trailing、bottom 的信息职责。
2. **保持产品冻结：** Expanded 只显示一行当前歌词，不显示下一行、不显示多行歌词、不显示完整翻译段落。
3. **三种窗口环境：** 有 notch Mac、无 notch 外接屏、屏幕安全区域变化；展示顶部锚点和 safe-area inset，而不是复制 iPhone 尺寸。
4. **动态尺寸 envelope：** 长标题、多艺人、无封面、无歌词和长当前行分别显示优先级降级：先收紧辅助信息，再截断低优先级文本，绝不裁掉当前行原文。
5. **同心边距与圆角：** 画出外层 shell、内层内容 inset、可选极弱 keyline tint，避免粗边框和灰色大面板。
6. **共享锚点动画：** 用静态前后帧或简短说明表示 compact→expanded 的元素位置保持，不使用明显弹簧或大幅位移。
7. **Reduce Motion：** 设计一组 opacity/crossfade 版过渡，不要 blur morph、回弹或长距离移动。
8. **桌面歌词继续独立：** transparent、light material、unlocked hover 三张状态图；不画成胶囊 expanded 的放大版。
9. **可读性边界：** 浅色桌面、深色桌面、复杂封面背景和低对比封面四种对照；确认文字阴影/描边的最小介入。
10. **版本说明：** mockup 标记为 `capsule.controlFocused.v2`、`floatingLyrics.transparent.v2` 等 presentation ID；不把这些设计稿误认为已实现版本。

## 10. 最终建议

建议下一轮只做“Apple 语义区域 + Lyric Island 自有窗口”的高保真 mockup，随后再由用户确认：

- collapsed 是否采用左右双区域而不是连续横排；
- Expanded 的一行歌词是 center 还是 bottom 的主信息；
- Light Material 的可接受透明度和 keyline tint 强度；
- 无 notch 外接屏是否使用同样的顶部 pill envelope；
- 是否在 Release Experience Library 中保留 `minimal` 预览。

在这些视觉输入确认前，不开始 Phase 2.3 SwiftUI 实现。本报告不改变当前 capsule mockup，也不改变现有业务架构。

## 附录：公开来源

- [boring.notch GitHub](https://github.com/TheBoredTeam/boring.notch)
- [Atoll / DynamicIsland GitHub](https://github.com/Ebullioscopic/Atoll)
- [DynamicNotch GitHub](https://github.com/winstonkhoe/DynamicNotch)
- [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.html)
- [MIT License](https://opensource.org/license/mit)
