# Phase 2.3 胶囊与桌面歌词视觉 mockup

状态：**待用户视觉确认**。这些文件是独立设计稿，不是 SwiftUI 实现、运行截图或最终交互。

## 依据

- 执行优先级：`/Users/apple/Downloads/Lyric-Island-Phase-2.2-至-2.3-胶囊与桌面歌词视觉冻结规范-v1.md`
- 视觉探索输入：`/Users/apple/backup/LyricIsland_UI_UX/lyric_island_phase2.2_visual_review.md`

冻结的默认方向：

- 胶囊：封面色驱动的轻沉浸（C），双表面仍独立。
- 桌面歌词：极简无边界（A）。
- 复杂背景：轻材质（B）作为可选 fallback。
- 胶囊最多显示一行当前歌词；桌面歌词负责多行字幕。
- 旧 presentation 只从推荐默认移除，不删除。

## Mockup 清单

1. `capsule-states.svg`
   - collapsed / hover / expanded
   - 尺寸、内容顺序、截断和无封面边界
2. `desktop-lyrics-states.svg`
   - transparent / light material / unlocked hover
   - 当前行层级、读音辅助层和控制显隐
3. `contrast-matrix.svg`
   - 浅色、深色、复杂背景下的可读性对照
   - 暗色阴影、亮色阴影、描边/发光和轻遮罩策略
4. `edge-states.svg`
   - 长标题、多艺人、无封面、长歌词、无歌词和未排轴

## 关键冻结值

| 表面 | 建议尺寸 | 信息上限 |
| --- | --- | --- |
| Capsule collapsed | 高 36–40pt，宽 120–220pt | 封面、歌名/短歌词、播放状态 |
| Capsule hover | 高 48–52pt，宽 260–340pt | 封面、歌名/艺人、上一首/播放/下一首/展开 |
| Capsule expanded | 宽 300–360pt，高 156–196pt | 歌曲信息、紧凑控制、短进度、一行当前歌词、图标入口 |
| Desktop current line | 28–36pt | 当前原文为绝对焦点 |
| Desktop adjacent line | 18–22pt | 只做层级，不做不可读模糊 |

## 视觉验收重点

- 胶囊不能像横向通知条或迷你主窗口。
- 胶囊控制键始终排在歌曲信息之后，不能跑到最左侧。
- expanded 不显示下一句、多行歌词或完整翻译段落。
- 桌面歌词默认不显示大面积灰色面板。
- 透明模式在浅色、深色、复杂背景都必须可读。
- 长标题和长歌词优先保留完整当前原文，不用裁掉当前行来保布局。
- `Reduce Motion` 只保留极短 opacity crossfade，不使用弹簧、明显位移或 blur morph。

## 交付边界

本目录没有 SwiftUI、AppKit、业务状态或数据库代码。用户确认 mockup 后，才可以按冻结稿进入 Phase 2.3 实现。
