# 悬浮歌词最终版 V1 验收记录

日期：2026-08-01
基线：`8aea61f8764b2b0f8cca61224db418df558710c1`
交付：本次独立悬浮歌词实现提交（本文件与实现一起提交）

## 范围

本次只实现悬浮歌词窗口正式接线、窗口生命周期、三种交互状态、共享歌词投影和纯文本/同步歌词展示。没有新增歌词 Provider、AI 请求、自动排轴算法、查询匹配逻辑或主窗口视觉模式。

## 运行二进制

使用的唯一 App：

`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`

构建后观察到的进程来源：

`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`

本次重建后观察到 PID `97767`。PID 仅作为当次运行记录，不作为持久配置。

## 架构与共享数据链

```text
PlaybackState
  ├─ liveLyrics / liveLyricsState / liveCurrentLineIndex
  └─ AppSettingsStore（显示层与窗口偏好）
        ↓
WindowManager.shared
        ↓ 单例
FloatingLyricsWindowController
        ↓ 单一 NSPanel
FloatingLyricsView
```

悬浮歌词只读取当前共享 `PlaybackState` 的 live projection，不创建第二个播放器轮询、歌词搜索、翻译会话、时间轴计算器或独立歌词缓存。歌词文档/翻译/读音变化重建 projection；播放位置变化只更新当前行和可见邻近行。

## 三种交互状态

- `interactive`：可拖动、缩放、操作窗口；不鼠标穿透。
- `locked`：保留位置和尺寸，隐藏非必要控件，但仍可点击。
- `passThrough`：设置 `ignoresMouseEvents`，不接收普通鼠标事件。

鼠标穿透可通过 App 菜单“解除悬浮歌词鼠标穿透”及快捷键恢复，不依赖点击悬浮窗本身。窗口关闭只 `orderOut`，不会退出 App；重复打开复用同一个 panel/controller。

窗口使用合理的 floating panel level、`canJoinAllSpaces` 和 `fullScreenAuxiliary`，并保存 frame、屏幕身份、显示状态、交互模式与透明度。恢复时会按当前可见屏幕进行 clamp，避免窗口出现在屏幕外。

## 歌词展示

### 同步歌词

使用现有时间轴和 `PlaybackState` 当前行，窗口只渲染当前行附近的稳定 projection（当前行及前后有限行）。暂停不会启动额外进度动画；seek 后由共享播放位置立即重新计算当前行；切歌先清空旧 projection，迟到结果由 session revision/identity 保护。

### 纯文本歌词

没有可靠时间轴时显示“纯文本 / 未排轴”，使用普通手动滚动全文，不生成当前行、不自动滚动、不按歌曲总时长平均切行。

## 合同测试

以每个脚本自身声明的 shell 执行全部 `Tests/*.sh`：

```text
SUMMARY scripts=38 pass=38 fail=0
```

新增/修改的悬浮相关覆盖：单例窗口、显示隐藏生命周期、frame 持久化、屏幕回位、三种交互状态、穿透恢复入口、纯文本不伪同步、同步当前行/seek、切歌清空、共享设置和 session、无第二 polling timer、无隐式 seek。全套既有歌词、SQLite、翻译、读音、编辑器和自动排轴合同也通过。

## 真实 App 验收

### 恋風 / Lilas

- Spotify Desktop 实际播放，曲目时长约 182 秒。
- 当前加载 42 行同步歌词，悬浮窗实际显示原文、Ruby 假名、罗马音和翻译。
- 生产数据库当前优先恢复的是已锁定的人工派生 42 行版本（`manualEdit`），不是原始 LRCLIB 行；这证明了共享“当前选中版本”链路，但不把人工派生误报为 LRCLIB 直接展示。
- 暂停时记录位置约 `60.885s`，恢复后约 `67.724s`，播放位置继续前进。
- 打开、关闭、拖动和显示切换没有触发隐式 seek。

截图：

- `/tmp/spotifylyrics-floating-final-production.png`
- `/tmp/spotifylyrics-floating-final-resume.png`
- `/tmp/spotifylyrics-floating-final-v1-postbuild.png`

### 水曜日の約束 / Kawasaki.Rio

- 为避免修改正式数据库，使用临时 SQLite `/tmp/SpotifyLyrics-floating-water-test.sqlite3`，仅保留 QQ 的 32 行纯文本版本。
- App 重启后日志确认 `sync=false`、`alignmentQueued`、32 行；主窗口和悬浮窗显示纯文本/未排轴，不自动切行。
- 临时数据库已删除，正式歌词库未被本次测试污染。

截图：`/tmp/spotifylyrics-floating-water-test.png`

### あやふや / みさき

- 在隔离临时数据库中运行真实 Provider 链，最终为 `noMatch`。
- 没有正文，没有创建空歌词版本；UI 显示无歌词状态。
- 临时数据库已删除。

### 窗口生命周期与模式

- 菜单切换 `passThrough → interactive` 可恢复；`locked` 可设置。
- 隐藏/显示后窗口仍为单一实例，显示状态持久化。
- 关闭悬浮窗不退出主 App。

## 构建与签名

- `xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug -derivedDataPath /Users/apple/backup/sptifylyrics/DerivedData build`：`BUILD SUCCEEDED`
- App：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`
- `codesign --verify --deep --strict`：通过
- 签名标识：`com.spotifylyrics.app`，`Sign to Run Locally`（Debug ad hoc）
- `git diff --check`：通过

## 尚未验证或仅由合同覆盖的项目

- 实际拔掉保存悬浮窗位置的物理显示器后的回位行为尚未在本次运行中执行；代码路径和合同检查已覆盖屏幕变化/clamp。
- 本次没有再次完整执行编辑器保存、自动排轴子版本采用的 UI 流程；共享版本刷新和防串歌由实现及合同覆盖。
- 没有把 TTS、合成音频或不匹配音频作为商业歌曲排轴验收；自动排轴真实商业歌曲状态仍按前一阶段保持 `UNVERIFIED`。
- 未进行长时间压力测试；实现已避免悬浮窗创建第二个高频 timer，并在隐藏时停止不必要的窗口渲染。
