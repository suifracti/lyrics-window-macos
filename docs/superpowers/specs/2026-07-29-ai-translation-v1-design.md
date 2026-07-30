# AI 整首歌词翻译 V1 设计

## 范围

本阶段只覆盖 OpenAI-compatible 整首歌词翻译、SQLite schema v2、设置接入和现有歌词展示。翻译服务只产生 `translationText`，不修改原文、假名、罗马音或任何时间轴。

## 数据流

```text
LyricsSessionController
  -> TranslationSessionController（PlaybackState 只创建一个实例）
  -> TranslationRepository（SQLite actor）
  -> AITranslationService
     -> OpenAICompatibleClient
     -> AITranslationResponseParser
  -> TranslationVersion + TranslationLine
  -> LyricsDocument 的展示投影
```

View 不发 HTTP、不执行 SQL，也不创建翻译 controller。V3、歌词专注模式及仍保留的歌词窗口通过同一个 `PlaybackState` 观察同一个 controller。

## SQLite v2

新增 `translation_versions` 与 `translation_lines`。翻译版本保存 `sourceKind`、`sourceContentHash`、目标语言、模型、服务 Host、prompt hash、完整状态和锁定/人工编辑标志。普通索引只服务查询，不建立阻止再次翻译的唯一约束。

v1 迁移逐首检查 `lyric_lines.translation_text`。只要存在非空内容，就创建 `legacyImported` 版本，目标语言使用 `und`，按原 line index 导入；旧列保留为只读兼容字段。若历史翻译不完整，版本标记为 `incomplete`，不参与“最新完整版本”自动选择，但不丢失数据。迁移在单事务内执行，并在升级前生成数据库备份。

翻译的源指纹只由歌词行的 index、原文、kana、romaji、起止时间等源字段计算，不包含旧翻译文本。加载必须同时匹配 LyricsVersion ID、指纹、行数和 index 集合。

## API 合同

Base URL 规范化规则：去除末尾 `/`；裸 Host 追加 `/v1/chat/completions`；已含 `/v1` 只追加 `/chat/completions`；已含完整 endpoint 原样使用；自定义反代路径不重复追加 `/v1`。测试连接发送最小探针，不发送当前歌词。

真实歌词请求一次发送整首 JSON 行数组，响应必须是严格的 `{index, translation}` 数组。解析器检查完整 index 集合、重复/缺失/越界、空白行保留和不得夹带时间轴或解释。验证失败、取消、超时、401、429 和网络错误只留在运行时，不写半成品数据库行。

## 版本选择和任务并发

选择顺序为：匹配目标语言和源指纹的 locked 版本；用户当前手动选择版本；最新完整版本。显式“重新翻译”永远新建版本；自动翻译可复用完整版本。相同上下文的并发任务由 `TranslationSessionController` 合并，切歌取消并用 generation/identity 双重校验，旧结果不能写入新歌曲。

API Key 使用独立 Keychain service 保存；UserDefaults 只保存 Base URL、Model、目标语言、风格、提示词、温度、超时和自动翻译开关。日志仅记录请求 ID、模型、Host、行数、HTTP 状态、错误分类和耗时，禁止记录 Key、Authorization、完整歌词、请求/响应正文。
