# Lyrics Window for macOS

一个个人使用的原生 macOS SwiftUI 歌词窗口实验，目前主要配合 Spotify Desktop 显示与管理歌词。

项目仍在开发中，不是 Spotify 或 Apple 的官方产品，也不保证所有歌曲都能取得歌词、翻译或准确排轴。

## 当前状态

| 状态 | 内容 |
| --- | --- |
| 已有基础能力 | 读取当前歌曲与基础播放控制；主窗口、悬浮、全屏和胶囊歌词界面；本地 LRC/TXT 导入、粘贴、编辑与 SQLite 保存；本地与在线歌词查询 |
| 仍在打磨 | 主窗口背景与播放器视觉、歌词来源覆盖率与选择策略、日语假名准确率、翻译呈现、长歌词排版和运行稳定性 |
| 实验或不完整 | 网易云/QQ 等非官方来源、自动排轴、Direction D 工作台、AI/系统翻译链路 |
| 尚未完成 | 面向所有歌曲的可靠歌词覆盖、成熟的自动排轴、MV/动态背景、正式发布与安装包 |

更细的实现边界、当前开发分支和未完成项见 [`docs/STATUS.md`](docs/STATUS.md)。这里列出的功能表示仓库中已有相应实现，不等于已经达到发布质量。

## 环境

- macOS 14 或更高版本
- Xcode
- Spotify Desktop
- Spotify Web Catalog OAuth 仅在使用相关可选能力时需要 Client ID；凭据不得提交到仓库

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

## 使用权

本项目不是开源软件。除第三方组件与素材各自适用的许可外，本项目原创代码保留全部权利，详见 [`LICENSE`](LICENSE)。
