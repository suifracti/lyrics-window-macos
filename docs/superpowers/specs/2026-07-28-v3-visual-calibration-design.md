# Apple Music Immersive V3 最后一轮视觉校准设计

## 目标

在不改变 V3 组件结构、缓存机制、响应式规则或业务接线的前提下，提升沉浸画布的空间层次、同步歌词景深和辅助读音层级，并微调左侧播放器的比例与间距。

## 范围与不变量

- 保留 `AppleMusicImmersiveV3WindowView`、`AppleMusicImmersiveV3BackdropView` 和现有 45/55、紧凑分栏、窄窗口响应式路径。
- 保留 `AppleMusicImmersiveV3BackdropCache` 的 TrackIdentity/artwork 缓存和异步低分辨率处理；播放位置不能参与背景计算。
- 不修改 V2、歌词专注模式、Provider、搜索、设置、自动排轴、播放同步、TrackIdentity、Ruby 生成或罗马音生成。
- 无时间轴歌词继续是自然全文阅读：不产生当前行、远近景深、自动滚动或伪同步效果。

## 视觉设计

### 背景

继续使用缓存后的低分辨率封面、确定性主色、程序化噪点和异步交叉淡入。改进主色采样与 V3 图层组合，使封面纹理、左侧局部柔光、歌词侧稳定暗幕和窗口暗角同时可见。模糊只作用于缓存缩略图，并保持有限半径，避免在播放进度变化时触发昂贵的全尺寸图像处理。

### 同步歌词

- 当前行：`opacity = 1`、无 blur、动态字号不变，完整 Ruby 和罗马音可见。
- 相邻行：透明度约 `0.42`，不使用 blur，保留可读性。
- 距离两行：透明度约 `0.22`，blur 约 `1–1.3pt`。
- 更远行：更低透明度，blur 上限约 `2pt`，并由现有上下渐隐遮罩退出画面。
- 距离两行以上隐藏 Ruby，罗马音隐藏或降至极弱；主歌词仍保留为远景。

### 播放器

保持封面、歌曲信息、进度条和控制区的左边缘对齐；仅调整控制按钮尺寸、控制间距与时间文字的间距。不得引入胶囊、卡片或新的播放状态逻辑。

## 文件边界

- 保留 `SpotifyLyrics/Design/BackdropPalette.swift` 的共享实现不变，避免影响 V2 的 `TrackBackdropView`；V3 只消费其现有的三色结果。
- 修改 `SpotifyLyrics/Views/Components/AppleMusicImmersiveV3BackdropView.swift`：只调整缓存快照的显示图层和异步过渡。
- 修改 `SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift`：只调整 V3 播放器、同步行景深和辅助层显隐。
- 更新 V3 合同与验收记录；不改变其他窗口和业务合同。

## 验收

使用真实 Spotify 歌曲验证：

- `春を告げる / yama`：有时间轴的前段、中段、后段，检查 Ruby、罗马音、当前行定位和连续滚动。
- `水曜日の約束 / Kawasaki.Rio`：无时间轴全文，检查无高亮、无自动滚动、Ruby/罗马音自然阅读。
- `fragrance - Remix / 茉ひる` 与蓝绿色调真实封面：检查背景不是固定模板。

同时检查默认 `1152×720`、最小 `800×600`、播放位置、歌词会话、切歌过渡及 CPU/线程采样。最终使用正常签名 `xcodebuild`、`codesign` 和全量合同回归验证。
