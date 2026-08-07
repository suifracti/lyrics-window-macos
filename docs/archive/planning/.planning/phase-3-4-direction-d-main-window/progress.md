# Phase 3.4 Progress

- 2026-08-05: 创建 scoped plan，等待 Stage 0 核对仓库和真实入口。
- 2026-08-06: 核对 `/Users/apple/backup/sptifylyrics-v4-ui-sandbox`；确认它是无 Git 元数据的后续 Direction D 源码快照。已创建 `backup/pre-sandbox-merge-20260806` 安全分支，准备只合并源码、工程引用及相关合同测试。
- 2026-08-06: 已导入 sandbox 的差异 Swift 源码、新 DirectionD 组件、`project.pbxproj` 工程引用和 DirectionD 合同测试；未导入 DerivedData/构建产物/截图/规划文档。已重新补回 V3 自动读音缓存、ruby fallback、可见工具栏和兼容全屏的可选 settings 注入。
- 2026-08-06: 提交 `778bd789de81bcb611ed01e14d325a5eedfd9520` 已创建。合并构建已重启为单实例；旧的 `DerivedDataLyricsReadability20260806` 与根目录旧 `DerivedData` 已移入 `artifacts`，根目录仅保留 `DerivedDataSandboxMerged20260806`。
- 2026-08-06: 根据历史截图对照定位 V3 假名回归：token 缺失时触发 `RubyLineView` 整句 ruby fallback。已先让 `v3_inline_ruby_gate_contract.sh` 失败，再补回 token gate；该合同和日语读音合同现通过，待整包编译/重启后提交。
