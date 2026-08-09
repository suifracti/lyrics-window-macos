# lyricsQ

## Spotify Lyrics for macOS

**A native Spotify lyrics app for Mac, designed exclusively for Spotify Desktop on macOS.**

lyricsQ 会跟随 Spotify Desktop 当前播放的歌曲和进度显示歌词。你可以在主窗口里看歌词，也可以把歌词放到桌面、全屏或屏幕顶部；找不到合适版本时，还能导入、粘贴和编辑自己的歌词。

这是一个正在开发的个人项目。目前提供源码，没有正式 Release、签名安装包或稳定版本。

## 它能做什么

### 跟随 Spotify 播放

- 读取 Spotify Desktop 当前歌曲、播放状态和进度。
- 按时间轴滚动同步歌词，并突出当前行。
- 在应用内进行播放、暂停、切歌和进度跳转等基础控制。

### 用不同方式显示歌词

- **主窗口**：在专辑信息、播放控制和歌词之间提供完整视图；当前包含经典伴随、专辑沉浸和实验工作台三种布局。
- **桌面歌词**：把歌词作为独立悬浮窗口放在其他应用旁边。
- **全屏歌词**：只保留适合远距离查看的歌词画面。
- **顶部胶囊**：用更紧凑的窗口查看歌曲与歌词状态。

### 查找并选择歌词版本

lyricsQ 会优先使用本地歌词和已经保存的版本，再按设置查询在线来源。不同结果可以作为独立版本保留，不会直接覆盖你编辑的内容。

| 来源 | 当前用途 |
|---|---|
| 本地文件与 SQLite | 读取导入、编辑或采用过的歌词版本 |
| AMLL | 按 Spotify 曲目身份读取社区排轴 |
| LRCLIB | 搜索同步歌词或纯文本歌词 |
| 网易云、QQ 音乐 | 可选实验来源，接口和结果都可能变化 |

### 翻译、读音与纠错

- 在原文旁显示翻译版本。
- 为日语歌词显示假名、罗马音和上下文读音。
- 对错误读音和歌词内容进行歌曲级编辑与保存。

这些内容来自歌词版本、第三方来源或用户自己的编辑；应用不能保证翻译和读音始终正确。

### 导入和整理自己的歌词

- 导入 LRC 或 TXT 文件。
- 直接粘贴纯文本歌词并进入编辑预览。
- 修改歌词、翻译和时间轴，并把新版本保存在本地。
- 在没有同步歌词时尝试自动排轴。自动排轴仍是实验功能，可能需要屏幕录制或系统音频权限，也可能无法得到可用结果。

## 运行要求

- macOS 14 或更高版本
- Spotify Desktop
- Xcode（从源码构建时）

## 从源码运行

```sh
git clone https://github.com/suifracti/lyricsQ.git
cd lyricsQ
open SpotifyLyrics.xcodeproj
```

也可以直接使用命令行构建 Debug 版本：

```sh
xcodebuild -project SpotifyLyrics.xcodeproj \
  -scheme SpotifyLyrics \
  -configuration Debug \
  -derivedDataPath /tmp/lyricsq-deriveddata \
  CODE_SIGNING_ALLOWED=NO build
```

涉及 ScreenCaptureKit 或本机权限的调试可能需要本地开发签名。个人 Team ID、证书和其他凭据不应提交到仓库。

## 数据与网络

- 歌词、编辑版本和索引默认保存在 `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3`。
- Spotify 授权令牌和用户填写的 AI API Key 使用 macOS Keychain；仓库不包含可用凭据。
- 使用在线歌词来源时，匹配歌曲所需的标题、歌手、专辑、时长或曲目 ID 会发送给对应服务。
- 使用用户自行配置的 AI 翻译服务时，歌词文本和请求会发送到该服务端点。
- 自动排轴可能读取 Spotify 进程音频；所选语音识别后端可能有自己的权限和数据处理规则。

## 当前限制

- 在线歌词的命中、时间轴和翻译质量取决于歌曲元数据与第三方来源。
- 网易云和 QQ 音乐接入使用非官方实验接口，可能失效，也不代表正式发行承诺。
- 日语读音在姓名、罕见词和多音词上仍可能出错。
- 自动排轴、实验工作台以及部分界面仍在测试和验收。
- 当前没有正式 Release、SemVer 标签、签名安装包或完整发布流程。

更细的实现状态见 [`docs/STATUS.md`](docs/STATUS.md)。

## 测试

仓库在 `Tests/` 下使用按模块划分的合同脚本。文档修改不需要重新构建应用；修改功能时应运行对应合同与 Debug 构建。基础入口为：

```sh
bash Tests/v3_lyric_readability_contract.sh
```

开发和提交边界见 [`docs/DEVELOPMENT_WORKFLOW.md`](docs/DEVELOPMENT_WORKFLOW.md)。

## 版权与说明

lyricsQ 与 Spotify、Apple、AMLL、LRCLIB、网易云音乐或 QQ 音乐没有隶属或背书关系。音乐平台名称、商标、歌词、专辑封面和其他第三方内容归各自权利人所有。

本仓库公开可见，但不是开源软件。原创源码、文档和设计内容保留全部权利；公开可见不代表获得使用、复制、修改或再分发许可。详见 [`LICENSE`](LICENSE)。
