# 顶部胶囊最终版 V1 验收记录

日期：2026-08-01
工作区：`/Users/apple/backup/sptifylyrics`
基线：`8c589f8cb18826f861484d36f7a792e8404352f6`

## 构建与进程

- Debug App：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`
- 构建方式：正常签名 Debug `xcodebuild`
- 结果：`BUILD SUCCEEDED`
- 代码签名：`codesign --verify --deep --strict` 通过
- 最终验收进程：PID `12655`
- 进程来源：
  `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`

## 自动化合同与回归

使用各脚本自己的 shebang 解释器运行全部 `Tests/*.sh`，避免把 zsh 的 `${0:A:h}` 当成 bash 语法。

结果：**40/40 PASS**。

新增胶囊合同：

- `capsule_lyrics_contract.sh`
- `capsule_window_behavior_contract.sh`

覆盖：live-only projection、前奏空状态、纯文本和未排轴不伪同步、noMatch/候选/失败状态、原文与时间戳保持、NSPanel 单例约束、三档尺寸、顶部回位、屏幕观察、outside-click、350ms hover debounce、显式 Slider seek、无第二个 timer/provider/session/network、旧直接胶囊入口移除。

## 真实 App 验收

### 恋風 / Lilas

- Spotify Desktop 实际播放并被当前 Debug App 识别。
- 主窗口实际显示 `恋風 / Lilas`，同步歌词列表为 42 行；SQLite 中 LRCLIB 版本也核对为 42 行同步歌词。
- 胶囊实际显示歌曲封面、标题、艺人和当前歌词投影；展开态实际显示当前行与下一行，使用共享的原文/Ruby/罗马音/翻译渲染层。
- 实际点击主播放控制进行播放/暂停，播放位置从约 `01:00` 前进到约 `01:13`，暂停后状态回到真实 Spotify 状态。
- 胶囊展开/收起本身未触发 seek；Slider 只有 `onEditingChanged(false)` 且存在用户拖动值时调用 `state.seek`，由合同和代码路径保护。

### 水曜日の約束 / Kawasaki.Rio

- Spotify Desktop 实际搜索并播放了正确曲目：Spotify ID
  `spotify:track:5MqkkCSrUjqyaKVOlvEn0w`，时长约 `2:51`。
- 当前正式数据库中存在两个 QQ 纯文本版本（32 行、时间字段为空），也存在此前人工导入/人工排轴的锁定版本。按照共享版本选择规则，App 当前实际恢复的是锁定的 `manualEdit` 32 行同步版本，因此真实画面显示同步行属于当前被选中的版本，而不是 QQ 纯文本版本。
- 为防止旧/手工记录错误地把 `isSynchronized=true` 与全零时间戳组合成伪同步，胶囊 projection 增加了 timing-evidence fail-closed 保护：没有正的时间证据或结束时间证据时显示 `纯文本 / 未排轴`，不显示第一行。
- 本轮没有修改正式数据库、没有删除用户版本；要单独验收 QQ 纯文本画面，应在编辑器选择 QQ 版本或使用独立测试数据库，不能把现有锁定排轴版本误判为 QQ 纯文本回归失败。

### あやふや / みさき

- Spotify Desktop 实际搜索并播放了正确曲目：`あやふや / みさき`。
- 主窗口实际显示 `暂无歌词`。
- 胶囊实际显示歌曲标题、艺人和 `未找到歌词`，没有残留水曜日の約束或恋風的歌词、翻译和封面状态。

### 快速切歌与共享状态

- 已实际完成水曜日の約束 → あやふや 的切歌验证：主窗口标题和歌词状态从 32 行内容切换为 `暂无歌词`，胶囊没有保留上一首的歌词。
- A→B→A 的完整三段连续物理操作未作为独立证据保存；状态清空、revision/identity 防迟到结果由现有 session contracts 与 live projection contracts 覆盖。
- 悬浮歌词与顶部胶囊同时存在：窗口列表实际同时出现两个 layer-3 SpotifyLyrics 窗口，分别为浮动歌词约 `620×221` 和胶囊 `360×46`，没有创建第二个播放器 polling timer。

## 窗口行为实测

- collapsed：`360×46`，位于当前主屏幕顶部安全区域，实测 bounds 约 `X=1100, Y=40`。
- expanded：`620×220`，同一屏幕顶部安全区域内，实测 `X=970, Y=40`。
- 收起后回到 `360×46`。
- 重启后只在 `restoreWindowState && capsuleWindowWasVisible` 时恢复，并始终从 collapsed 开始；可见性和屏幕 ID 已在 UserDefaults 中持久化。
- 同时打开悬浮歌词不互相关闭，两个 Controller、panel、frame key 和 visibility state 独立。
- 鼠标穿透解除入口保留在 App 菜单，不依赖点击悬浮窗本身。

## 未实测项目

以下项目没有在当前物理环境中作完整硬件实测，未宣称通过：

- 外接显示器物理拔出后的真实窗口回位；
- 屏幕排列变化、不同缩放比例和全屏 Space 的物理组合；
- 胶囊 expanded 状态下的真实鼠标拖动和 Slider 拖动；
- 完整的 A→B→A 三段连续切歌录像级验收；
- 手工编辑器完整 UI 与胶囊同步的长流程。

这些路径已有合同、屏幕参数观察和共享 session/revision 保护；后续可在用户环境中补做物理验收。

## 关键范围结论

- 顶部胶囊使用独立 `NSPanel`/`WindowController`，window level 为 `.floating`，不是 `.statusBar` 或 `.modalPanel`。
- 胶囊只读取 `PlaybackState.liveLyrics`、`liveLyricsState`、`liveCurrentLineIndex`、`liveLyricsAreSynchronized` 和共享显示设置，不读取可被搜索预览替换的 `state.lyrics`。
- 没有新增 Spotify polling timer、PlaybackProvider、歌词搜索、翻译状态或歌词缓存。
- 旧的 WindowManager 直接创建胶囊 `NSWindow` 路径已移除；`CapsulePlayerView` 仅作为既有兼容符号保留，不再是正式窗口入口。
