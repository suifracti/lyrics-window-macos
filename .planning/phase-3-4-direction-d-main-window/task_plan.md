# Phase 3.4 Direction D Main Window Audit & Repair

## Goal
核实并修复 Direction D Main Window 的最小真实入口，使用真实 PlaybackState/歌词投影，完成 Wide/Small/Lyrics Focus 的工程与真实运行证据；保持 V3 默认、Direction D experimental，不进入 Phase 3.5。

## Scope
- 只处理 Phase 3.4 主窗口 Presentation、Catalog factory/入口、相关合同、截图和报告。
- 不修改 Provider、数据库 schema、Playback、歌词数据模型或自动排轴。
- 不使用 Preview Matrix 或 Phase 3.3 Experimental Host 作为主窗口证据。

## Phases
- [ ] Stage 0: 核对分支、HEAD、工作区、报告和工程引用
- [ ] Stage 1: 迁移旧 Phase 3.4 无效截图并记录原因
- [ ] Stage 2: 审计/最小修复 Direction D Main Window 真实入口和 Catalog factory
- [ ] Stage 3: 增加/验证行为合同，构建、签名和 TEMP DB 隔离
- [ ] Stage 4: 真实 Direction D Main Window 运行、Spotify/布局/状态验收和窗口截图
- [ ] Stage 5: 写两份报告、截图 manifest，提交独立 commit，最终复核

## Constraints
- V3 保持 current/recommended/default；Direction D 仍 experimental。
- 正式数据库不得打开或写入；所有运行使用 TEMP DB。
- 不得把失败截图标为 PASS；真实歌曲证据不足时判定 Conditional/Fail。

## Errors Encountered
| Error | Attempt | Resolution |
|---|---|---|
| pending | — | — |
