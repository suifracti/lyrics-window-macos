# 日语歌曲多别名搜索与歌词恢复 — 设计与合同

> 日期：2026-07-27（Asia/Shanghai）  
> 状态：**设计 + 红色合同，等待确认后再实现**  
> 触发：回归验收中当前曲 `あやふや / みさき` 在 LRCLIB 原文查询无匹配；需要别名扩展与失败恢复，而不是一次接入全部平台。

## 0. 结论先行

1. **别名是一等元数据**，不得拼进 `title` 字符串。  
2. **别名只扩大召回**，不能单独证明 `TrackIdentity`，不能单独触发高置信度自动采用。  
3. **自动采用**仍依赖 Spotify ID/URI、ISRC、艺人、专辑、时长、版本标记的组合证据。  
4. **罗马音**以确定性日语转写为主；AI 生成只作低置信查询词。  
5. **本阶段不实现** Provider 接入或 UI 全功能；先冻结状态模型、查询矩阵、安全匹配规则和合同测试。  
6. 日语覆盖调研（只读最小请求，2026-07-27）：

| 查询 | LRCLIB search | 网易云 search |
|------|---------------|---------------|
| あやふや / みさき | count=0 | count=2，命中原曲 id=2717111195 |
| Ayafuya / Misaki | count=0 | 易偏到无关曲 |
| Lemon / 米津玄師 | count=20，sync=true | 命中原曲 |
| Lemon / Kenshi Yonezu | count=20，sync=true | （同批可检索） |
| Pretender / Official髭男dism | count=20，sync=true | 命中但偏 live 版本 |

含义：热门日语曲在 LRCLIB 上**罗马音/拉丁标题**往往比纯日文查询更有效；长尾曲（如あやふや）即使中文平台能搜到目录，也不等于有可用授权歌词 API。网易云/QQ/酷狗对日语目录有覆盖，但歌词接口属非官方实验路径，只能插件化，不能进核心默认。

## 1. 边界

### 本轮交付
- 设计文档（本文）
- 红色合同：`Tests/japanese_alias_contract.swift` + `Tests/japanese_alias_contract.sh`
- 不修改生产 Swift 行为（合同允许仅新增待实现源文件占位检查）

### 本轮不做
- 不接入网易云/QQ/酷狗/Musixmatch 实现
- 不接 Spotify Web OAuth
- 不实现完整网页爬取恢复 UI
- 不把 AI 罗马音写入高置信自动采用路径

### 与现有架构关系
- 延续 `TrackSearchManager`（元数据）与 `LyricsSearchManager`（已确认 identity）拆分。
- 别名与查询扩展挂在 **Lyrics 查询规划层**（以及可选 Track 元数据 enrich），不把 LRCLIB 重新塞回自由文本曲库搜索。
- `TrackIdentity.stableKey` **不因别名变化**；别名是 identity 上的附属证据与查询材料。

## 2. 状态模型

### 2.1 `TrackAliasKind`
```text
original
kana
romaji
officialEnglish
localizedTitle
alternativeTitle
providerAlias
userAlias
```

### 2.2 `TrackAlias`
| 字段 | 类型 | 说明 |
|------|------|------|
| id | String | 稳定 id |
| field | title \| artist \| album | 作用字段 |
| kind | TrackAliasKind | 别名类型 |
| value | String | 展示/查询原文，不二次污染 |
| language | BCP-47? | 如 `ja`, `en`, `und` |
| script | enum | `kanjiHiraganaKatakana` / `latin` / `mixed` / `unknown` |
| source | enum | `spotifyMetadata` / `user` / `provider(name)` / `deterministicTransliteration` / `machineGenerated` / `importedTable` |
| confidence | 0...1 | 来源可信度，不是匹配分 |
| isOfficial | Bool | 官方/发行方确认 |
| createdAt | Date? | 可选 |

**权重（查询排序与证据加权，不是自动采用门槛）：**
```text
official / user-confirmed
  > provider official alias
  > deterministic transliteration
  > provider fuzzy alias
  > machineGenerated (AI)
```

### 2.3 `TrackMetadata`（逻辑模型；实现时可新建类型或扩展 `Track`）
```text
TrackMetadata
├── identity: TrackIdentity          // 已确认，稳定
├── primaryTitle / primaryArtist / primaryAlbum / duration
├── spotifyId / spotifyURI / isrc / artworkURL
├── versionTags: [VersionTag]        // live, remix, acoustic, instrumental, karaoke, demo...
├── aliases: [TrackAlias]            // 独立数组，禁止塞进 title
└── queryPlanRevision: UInt64
```

`Track` 保持播放兼容；`TrackMetadata` 由 `Track` + 别名表 + 版本解析构成。

### 2.4 `VersionTag`
```text
live | remix | acoustic | instrumental | karaoke | demo | edit | cover | unknown
```
从标题/专辑附加段解析；用于**阻止** live/instrumental 自动覆盖 studio 原版。

### 2.5 `LyricsQueryVariant`
| 字段 | 说明 |
|------|------|
| id | 稳定 |
| rank | 执行顺序（越小越先） |
| titleQuery | 扩展后的标题 |
| artistQuery | 扩展后的艺人（可空表示仅标题宽松） |
| albumQuery? | 可选 |
| durationHint? | 可选 |
| aliasRefs | 使用了哪些 alias id |
| strategy | 见查询矩阵 |
| evidenceCeiling | 该变体单独能达到的最高采用等级（通常 ≤ medium） |

### 2.6 `MatchEvidence` / `AdoptionDecision`
```text
MatchEvidence
├── identityStrong: spotifyId | uri | isrc 命中
├── titleScore, artistScore, albumScore, durationScore
├── versionConflict: Bool
├── aliasKindUsed: TrackAliasKind?
├── aliasSource: TrackAlias.source
└── provider: String

AdoptionTier
├── autoHigh     // 可自动 loaded
├── autoMedium   // 可自动，需日志
├── candidates   // 必须用户选
└── reject
```

规则摘要：
- 仅 alias 文本相似 → 最高 `candidates`
- `machineGenerated` 罗马音/翻译 → 最高 `candidates`（不得 autoHigh）
- versionConflict（live vs studio 等）→ 不得 autoHigh/autoMedium
- identityStrong + 高字段分 + 无 versionConflict → 才允许 autoHigh

### 2.7 `LyricsRecoveryState`（全部别名与 Provider 失败后）
```text
idle
planning
querying(variantID)
providerPartial(diagnostics)
noMatchExhausted
recoveryMenu(options)
webSearchSuggested(queries)      // 只生成查询，不默认抓取正文
awaitingPasteOrImport
aligningTimeline(mode: manual|assisted)
resolved(document)
failed(reason)
cancelled
```

`LyricsLoadState` 保持现有 UI 枚举；恢复流程由 `LyricsSessionController` 或新的 `LyricsRecoveryController` 驱动，最终仍落到 `loaded / candidates / noMatch / failed`。

### 2.8 诊断
每个 Provider / 每个 variant 记录：
```text
provider, variantID, httpStatus?, failureClass, durationMs, aliasKinds, adoptionTierCap
```
禁止记录歌词正文、token、Cookie。

## 3. 查询矩阵

对同一 `TrackIdentity` 生成**有序、去重**变体（同 title+artist 归一化后只保留最高权重来源）：

| Rank | Strategy | 标题 | 艺人 | 目的 |
|------|----------|------|------|------|
| 1 | `primaryOriginal` | original title | original artist | 基线 |
| 2 | `normalizedPrimary` | normalize(title) | normalize(artist) | 全半角/标点/feat |
| 3 | `kanaTitle` | kana alias | original/kana artist | 假名召回 |
| 4 | `romajiTitleArtist` | romaji title | romaji or original artist | 拉丁目录 |
| 5 | `officialEnglish` | officialEnglish title | officialEnglish/original artist | 官方英名 |
| 6 | `knownAliases` | alternative/provider/user aliases | artist aliases | 已知别名对 |
| 7 | `titleOnlyLoose` | best title form | _(empty)_ | 仅标题宽松 |

### 3.1 标准化（`JapaneseTextNormalizer` / `TrackTextNormalizer`）
至少：
- Unicode NFC，可选 NFKC（全角英数→半角）
- 大小写 fold（拉丁）
- 空白压缩（含全角空格）
- 常见标点统一：中点 `・`/`·`、波浪 `〜`/`～`/`~`、长音符 `ー` 保留但可生成无长音变体
- 去掉包裹性引号与装饰括号（保留版本标记解析用的原文副本）
- `feat.` / `ft.` / `featuring` / `with` 分割主艺人与客串
- 版本标记剥离：`live`, `remix`, `acoustic`, `instrumental`, `off vocal`, `TV size`, `anime size` 等 → `VersionTag`，不丢信息

### 3.2 日语转写（`JapaneseRomanizer`）
- **确定性优先**（系统/自研假名→罗马字规则表）
- 可配置：长音 `ō` vs `ou` vs `o`；助词 `は→wa` / `へ→e` / `を→o`；促音 `っ`；拗音
- 已含拉丁字母、数字、符号的片段**原样保留**
- 输出 `TrackAlias(kind: .romaji, source: .deterministicTransliteration, confidence: mid)`
- AI 补全仅 `source: .machineGenerated, confidence: low`

### 3.3 执行策略
```text
for variant in plan:
  if cancelled or identity changed: stop
  for provider in lyricsProviders:   // Local first, then LRCLIB, then future
     result = provider.lookup(query: variant, identity: identity)
     decision = SafeMatcher.decide(result, evidence...)
     if decision == autoHigh/autoMedium: return loaded
     if candidates: accumulate
  next variant
if accumulated candidates: present
else: enter LyricsRecoveryState.noMatchExhausted
```

Local provider 可同时用 alias 扫文件名与 LRC 头；仍只读。

## 4. 安全匹配（合同必须锁死）

1. 查询别名 ≠ 身份证明。  
2. 自动采用必须组合：ID/URI/ISRC（若有）+ 艺人 +（专辑或时长）+ 版本不冲突。  
3. 官方别名权重 > provider 别名 > 机器生成。  
4. AI 罗马音/翻译：可进 rank 靠后的 variant；`evidenceCeiling = candidates`。  
5. 同名、翻唱、live、instrumental：`versionConflict || low artist` → `candidates` 或 `reject`，禁止覆盖当前 loaded 原版。  
6. 快速切歌：`identity + generation` 二次校验；旧 variant 结果丢弃。  
7. Provider 失败隔离：单 variant/单 provider 失败不取消其余。

## 5. 来源调研（日语向，设计阶段）

| 来源 | 原文 | 假名 | 罗马音 | 逐行轴 | 翻译 | 接入姿态 |
|------|------|------|--------|--------|------|----------|
| Local LRC/用户导入 | ✓ | 视文件 | 视文件 | ✓ | 视文件 | **立即，最高优先** |
| LRCLIB | ✓（热门） | 少 | 依赖曲名语言 | synced/plain | 无保证 | **个人桌面 opt-in，先做多 query** |
| Musixmatch | ✓ | 元数据翻译 | 标题翻译字段 | 商业同步 | 官方翻译 API | **授权后** |
| Apple Music | hasLyrics 提示 | — | — | 不提供正文 API | — | 仅目录，不作文 |
| 网易云非官方 | 日语目录较好 | 视资源 | 视资源 | 常见 | 常见 | **实验插件 only** |
| QQ/酷狗非官方 | 有日语覆盖 | 视资源 | 视资源 | 常见 | 常见 | **实验插件 only** |
| 网页搜索恢复 | 外链 | 外链 | 外链 | 少 | 外链 | 只建议查询/粘贴，不默认 scraper |

最小实证（2026-07-27，只读）：
- `あやふや`：LRCLIB 0；网易云可命中目录 → **多别名仍可能不够，需要恢复/导入**
- `Lemon`：日文艺人名与 Kenshi Yonezu 在 LRCLIB 均有 synced
- `Pretender`：LRCLIB 有；网易云首条可能是 live → **版本标记合同必需**

## 6. 失败恢复（Lyrics Recovery）

当 query plan + 全部 Provider 穷尽：
1. 展示恢复菜单（不自动打开浏览器抓取正文）  
2. 提供可复制的网页搜索查询：原文名 / 罗马音 / 官方英文名（含艺人）  
3. 粘贴纯文本或导入 `.lrc`  
4. 无时间轴 → `aligningTimeline(manual|assisted)`；assisted 不做静默覆盖播放  
5. 恢复成功文档绑定**当前** `TrackIdentity`；来源标记 `local` 或未来 `userImport`  
6. 不默认把在线恢复结果写入用户歌词库（除非用户明确保存——实现阶段再定）

## 7. 建议文件布局（确认后实现）

```text
SpotifyLyrics/Lyrics/TrackAlias.swift
SpotifyLyrics/Lyrics/TrackMetadata.swift
SpotifyLyrics/Lyrics/TrackTextNormalizer.swift
SpotifyLyrics/Lyrics/JapaneseRomanizer.swift
SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift
SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift
SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift
Tests/japanese_alias_contract.swift
Tests/japanese_alias_contract.sh
```

分步实现顺序（确认后）：
1. 模型 + Normalizer + 确定性 Romanizer + QueryPlanner（纯函数）  
2. SafeMatcher 合同转绿  
3. LyricsSearchManager 按 plan 多 variant 调 Local/LRCLIB  
4. Recovery 状态与粘贴/导入  
5. 单独实验插件：日语覆盖验证后的网易云等

## 8. 测试案例矩阵（合同）

| ID | 案例 | 期望 |
|----|------|------|
| A1 | aliases 独立存储 | `TrackMetadata.aliases` 存在；`title` 不含拼贴罗马音 |
| A2 | kind 全集 | 8 种 kind 可编码 |
| N1 | NFKC 全角英数 | `ＡＢＣ` → 可与 `ABC` 归一 |
| N2 | 中点/波浪/长音 | 生成稳定 normalize，不抛 |
| N3 | feat. 剥离 | 主艺人保留，feat 不进 identity 误伤 |
| N4 | live/remix 标记 | 解析为 VersionTag，原文可追溯 |
| Q1 | 查询顺序 | rank1...rank7 按矩阵 |
| Q2 | 去重 | 相同 normalize(title,artist) 只保留更高权 |
| Q3 | あやふや fixture | 至少 original + normalized + romaji 变体 |
| M1 | 仅罗马音相似 | 不得 autoHigh |
| M2 | AI 罗马音 | ceiling=candidates |
| M3 | live vs studio | versionConflict → 非自动采用 |
| M4 | spotifyId+时长+艺人 | 允许 autoHigh |
| R1 | 穷尽后 recovery | `noMatchExhausted` 与可复制 search queries |
| R2 | 切歌取消 | 旧 plan 结果不应用 |
| P0 | 生产文件缺失 | 红色合同失败（当前阶段） |

## 9. 待你确认的问题

1. `TrackMetadata` 新建类型 vs 扩展现有 `Track`？**建议新建**，`Track` 保持播放快照精简。  
2. 罗马音默认风格：`Hepburn ou/ō` 选哪？**建议可配置，默认 Hepburn 且长音用 `ou` ASCII**。  
3. Recovery 网页搜索：仅生成查询字符串，还是允许后续可选“打开浏览器”？**建议先只生成**。  
4. 是否接受下一步实现只做 **Local+LRCLIB 多 variant**，中文平台仍插件化？**建议是**。

## 10. 验收（实现阶段）

- 合同测试全绿  
- `あやふや`：plan 含日文与罗马音；LRCLIB 仍无时进入 recovery 而非假成功  
- `Lemon`：罗马音或日文艺人之一可命中并安全采用  
- live 版候选不自动覆盖  
- 快速切歌无旧词  
- 无新平台默认开启


---

## 相关后续

- Web 三站发现审计与设计：`docs/superpowers/specs/2026-07-27-web-lyrics-discovery-jp-sites.md`（AWA / Uta-Net / UtaTime；发现+外链+手动导入，不自动抓正文）

- 一键自动补全：`docs/superpowers/specs/2026-07-27-one-button-lyrics-autocomplete-design.md`
