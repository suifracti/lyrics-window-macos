# Lyrics Window for macOS

一个个人使用的原生 macOS SwiftUI 歌词窗口，主要配合 Spotify Desktop 显示和管理歌词。

项目仍在开发中，不是 Spotify 或 Apple 的官方产品；歌词覆盖率、翻译和排轴效果会因歌曲与来源而异。

## 主要功能

- 从 Spotify Desktop 读取当前歌曲，并提供基础播放与进度控制。
- 提供经典伴随、专辑沉浸、歌词专注、悬浮、全屏和胶囊等显示方式。
- 支持导入本地 LRC/TXT、直接粘贴、编辑歌词，并保存到本地 SQLite。
- 支持本地歌词、LRCLIB，以及实验性的 AMLL、网易云和 QQ 来源查询，并可选择候选版本。
- 支持同步歌词、翻译/伴随层，以及日语上下文读音、假名和罗马音显示。
- 专辑沉浸窗口提供环境光、舞台封面和经典放大三种背景构图；模糊、封面尺寸和位置可以分别调整。

## 当前状态

核心窗口、歌词导入与保存、本地和在线查询及基础播放控制已经可用；歌词来源覆盖率、日语读音、翻译、自动排轴和视觉细节仍在持续打磨。更细的实现边界、当前开发分支和未完成项见 [`docs/STATUS.md`](docs/STATUS.md)。

这里列出的功能表示仓库中已有相应实现，不等于已经达到发布质量。

## 环境

- macOS 14 或更高版本
- Xcode
- Spotify Desktop

## Debug build

```sh
xcodebuild -project SpotifyLyrics.xcodeproj \
  -scheme SpotifyLyrics \
  -configuration Debug \
  -derivedDataPath /tmp/lyrics-window-macos-deriveddata \
  CODE_SIGNING_ALLOWED=NO build
```

## 核心合同测试

仓库使用 `Tests/` 下的聚焦合同脚本，没有一个可以替代全部验证的万能命令。文档入口为：

```sh
bash Tests/v3_lyric_readability_contract.sh
```

修改特定模块时还需要运行相应的测试脚本。

## 协作与版本

- AI 与协作者先读 [`AGENTS.md`](AGENTS.md)。
- 开发、分支、构建与归档规则见 [`docs/DEVELOPMENT_WORKFLOW.md`](docs/DEVELOPMENT_WORKFLOW.md)。
- 提交前后的统一基准见 [`docs/SUBMISSION_BASELINE.md`](docs/SUBMISSION_BASELINE.md)。
- 检查精确源码版本：`git status`、`git branch --show-current`、`git rev-parse HEAD`。
- `main` 是已确认的默认基线；功能分支可能包含尚未合并的开发进展。
- 当前没有正式 Release 或 SemVer tag。

## 许可证

本仓库公开源码，但不是 OSI 定义的开源软件。原创代码采用
[PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)：允许个人和其他非商业目的使用、修改与再分发，禁止商业使用。第三方组件、服务、商标和素材仍按各自适用的许可执行，完整条款见 [`LICENSE`](LICENSE)。
