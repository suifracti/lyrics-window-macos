# 全屏歌词最终版 V1 验收记录

日期：2026-08-01

基线：`a9edc600b685a8c82e780769001d6e87a4d1496f`

范围：独立无边框全屏歌词窗口；不修改 Provider、AI、排轴算法、V2/V3 主窗口视觉、悬浮歌词或顶部胶囊业务。

## 构建与运行二进制

唯一运行 App：

`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`

进程来源核验：

`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`

构建后目标 App 进程 PID：`35662`；完成临时数据库回归并恢复正式数据库后，当前目标 App 进程 PID：`39677`。
HEAD：`a9edc600b685a8c82e780769001d6e87a4d1496f`。

- 正常签名 Debug `xcodebuild`：`BUILD SUCCEEDED`
- `codesign --verify --deep --strict`：通过
- `git diff --check`：通过

## 架构与共享数据

```text
PlaybackState
  ├─ liveLyrics / liveLyricsState / liveLyricsAreSynchronized
  ├─ liveCurrentLineIndex / currentTime / isPlaying
  └─ AppSettingsStore（既有显示设置）
        ↓
WindowManager.shared
        ↓ 单例 controller
FullScreenLyricsWindowController
        ↓ 单一无边框 NSPanel（.floating）
FullScreenLyricsView
```

全屏 View 只消费 live projection，并复用现有 `LyricLineView`、`AppleMusicImmersiveV3BackdropView`、`ArtworkView` 和 artwork/backdrop cache。没有新增播放器轮询、Provider、歌词搜索、TranslationSession、current-line calculator、歌词缓存或全屏专属设置。

WindowManager 保留唯一入口和 controller 引用；旧的直接 `NSWindow`/`.modalPanel` 正式路径已移除。panel `isReleasedWhenClosed = false`，重复显示/隐藏复用同一个实例，关闭只 `orderOut`，不退出 App。

## 真实性与状态行为

- 只有 `liveLyricsAreSynchronized == true` 且歌词存在有效正时间证据时进入同步展示。
- `alignmentQueued`、`alignmentRunning`、未确认 `alignmentPreview`、纯文本、全零时间轴均显示 `纯文本 / 未排轴` 或克制状态。
- 前奏 `liveCurrentLineIndex == nil` 时不显示第一句，避免提前歌词；有效 current index 只来自共享 PlaybackState。
- 同步展示只渲染当前行附近的有限 projection，seek 后通过共享 index 定位；不创建第二个计时器。
- 普通歌词点击、打开/关闭、鼠标 hover、控件淡出和窗口操作不 seek。Slider 仅在用户完成拖动时调用共享 `PlaybackState.seek`。
- 切歌/状态切换通过 live identity 和 session projection 清空旧内容；搜索预览 state 不会进入全屏。

## 辅助窗口编排

进入全屏前 WindowManager 记录悬浮歌词和顶部胶囊当时的可见状态，并临时 `orderOut`。全屏期间不销毁它们的 controller，不修改持久化 frame、可见性设置或交互模式；退出时只恢复此前实际可见的窗口，原本隐藏的不会被打开。主窗口保持存在。全屏 panel 使用 `.floating`、`canJoinAllSpaces` 和 `fullScreenAuxiliary`，目标屏幕按主窗口 screen → `NSScreen.main` → 首屏解析；屏幕参数变化时重新铺满目标屏幕。

本地 Esc monitor、panel keyDown、菜单项“显示/隐藏全屏歌词”和快捷键 `⌘⌥G` 都走同一个 WindowManager façade。Esc 只隐藏全屏歌词，不暂停 Spotify、不退出 App、不关闭主窗口。

## 合同测试

使用脚本声明的 shell 解释器运行全部 `Tests/*.sh`：

```text
SUMMARY scripts=42 pass=42 fail=0
```

另外单独编译运行 `Tests/fullscreen_lyrics_presentation_test.swift`：通过。

新增覆盖：

- live-only 读取和旧 preview state 禁止进入；
- 计时证据 fail-closed、前奏不提前显示、纯文本不伪同步；
- bounded current-line projection；
- loading/noLyrics/noMatch/candidates/failed 状态；
- 单例 panel、屏幕 fallback、Esc、关闭和无隐式 seek；
- V3 backdrop/cache 与共享 Ruby/假名/罗马音/翻译渲染复用；
- auxiliary window 临时隐藏/恢复；
- 保持唯一 `PlaybackState` polling timer。

## 真实 App 验收

### 恋風 / Lilas

Spotify Desktop 实际切换到 `恋風 / Lilas`，Debug App 日志确认当前 session 恢复 42 行同步版本（当前优先的是已锁定的人工派生版本）。全屏实际显示原文、Ruby、罗马音、翻译和共享 V3 artwork backdrop；外部明确暂停、改变播放位置并恢复后，全屏仍跟随共享播放状态，没有因打开/关闭全屏产生隐式 seek。

运行截图（测试产物，不作为歌词内容凭证）：

`/tmp/spotifylyrics-fullscreen-koikaze-runtime.png`

全屏 Slider 的实体鼠标拖动本轮仍未单独实测；通过 Spotify Desktop 的明确 seek 验证了共享位置响应。

### あやふや / みさき

Spotify Desktop 实际切换到 `あやふや / みさき`。真实 Provider 链完成后日志为 `noMatch`；全屏实际显示该曲标题/封面和“暂无歌词”，没有残留恋風或前一首的歌词、翻译和背景。运行截图：

`/tmp/spotifylyrics-fullscreen-ayafuya-runtime.png`

### 青春不打烊 / 王梓钰

作为另一首真实有同步歌词的运行样本，SQLite/session 日志确认恢复 LRCLIB 36 行同步歌词（`sync=true`）。全屏显示共享同步歌词和 V3 背景；运行截图：

`/tmp/spotifylyrics-fullscreen-final-runtime.png`

从 Window 菜单打开全屏后，Accessibility 窗口范围显示为整屏；Esc 后全屏窗口消失而 SpotifyLyrics 主进程仍存活。

此前同一目标 App 的多窗口运行验收也确认：全屏期间可临时隐藏已打开的悬浮歌词和顶部胶囊，退出后恢复进入前实际可见状态；未创建第二个 polling timer。

## 未实测 / 非阻塞项目

以下项目本轮没有在当前物理环境中完成完整硬件或长流程实测，明确标记为 `UNVERIFIED`：

- 水曜日の約束 QQ 纯文本版本与已有同步子版本的全屏双场景切换；
- 水曜日的纯文本版本/同步子版本切换，以及完整 A→B→A 连续切歌录像级验收；
- 人工导入/编辑器保存、automaticAlignment 子版本采用后的全屏长流程；
- 外接屏拔出、屏幕排列改变、不同缩放、多 Space 的物理组合；
- 全屏 Slider 实体拖动。

这些项目已有合同、共享 session/revision 防串歌和屏幕 fallback 保护；本报告不把合同通过写成上述真实场景已完成。

## 结论

本轮完成的是“独立单例 NSPanel + live-only 共享歌词接线 + 同步/纯文本真实性保护 + 辅助窗口临时编排 + 构建签名”的 V1 实现。未验证项目保留为后续真实环境验收，不影响本次代码提交。
