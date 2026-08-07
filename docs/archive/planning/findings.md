# Findings & Decisions — Lyric Island Phase 3.1 Direction D Convergence

## Technical & Design Decisions for Direction D
| Decision | Rationale |
|----------|-----------|
| 不整套照搬 A/B/C | 取 A 的安静默认播放、取 B 的清晰 Inspector 工作台信息架构、取 C 的轻量行级快捷语境 |
| 不做成用户可切换的三种模式 | 确定为 Lyric Island 唯一的统一产品体验与架构 |
| 歌曲工作台全面语言洗牌 | 严禁展示 LRCLIB ID, Claude/GPT, MeCab IPADIC, Whisper, DP, Level 3, confidence 数字。全部改用用户任务语言："歌词", "翻译", "读音", "时间同步", "历史版本", "导入与导出" |
| 修正默认歌词辅助层 | 严格实施：默认只显示"原文 + 翻译"或"原文 + Ruby"（二选一），不再同时显示 Ruby + 原文 + 翻译 |
| 真实 DOM 视图切换 | `index.html` 中的 19 个真实状态按钮不再仅仅改变说明文本，而是完全渲染出对应的 19 个独立 DOM 结构 |

## Multi-surface Unified Grammar
- **Main Window (Wide 1200x760 & Small 520x720)**: Complete 45/55 split or stacked card, expandable 380px Inspector or Sheet, 47% line highlight.
- **Lyrics Focus (680x760)**: Pure lyrics mode, 32pt large text, floating mini transport.
- **Desktop Lyrics (760)**: Free position glass card, click-through & lock capability, 1-3 lines display.
- **Capsule (Collapsed 240x36 / Hover 280x36 / Expanded 420x52)**: Compact dynamic island, 1 line lyric max.
- **Fullscreen (16:10)**: Ambient backdrop diffusion, 40pt hero current line text.
