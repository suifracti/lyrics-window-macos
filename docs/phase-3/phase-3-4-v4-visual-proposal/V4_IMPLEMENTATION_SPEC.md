# Lyric Island V3 & V4 Visual Implementation Specification (for Codex)

> **文档性质**：本文档为工程团队 (Codex) 交付 V3 基础微调与 V4 主窗口 UI 视觉实现的精准规格说明书。

---

## 一、V3 (Apple Music 沉浸主窗口) 零大改·原位微调规格

**原则**：绝对不改动 V3 现有结构、布局比例或界面组件。仅在原基础上手术式加入 2 项微调：

### 1. 智能防透字暗幕 (Backdrop Contrast Shield)
- **目标**：解决遇白底/高亮封面时白字歌词局部对比度变弱问题。
- **改动代码点**：`SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3BackdropView.swift`
- **实现**：在柔光背景之上加一层 `LinearGradient(colors: [Color.black.opacity(0.10), Color.black.opacity(0.35)], startPoint: .leading, endPoint: .trailing)`。
- **效果**：文字 WCAG 对比度 `>= 4.5:1`，视觉几乎无察觉，但歌词大幅清晰。

### 2. 顶栏控制按钮胶囊化对齐 (Quiet Tool Capsule)
- **目标**：收纳右上角散落的搜索/设置/布局切换按钮。
- **改动代码点**：`SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`
- **实现**：右上角 `HStack` 增加 `background(Color.black.opacity(0.30))` + `.cornerRadius(12)` + `.blur(radius: 12)` 胶囊背景，按钮与布局保持不变。

---

## 二、V4 (Direction D) 响应式断点与窗口尺寸 (Responsive Breakpoints)

| 布局模式 | 宽度边界 | 建议基线尺寸 | 适用场景 | 工作台展开形态 |
|---|---|---|---|---|
| **Wide 宽窗口** | `width >= 900px` | 1200 × 760 px | 桌面大屏沉浸伴侣 | 右侧滑动滑出 360px Inspector |
| **Small 紧凑窗口** | `width <= 580px` | 520 × 720 px | 屏幕边缘小窗伴侣 | 从底部向上弹出 82% 高度 Bottom Sheet |
| **Lyrics Focus 专注** | `580px < width < 900px` 或用户强指 | 680 × 760 px | 纯歌词大字号阅读 | 右侧滑动 360px Inspector |

---

## 三、V4 区域尺寸与几何结构 (Geometry & Layout Metrics)

### 1. 主方案 (Variant A - Master Vision)
- **左侧播放器区域**：宽度 `280px`；内边距 `24px 28px`；封面尺寸 `180 × 180 px`（圆角 `12px`，底衬 Ambient Glow `20px` 模糊光晕）。
- **右侧歌词画布**：弹性 `flex: 1` 占据剩余宽度；内边距 `0 40px`；歌词列最大宽度 `680px`。
- **歌曲工作台 Inspector**：固定宽度 `360px`；内边距 `16px`；背盘毛玻璃 `backdrop-filter: blur(24px) saturate(180%)`。
- **Small Bottom Sheet**：最大高度 `82%`；顶部圆角 `16px 16px 0 0`；顶部拖拽条 `36 × 4 px`。

### 2. 克制变体 (Variant B - Restrained Variation)
- **左侧播放器区域**：宽度 `250px`；封面尺寸 `150 × 150 px`。
- **歌曲工作台 Inspector**：固定宽度 `340px`。

---

## 四、字体阶梯与歌词层级 (Typography & Lyrics Hierarchy)

- **当前行 (Hero Line)**：
  - 字号 `26pt`（Focus 模式 `32pt`），Bold 字重，100% 不透明度（`#ffffff`）。
  - 辅助层（翻译）字号 `14pt` Regular，75% 不透明度；Ruby 假名注音 `11pt` Medium Cyan（`#38bdf8`）。
- **相邻行 (±1 Line)**：
  - 原文字号 `18pt` Semibold，45% 不透明度。
- **远端行 (±2+ Lines)**：
  - 原文字号 `16pt` Medium，25% 不透明度；**隐藏所有辅助层**。

---

## 五、Codex 实现必须遵守的业务边界 (Business Boundaries)

1. **绝对保留 V3 结构**：V3 不允许大改，仅做暗幕遮罩 + 胶囊对齐；V3 保持为默认主窗口 Stable ID。
2. **V4 Experimental 隔离**：V4 仅作为 `.experimental` 登记在 `PresentationCatalog.swift` 中供选择。
3. **零业务代码修改**：View 内部严禁直接发 HTTP 请求、操作数据库或调用 Provider。
