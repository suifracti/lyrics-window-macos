# Lyric Island 第二阶段：冻结范围与执行路线 v2

> 本文件是第二阶段的执行冻结基线。它约束范围、回退和验证方式；不得用视觉参考稿替代本文件的边界。

## 1. 产品结构冻结

第二阶段采用“统一浮动系统、两个独立表面”（方案 C）：

- 胶囊是歌曲状态与播放控制表面；
- 桌面歌词是多行字幕表面；
- 胶囊可以开关桌面歌词；
- `CapsuleLyricsWindowController` 与 `FloatingLyricsWindowController` 必须继续独立；
- 两个表面不共享 frame、screen、visibility、lock、pass-through 或 hover 状态；
- 只共享 PlaybackState、live lyrics projection、WindowManager 协调命令、Design Tokens 和纯展示组件。

全产品使用 presentation version 作为另类归档边界。旧版本不直接删除；新版本通过稳定 ID 并存，可回退。Preview Lab 只允许读取同一 live projection 或 Mock snapshot，不写正式数据库、不改变播放进度、不创建第二套 Session/Timer。

## 2. 执行范围

### Phase 2.1：正确性与低风险交互

- V3、歌词专注、悬浮歌词、胶囊、全屏只读取 live projection；
- 非日语歌词不显示 kana/romaji；未知语言 fail-closed；
- 歌词版本和翻译版本支持 session 级“无选择”；
- Spotify 授权复用现有 PKCE、state、loopback、Keychain，并通过系统浏览器；
- 艺人/专辑只使用真实 Spotify identity 外链。

### Phase 2.2：浮动系统与小窗口

1. 浮动系统协调层：统一入口，保持两个独立 Controller。
2. 胶囊职责收缩：收起/hover/expanded，expanded 最多一行当前歌词，不显示下一行或多行上下文。
3. 桌面歌词 presentation：保留 `floatingLyrics.legacyPanel.v1`，增加 `floatingLyrics.transparent.v2`，支持 Ultra Transparent 与 Light Material。
4. 小窗口歌词专注：尺寸触发是临时投影，不覆盖用户布局选择；手工专注与自动专注分离。
5. 胶囊 Debug 比较锚点：仅 Debug，Release 固定 Top Center，不进入正式设置。
6. Phase 2.2 验收报告、截图索引、数据库和敏感信息检查。

每个子阶段独立提交，失败时保留上一个干净提交，不把半成品带入下一阶段。

### Phase 2.3：只读审计与规划

Phase 2.2 后只审计和规划，不实施主窗口重构：

- Design Tokens、重复定义和硬编码；
- V3 背景、封面取色、缓存、歌词布局、进度视觉、响应式布局、状态页；
- 长短歌词的裁剪、换行、frame、transition、scroll anchoring；
- presentation version 接口；
- Preview Lab 只读架构；
- 2.3A–2.3G 可执行子阶段计划。

## 3. 共同边界

本批次不得：

- 修改正式 SQLite 或创建 migration；
- 修改 Track Identity v4；
- 新增 Provider、修改 QueryPlanner/SafeMatcher；
- 修改自动排轴或创建第二套 PlaybackState/LyricsSession/Timer；
- 进入 Phase 2.4、AI 模型列表、历史、翻译曲库、多角色或动态桌面；
- 删除 legacy UI 版本；
- 将 Gemini 提案逐像素照搬；
- 把私人桌面截图提交到 Git；
- 为测试硬编码特定歌曲。

正式 App 验收必须使用目标 Debug App；数据库运行验收使用临时副本，并以前后 SHA-256 证明正式库未被写入。

## 4. 浮动表面交互冻结

- 可编辑/可拖动、锁定展示、鼠标穿透三态继续独立管理；
- 穿透必须有不依赖窗口本身的恢复入口；
- 全屏前后分别保存两个表面的可见状态；
- 关闭一个表面不得自动关闭另一个；
- 普通播放 tick、展开/收起、拖动位置和点击歌词不得隐式 seek；
- 播放、歌词、翻译、读音和切歌全部来自共享 live session。

## 5. 停止条件

遇到数据破坏、正式库写入风险、架构身份不明、构建无法恢复或需求冲突时停止该子阶段，记录：阻塞位置、已验证事实、尝试方法、未继续猜测的原因和建议下一步。不得提交不可构建的代码。
