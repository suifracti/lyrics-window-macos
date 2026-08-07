# Task Plan: Lyric Island Phase 3.1 — Visual Directions Exploration & Final Direction Convergence

## Goal
在完成方案 A/B/C 三套高保真探索的基础上，执行最终收口，收敛为**方案 D：安静歌词伴侣 + 可展开歌曲工作台 + 轻量语境快捷操作**。完成 `PHASE_3_1_FINAL_DIRECTION.md` 规范说明，更新 `PHASE_3_1_VISUAL_DIRECTIONS.md`，并在 `index.html` 中实现 Direction D 的 19 个真渲染状态。不修改任何 Swift/SwiftUI 代码或 Xcode 工程，完成后暂停。

## Scope & Prohibitions
- **唯一项目路径**：`/Users/apple/backup/sptifylyrics`
- **禁止修改**：SpotifyLyrics 源码、Xcode 工程、SQLite 数据库、Stable ID
- **禁止动作**：开始 Phase 3.2 实现、直接选定某临时方案开始写代码、整套照搬 A/B/C 某单一方面、把 A/B/C 做成用户可切换的产品模式
- **完成后**：暂停，等待用户下一步指示

## Phases

### Phase 3.1.1: 准备测试数据与共享设计系统 — complete
- [x] 生成/准备统一测试专辑封面 `docs/phase-3/phase-3-1-mockups/shared/album_cover.jpg`
- [x] 固定统一测试歌曲：日文歌曲「丸ノ内サディスティック (Marunouchi Sadistic EX-Extended Version)」 - 椎名林檎
- [x] 固定统一窗口尺寸矩阵 (Wide 1200×760, Small 520×720, Lyrics Focus 680×760, Desktop 760, Capsule, Fullscreen 16:10)
- [x] 建立 `docs/phase-3/phase-3-1-mockups/` 目录及子目录 (`shared/`, `direction-a-quiet/`, `direction-b-workbench/`, `direction-c-contextual/`, `final-direction-d/`)

### Phase 3.1.2: 编写三套高保真 Mockup 交互预览系统 — complete
- [x] 实现 HTML/CSS/SVG 高保真 3D/macOS 玻璃材质交互 Mockup 系统 (`docs/phase-3/phase-3-1-mockups/index.html`)
- [x] 覆盖方案 A、B、C 30 全状态

### Phase 3.1.3: 编写 Phase 3.1 审计比较报告 — complete
- [x] 撰写 `docs/phase-3/PHASE_3_1_VISUAL_DIRECTIONS.md`

### Phase 3.1.5: 方向 D 收口 (Final Direction Convergence) — in_progress
- [x] 制定方向 D (Quiet Companion + Restrained Inspector Workbench + Light Context Actions) 规范
- [x] 重新设计歌曲工作台为任务语言 (歌词、翻译、读音、时间同步、历史版本、导入与导出)
- [x] 修正默认歌词层级为硬约束：原文 + 最多一层辅助 (翻译或 Ruby 二选一)
- [x] 撰写全新收口规范 `docs/phase-3/PHASE_3_1_FINAL_DIRECTION.md`
- [x] 更新比较报告 `docs/phase-3/PHASE_3_1_VISUAL_DIRECTIONS.md` 记录 Final Direction D 的收口关系
- [x] 重构更新 `docs/phase-3/phase-3-1-mockups/index.html`，保留 A/B/C 并新增 Direction D，实现 19 个真实 DOM 视图切换
- [x] 验证 0 行 Swift / SwiftUI / Xcode 文件被修改
- [x] 总结汇报并暂停，等待用户下一步指示
