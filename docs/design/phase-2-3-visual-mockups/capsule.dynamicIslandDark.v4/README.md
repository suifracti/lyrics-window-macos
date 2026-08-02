# `capsule.dynamicIslandDark.v4`

状态：**视觉候选，等待用户确认**
类型：静态 SVG mockup，不是 SwiftUI、AppKit 或运行截图。
来源：Apple Live Activities / Dynamic Island 的信息分区原则；不包含 Apple 模板资源，也没有复制任何第三方项目代码或素材。

## 三版 CapsulePresentation 定位

这三版不是三套业务系统，而是同一个运行时状态和窗口控制器下的三种 `CapsulePresentation`：

```text
PlaybackState
  └─ live lyrics projection
       └─ one Capsule state machine
            └─ one Capsule WindowController
                 ├─ capsule.controlFocused.v2  (经典 / Legacy)
                 ├─ capsule.immersiveCompact.v3 (封面色沉浸)
                 └─ capsule.dynamicIslandDark.v4 (推荐默认候选)
```

| Presentation ID | 产品定位 | 当前阶段 |
|---|---|---|
| `capsule.dynamicIslandDark.v4` | Lyric Island 主品牌视觉、推荐默认版本 | **唯一继续实现和打磨的版本** |
| `capsule.immersiveCompact.v3` | 封面色驱动的彩色沉浸主题 | 保留在 Experience Library；冻结，不与 v4 并行实现 |
| `capsule.controlFocused.v2` | 经典控制器 / Legacy | 保留现有可运行实现；冻结，不继续美化或重构 |

三版不得各自创建 `PlaybackState`、`LyricsSession`、Timer、WindowController、播放进度计算、当前行计算或窗口持久化逻辑。差异只存在于 shape、layout、material、color、typography、spacing、motion policy 和信息显隐优先级。

当前 v4 只是候选默认；在 v4 完成真实 Spotify、长标题、无封面、多屏和 Reduce Motion 验收前，不正式切换默认 presentation ID，也不提前进入 Phase 2.4 Experience Library。

## 视觉身份

- 顶部锚定的连续近黑岛体。
- collapsed、hover、expanded 是同一个轮廓的连续形变，不是三张卡片。
- 封面色只作为极弱 keyline、进度和小面积光晕。
- 不使用 Control Center 播放卡片、彩色毛玻璃播放器或纯白面板。
- Apple 的 leading / trailing / center / bottom 只作为内部语义分区，不画成独立卡片。

## 尺寸候选

| 状态 | 候选尺寸 | 内容上限 |
|---|---:|---|
| collapsed | 312 × 40 pt | 小封面、单行歌名/短歌词、播放状态 |
| hover | 332 × 44 pt | 封面、歌名/艺人、上一首/播放/下一首 |
| expanded | 600 × 168 pt | 左侧歌曲与控制，右侧一行当前歌词，可选一行弱化翻译 |

尺寸是 macOS mockup 的 envelope，不是 iPhone Dynamic Island 的系统尺寸。

## 内容顺序

### Collapsed

`封面 → 歌曲名或当前歌词片段 → 播放状态`

### Hover

`封面 → 歌曲名/艺人 → 上一首 / 播放 / 下一首`

控件在同一轮廓中淡入，不弹出第二张卡片；不显示巨大 Spacer。

### Expanded

- 左区：封面、歌曲名、艺人、短进度、播放控制。
- 右区：一行当前歌词，可选一行弱化翻译。
- 不显示下一句、多行歌词或底部长文字工具栏。
- 低频入口收进图标或更多菜单。

## 交互和动画标注

- 共享封面、标题和控制锚点。
- 主要向下展开，宽度向左右连续增加。
- 使用 crossfade / matched layout 语义，不使用弹出卡片动画。
- Reduce Motion：快速 opacity 与直接尺寸变化；禁用弹簧、明显位移和 blur morph。
- mockup 只表达视觉与布局，不定义新的播放器 timer、歌词 session 或窗口行为。

## 边界状态

`capsule-environments.svg` 覆盖：有 notch、无 notch、长标题、多艺人、无封面、暂停、无歌词、长当前歌词和 Reduce Motion 前后状态。

`capsule-states.svg` 覆盖：collapsed / hover / expanded 的完整主状态。

`animation-map.svg` 覆盖：共享锚点、连续尺寸和 Reduce Motion 的静态帧说明。

用户确认前不进入 Phase 2.3 SwiftUI 实现；现有 `capsule.immersiveCompact.v3` 保留不变。
