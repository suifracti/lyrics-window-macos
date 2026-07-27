# UI Layout Audit — Phase 2

日期：2026-07-27
范围：主窗口布局切换与两个功能 Bug 之后的 UI 设计审计。悬浮歌词、顶部胶囊、全屏歌词、Spotify 后端、SQLite 和 AI 不在本阶段改动范围内。

本阶段的主要设计参考收敛为两个来源：Dynamic Lyrics 的黑盒行为，以及 Lyricify 公开资料中的 Apple Music 歌词模式。Music.app 和 Apple HIG 只作为 macOS 窗口、材质、可调整大小和可读性的辅助约束，不作为视觉样板。

## 1. 审计边界与许可证结论

- 正式项目是 `/Users/apple/backup/sptifylyrics`。
- `Lyricify-App-main/` 只读。按要求首先读取 `Lyricify-App-main/LICENSE`，结果为文件不存在；仓库内也没有 `LICENSE*` 或 `COPYING*`。因此不能把该 checkout 的截图、主题、图标或资源当作当前项目可复用资产，也不把缺失许可证解释成“允许复制”。
- `/Applications/Dynamic Lyrics.app` 只做黑盒观察：截图、窗口帧、Accessibility 树和交互。没有反编译、二进制修改、重签名、资源提取或实现恢复。
- Music.app 只做本机可见界面观察，不接受首次运行协议或订阅，也不改变账户/媒体状态。

## 2. Lyricify-App-main：实际文件与可借鉴内容

### 实际读取的文件

- `README.md`
- `docs/Lyricify 4/README.md`
- `docs/Lyricify 4/Lyrics.md`
- `docs/Lyricify 4/settings.json`
- `images/readme/func-lyrics-display.png`
- `images/readme/func-lyrics-am-duet.png`
- `images/readme/func-lyrics-am-highlight.png`
- `images/readme/func-lyrics-am-multiline.png`
- `images/readme/func-lyrics-dynamic-lyrics-island.png`
- `images/readme/func-lyrics-desktop.png`
- `images/readme/func-lyrics-vertical.png`
- `images/readme/func-lyrics-fulscreen.png`
- `images/readme/func-lyrics-mobile-ui.png`

仓库中没有可发现的 Swift/C#/XAML UI 源码；`i18n/` 是语言文案，`resources/theme/` 是参考主题资源，不作为实现来源。

### 模式、入口与持久化结论

公开文档描述了主歌词、Apple Music 歌词、桌面歌词、全屏歌词和动态顶部入口。主界面把歌曲信息放在左下、播放控制放在底部中央、功能按钮放在右下；Apple Music 歌词通过一个独立入口进入；窄窗口会切换竖向排列。`settings.json` 是设置示例，保存 `window_main`、`apple_music_lyrics`、`dynamic_lyrics_island` 和 `desktop_lyrics` 的位置、尺寸、字号、模糊、动画以及 `is_opened` 等字段，但没有真实枚举或切换实现可供复制。

可借鉴的只是通用信息架构：上下文菜单承载低频设置、播放控制始终可达、歌词区域对当前行建立清晰层级、窗口尺寸变化触发布局重排。SpotifyLyrics 使用独立的 SwiftUI 组合和自己的命名、token 与交互。

## 3. Dynamic Lyrics：黑盒观察

新鲜 AX 状态包含：封面、歌曲名 `SAD SONG`、艺人 `CHANMINA`、喜欢/更多、时间、上一首/暂停/下一首、双语滚动歌词列表、翻译按钮、搜索按钮和系统窗口控件。截图中的主窗口约 1000×650：左侧为大封面和底部播放区，右侧为歌词；背景使用封面派生的暖色模糊纹理并覆盖可读性遮罩。当前双语行最大最亮，相邻行可读但更淡，远处行才明显模糊。

WindowServer 只读记录到主窗口 1000×650，以及两个独立高层辅助窗口 610×200 和 600×78。辅助窗口的尺寸不能单独证明其收起/展开语义；顶部胶囊展开态在本轮标为未验证。更多菜单将歌词延时、模糊、字号、对齐、分享、报错和纯音乐开关收纳在上下文菜单中。

观察截图仅存于 `ui-reference-audit-assets/`，包括 `dynamic-main-initial.png`、`dynamic-main-paused.png`、`dynamic-fullscreen.png` 和 `dynamic-floating.png`；不包含 Dynamic Lyrics 的应用资源。

## 4. Music.app：本机观察

当前 Music.app 的 AX 树显示真实 macOS 外壳：搜索、主页、广播、资料库、最近添加、艺人、专辑、歌曲、商店侧栏，账户按钮，以及迷你播放器中的随机、上一首、播放、下一首、重复、播放中、歌词、待播清单、隔空播放和音量入口。当前没有活动歌曲，运输控制为禁用，主页显示订阅营销内容，因此本轮不声称已观察到 Apple Music 的真实歌词滚动或播放态视觉。可确认的通用模式是：持久的紧凑播放条 + 独立歌词入口，而不是常驻设置面板。

## 5. Apple 官方依据

- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)：选择系统材质和 `behindWindow`/`withinWindow` 混合方式；用 vibrancy 保持前景可读，避免不必要的不透明遮挡。
- [Windows](https://developer.apple.com/design/human-interface-guidelines/windows)：macOS 窗口可移动、可调整大小，有系统窗口控件，并区分 main/key 状态。
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)：布局应随窗口和上下文动态适配；SwiftUI 的布局工具可保持内容关系。
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)：利用宽阔桌面空间并支持个性化。
- [Apple Design Resources](https://developer.apple.com/design/resources/)：提供官方 macOS UI Kit 与系统字体资料；本项目不导入 Apple 专有素材。

## 6. 当前 SpotifyLyrics 与目标差异

| 区域 | 当前状态 | 本阶段目标 |
| --- | --- | --- |
| 主窗口布局 | 只有纵向歌词焦点组合 | 保留原组合，并增加可即时切换的沉浸分栏组合 |
| 封面 | 已接真实 artwork，但焦点布局中的视觉中心不足 | 分栏模式左侧大封面；背景与封面 identity 绑定 |
| 歌词列 | 当前行突出，远行 blur 偏重 | 相邻行优先用透明度，保留可读性；更远行才轻 blur |
| 播放器 | 控件共享但与封面/歌词关系弱 | 分栏左列承载元数据、进度和上一首/播放/下一首 |
| 状态条 | Spotify 正常连接时占用整条内容宽度 | 正常连接收进 toolbar/menu；失败仍提供明确操作反馈 |
| 宽度适配 | 焦点布局在宽窗口有空白 | 分栏模式宽时双列，窄时堆叠，不硬挤双栏 |
| 设置入口 | 已有 popover | 增加布局样式切换并持久化，不重置播放或歌词位置 |

## 7. 独立设计规范

- `lyricsFocus`：当前纵向歌词画布保持为默认兼容模式，顶部元数据、中央歌词列、底部播放条不改变业务语义。
- `immersiveSplit`：宽窗口使用约 38%–44% 的左列；封面采用 1:1 中等大尺寸，下面是歌名/艺人、收藏/更多、进度和三键控制；右列为可滚动歌词视口。背景由真实 artwork 的渐变、放大裁切纹理、模糊和暗色可读性遮罩组成。
- 小于约 900pt 的可用宽度时，切换为上下堆叠：封面与控制在上，歌词在下；不压缩到不可读。
- 默认窗口 1040×680，最小窗口 760×520；两种模式都遵守现有窗口约束。
- 字体使用系统字体；当前原文为最大层级，翻译次级，罗马音/假名更小更淡；相邻一两行不超过轻微 blur，远行再增加 blur。
- 圆角、间距、透明度和动画统一由 `LyricsDesignTokens` 提供；模式切换用短淡入/布局过渡，不重新创建播放或歌词会话。
- 深色优先；浅色外观保留材质和可读性遮罩的对比逻辑，不使用大面积纯白卡片。

## 8. 拟修改文件（实现前清单）

### 新增

- `SpotifyLyrics/Design/MainWindowLayoutStyle.swift` — `lyricsFocus`/`immersiveSplit` 枚举、显示名和持久化 raw value。
- `SpotifyLyrics/Views/MainWindow/ImmersiveSplitWindowView.swift` — 分栏/窄宽堆叠组合，只接收共享状态和动作。
- `SpotifyLyrics/Views/Components/ArtworkView.swift` — 统一封面/占位/加载失败显示。
- `SpotifyLyrics/Views/Components/TrackMetadataView.swift` — 歌曲名、艺人、收藏/更多。
- `SpotifyLyrics/Views/Components/PlaybackControlsView.swift` — 上一首、播放/暂停、下一首和进度。
- `SpotifyLyrics/Views/Components/LyricsViewport.swift` — 共享歌词滚动视口和状态/候选/重试呈现。
- `SpotifyLyrics/Views/Components/ArtworkBackgroundView.swift` — 共享真实封面背景、渐变、纹理和遮罩。
- `Tests/phase2_layout_contract.sh` — 先于 UI 生产代码运行的红色布局合约。

### 修改

- `SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift` — 用 `@AppStorage` 保存布局样式，组合两个布局，保留共享 `PlaybackState` 与现有设置入口。
- `SpotifyLyrics/Views/Components/TrackHeaderView.swift` — 仅在抽取可复用元数据/封面后保留兼容包装，不改变业务状态。
- `SpotifyLyrics/Views/Components/LyricsCanvasView.swift` — 如需要仅抽取到 `LyricsViewport`，保持当前歌词状态和安全 seek 规则。
- `SpotifyLyrics/Design/LyricsDesignTokens.swift` — 增加分栏比例、窄宽断点、间距和层级 token。
- `SpotifyLyrics.xcodeproj/project.pbxproj` — 将新增 Swift 与合约文件加入 target；不修改产品功能或辅助窗口。
- `task_plan.md`、`findings.md`、`progress.md` — 记录阶段状态和验证证据。

明确不修改：`SpotifyLyrics/Views/LyricsViews.swift`、Spotify Provider、歌词 Provider、SQLite、AI、MockData 的语义。

## 9. 分阶段实现与验收

1. **红色合约**：检查枚举、持久化 key、共享状态注入、响应式断点和未触碰辅助窗口；预期先失败。
2. **共享组件**：抽取封面、元数据、控制、歌词视口和背景；组件测试/Debug build 通过。
3. **布局组合**：接入 `lyricsFocus`/`immersiveSplit` 即时切换；切换前后 Track identity、播放位置、歌词状态和背景 key 不变。
4. **运行验收**：用签名 Debug 产物验证真实封面、真实歌词、进度、三键控制、默认/最小尺寸和运行中切换；分别保存 `ui-redesign-assets/phase2-lyrics-focus.png` 与 `phase2-immersive-split.png`。
5. **提交**：UI 改造单独提交，提交信息为 `Add switchable immersive main layout`；不得与前一提交合并。
