# Lyric Island Phase 2.2 验收报告

日期：2026-08-02
工作目录：`/Users/apple/backup/sptifylyrics`
分支：`codex/phase-2-2-overnight`
起始基线：`0b6ccf3e24404375865d900fcaf72b86a07deb67`
本报告提交前 HEAD：`f299cf41ebc8f532dca8f5e6c6edac309c7d648f`

## 1. 范围

本批次完成 Phase 2.2 的五个实现阶段：

1. 统一浮动系统协调入口；
2. 胶囊 control-focused presentation v2；
3. 桌面歌词 transparent / Light Material presentation；
4. V3 小窗口自动歌词专注；
5. Debug 胶囊 Top Left / Top Center / Top Right 比较锚点。

产品结构仍为方案 C：一个浮动系统、两个独立表面。`CapsuleLyricsWindowController` 与 `FloatingLyricsWindowController` 没有合并，frame、screen、可见性、锁定、穿透和 hover 状态均独立。

本批次明确未做：Phase 2.3 主窗口视觉重构、Phase 2.4 设置工作台、Provider、SafeMatcher、AI、自动排轴、Track Identity migration v4、全屏/悬浮歌词业务重写，以及任何正式数据库迁移。

## 2. 状态图

```mermaid
flowchart LR
    P[PlaybackState live projection] --> W[WindowManager façade]
    W --> C[CapsuleLyricsWindowController]
    W --> F[FloatingLyricsWindowController]
    W --> G[FullScreenLyricsWindowController]
    C --> CV[Capsule: state and controls]
    F --> FV[Floating lyrics: multi-line surface]
    C -. independent frame/screen/visibility .- F
    G --> S[Fullscreen temporary hide/restore snapshot]
```

胶囊可以独立显示/隐藏桌面歌词；关闭其中一个不会关闭另一个。全屏只临时隐藏进入前实际可见的辅助窗口，退出时分别恢复。

## 3. 按提交顺序

所有提交均可单独回退；推荐回退命令为 `git revert <commit>`，不要 reset 已共享历史。

| 顺序 | Commit | 目的 | 主要范围 | 独立回退 |
|---|---|---|---|---|
| 1 | `12efbdc` | 冻结 Phase 2 执行范围 v2 | 纯文档 | `git revert 12efbdc` |
| 2 | `07da632` | 浮动系统协调 façade | `WindowManager`、两个 Controller 入口 | `git revert 07da632` |
| 3 | `7793cbc` | 协调层合同测试 | 浮动开关/独立恢复合同 | `git revert 7793cbc` |
| 4 | `333f753` | 胶囊 control-focused v2 | presentation ID、胶囊展示与 SF Symbols 控件 | `git revert 333f753` |
| 5 | `3f28589` | 限制 expanded 长歌词行 | 固定行高与截断合同 | `git revert 3f28589` |
| 6 | `38452ae` | 桌面歌词透明/材质 v2 | presentation/style、设置接线、材质表面 | `git revert 38452ae` |
| 7 | `ec4419a` | 控件仅在 hover 显示 | 浮动歌词 hover 控件生命周期 | `git revert ec4419a` |
| 8 | `f6a6d65` | V3 自动小窗口歌词专注 | 单一设置、集中阈值、临时 V3 projection | `git revert f6a6d65` |
| 9 | `aac1c29` | 固化 compact focus 合同 | 默认关闭、V3-only、手工模式区分 | `git revert aac1c29` |
| 10 | `3797bbc` | Debug 胶囊锚点 | Debug 菜单与三种顶部锚点 | `git revert 3797bbc` |
| 11 | `c87ac32` | 隔离 Release 调试代码 | Release center-only、safe area 与 clamp | `git revert c87ac32` |
| 12 | `f299cf4` | 更新旧合同 harness | 最小尺寸断言、编译切片兼容 | `git revert f299cf4` |

对应各提交的实际 shortstat 已由 Git 保留；本批次相对基线总计：22 个已跟踪文件，`1151 insertions(+), 66 deletions(-)`。

## 4. 测试与构建

- 全部 `Tests/*.sh`：**51/51 PASS**。脚本按各自 shebang 使用 `bash`、`zsh` 或 `sh` 执行；没有只按 executable bit 筛选。
- Phase 2.2 专项合同：**5/5 PASS**。
- `git diff --check`：PASS。
- Debug 构建：`** BUILD SUCCEEDED **`。
- 目标 App：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`。
- `codesign --verify --deep --strict`：PASS。
- 签名：`Sign to Run Locally`；bundle identifier `com.spotifylyrics.app`；arm64。

## 5. 真实运行与数据库安全

使用临时数据库副本启动，未让测试 App 写正式库：

- 临时库：`/tmp/spotifylyrics-phase2-2-runtime.T47AHw/SpotifyLyrics.sqlite3`
- 启动进程 PID：`7886`（已停止）
- 实际进程路径：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`
- 临时库启动后 `user_version=4`、`integrity_check=ok`、`foreign_key_check` 为空。

正式数据库：`/Users/apple/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3`

| 项目 | 迁移前/本批次前 | 本批次后 |
|---|---:|---:|
| SHA-256 | `47e32afab6b7e2a648dc7323acac447250e8be6703720089165905d4d37076c9` | `47e32afab6b7e2a648dc7323acac447250e8be6703720089165905d4d37076c9` |
| user_version | 4 | 4 |
| tracks | 73 | 73 |
| track_aliases | 168 | 168 |
| lyrics_versions | 94 | 94 |
| lyric_lines | 4396 | 4396 |
| translation_versions | 9 | 9 |
| translation_lines | 405 | 405 |
| track_identity_redirects | 1 | 1 |
| track_identity_merge_audit | 1 | 1 |

`integrity_check=ok`；`foreign_key_check` 为空。没有 migration、删除、reparent、版本写入或 sidecar 操作。

## 6. 截图索引

以下截图使用目标 App 的独立窗口捕获，未加入 Git，避免提交私人桌面内容：

- `/Users/apple/backup/sptifylyrics/docs/design/phase-2-2-validation/capsule-top-left-collapsed.png`：已生成，Debug Top Left / collapsed。
- `/Users/apple/backup/sptifylyrics/docs/design/phase-2-2-validation/capsule-top-center-hover.png`：已生成，Debug Top Center / hover smoke check。
- `/Users/apple/backup/sptifylyrics/docs/design/phase-2-2-validation/capsule-top-right-expanded.png`：已生成，Debug Top Right / expanded smoke check。

这些截图验证窗口位置和三态入口，不代表真实 Spotify 歌曲、歌词正文或翻译内容验收；本次临时运行未连接 Spotify Desktop，因此歌曲内容相关 UI 仍需用户本地真实验收。

## 7. 验收矩阵

| 场景 | 结果 | 证据/限制 |
|---|---|---|
| 胶囊 collapsed / hover / expanded | PASS（窗口 smoke check） | 三态合同与目标 App 窗口捕获；真实歌曲内容未接入 |
| 胶囊独立开关桌面歌词 | PASS（合同） | `WindowManager` façade；未改变两个 panel 的 frame/visibility 绑定 |
| legacy / transparent / Light Material | PASS（合同/构建） | 样式 presentation ID 与 settings publisher 接线；材质细节需本地视觉验收 |
| 解锁 hover 控件 / 锁定 / 穿透恢复 | PASS（合同） | 真实鼠标穿透长流程未在本环境完成 |
| V3 宽 / 小 / 恢复 | PASS（合同/构建） | 自动专注默认关闭，阈值集中；真实拖拽缩放未完成 |
| 全屏前后辅助窗口恢复 | PASS（既有合同） | 物理窗口组合未完成 |
| 多显示器、拔屏、Space | UNVERIFIED | 当前环境未执行物理外接屏/拔屏测试 |
| Reduce Motion 降级 | UNVERIFIED | 未在系统设置中切换验证 |
| 正式数据库不变 | PASS | SHA-256、schema、完整性均一致 |
| 敏感信息扫描 | PASS | diff 未发现 API key、token、Authorization header 或私密二进制 |

## 8. 已知问题与醒后需确认

1. 当前合同和临时 App 运行证明了结构接线，但没有替代真实 Spotify 歌曲下的视觉验收。
2. `CapsuleLyricsWindowPersistence` 使用屏幕 `visibleFrame` 与 `safeAreaInsets.top`；多显示器实际屏幕排列、拔屏和全屏 Space 仍需人工确认。
3. V3 自动歌词专注是临时显示 projection，默认关闭，不改变用户选择的 layout family；用户需要确认阈值和进入/退出时的视觉取舍。
4. 胶囊与桌面歌词的产品关系已按方案 C 落地：胶囊控制、桌面歌词多行显示；用户仍可决定透明模式与 Light Material 的最终默认视觉。
5. 本批次没有开始 Phase 2.3，也没有开始 Phase 2.4。

## 9. 停止点

Phase 2.2 代码、合同、构建和数据库只读验收已完成。下一步仅允许进入 Phase 2.3 的只读审计与计划；本报告完成后不进入 Phase 2.3 代码实现，也不进入 Phase 2.4。
