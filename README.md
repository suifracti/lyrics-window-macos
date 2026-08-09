# Lyrics Window for macOS

一个仍在开发中的原生 macOS 歌词窗口，主要用于配合 Spotify Desktop 显示、查找和整理歌词。

当前仓库是源码开发现场，不是已经发布的成品：没有正式 Release、签名安装包或稳定版本，需要使用 Xcode 自行构建。项目不隶属于 Spotify、Apple 或任何歌词服务。

## 当前包含的内容

- 读取 Spotify Desktop 的当前歌曲和播放状态，并提供基础播放与进度控制。
- 提供主窗口、悬浮歌词、全屏歌词和顶部胶囊等显示界面。
- 导入本地 LRC/TXT、直接粘贴和编辑歌词，并将用户版本保存在本地 SQLite 数据库。
- 查询本地版本、AMLL 和 LRCLIB；网易云与 QQ 查询属于可选的实验来源。
- 显示同步歌词、翻译伴随层，以及日语假名、罗马音和上下文读音。
- 包含翻译、歌词候选、读音纠错和自动排轴的开发中实现。

这些条目只表示当前源码中存在相应实现，不表示它们已经达到发布质量。

## 已知限制

- 在线歌词的命中率、时间轴和翻译内容取决于歌曲元数据与第三方来源，不能保证正确或完整。
- 网易云和 QQ 使用非官方实验接口，可能随时失效，也不作为正式发行能力承诺。
- 日语读音仍可能在姓名、罕见词和多音词上出错。
- 自动排轴仍是实验功能，不能视为可靠的零操作歌词时间轴方案。
- 实验工作台和部分界面仍在验收；性能、长期运行稳定性、打包、签名和发布流程尚未完成。

更细的实现状态见 [`docs/STATUS.md`](docs/STATUS.md)。

## 数据与网络

- 歌词、编辑版本和相关索引默认保存在 `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3`。
- Spotify 授权令牌和用户填写的 AI API Key 使用 macOS Keychain；仓库不包含可用凭据。
- 启用在线歌词来源时，应用会把匹配所需的歌曲标题、歌手、专辑、时长或曲目 ID 发送给相应服务。
- 使用用户自行配置的 AI 翻译服务时，歌词文本和翻译请求会发送到该服务端点。
- 实验性自动排轴可能请求 macOS 的屏幕录制/系统音频权限，以读取 Spotify 进程音频并生成时间轴；所选语音识别后端可能另有权限与数据处理规则。

请先了解并接受相应第三方服务的条款与隐私规则，再启用在线能力。

## 环境要求

- macOS 14 或更高版本
- Xcode
- Spotify Desktop

## Debug 构建

```sh
xcodebuild -project SpotifyLyrics.xcodeproj \
  -scheme SpotifyLyrics \
  -configuration Debug \
  -derivedDataPath /tmp/lyrics-window-macos-deriveddata \
  CODE_SIGNING_ALLOWED=NO build
```

涉及 ScreenCaptureKit 或本机权限的调试可能需要本地开发签名；个人 Team ID 与证书不应提交到仓库。

## 测试

仓库在 `Tests/` 下使用按模块划分的合同脚本，没有一个命令能替代全部验证。文档中的基础入口是：

```sh
bash Tests/v3_lyric_readability_contract.sh
```

修改特定模块时，还需要运行对应的聚焦合同和 Debug 构建。

## 项目边界

- 当前没有正式 Release 或 SemVer tag。
- Git `main` 是默认源码基线；精确状态应以当前提交和工作区差异为准。
- `.local/`、DerivedData、数据库、凭据、本地签名文件、参考仓库和普通构建产物不属于可发布源码。
- 歌词、专辑封面、音乐平台名称、商标和第三方服务均归各自权利人所有。本项目不授予这些内容的任何权利。

开发与构建边界见 [`docs/DEVELOPMENT_WORKFLOW.md`](docs/DEVELOPMENT_WORKFLOW.md)。

## 版权与使用

本仓库不是开源软件。原创源码、文档和设计内容保留全部权利；仓库公开可见不代表获得使用、复制、修改或再分发许可。第三方内容仍按各自条款处理，详见 [`LICENSE`](LICENSE)。
