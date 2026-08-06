# Track Identity Migration v4：正式数据库只读审计

**审计日期：** 2026-08-01  
**仓库 HEAD：** `09fb57dcb69082f95752c189d74fd36ef38f2671`  
**分支：** `ui-redesign-phase-1`  
**审计范围：** 只读检查源码、迁移方案和正式 SQLite；未执行正式迁移、未提升正式 schema version、未删除正式数据库记录。

## 1. 结论先行

1. 正式数据库当前确实存在 **1 组可以由强 Spotify ID 证据确认的 Track 重复**：
   `水曜日の約束 / Kawasaki.Rio` 的裸 Track ID 与 `spotify:track:` 形式各保存了一条 Track。
2. 推荐的 canonical stable key 是：

   ```text
   spotify-id:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171
   ```

   但本次 dry-run 证明：按旧方案直接把另一条 Track 的 `LyricsVersion.track_stable_key` 改到 canonical，会触发现有 `lyrics_versions_dedup` 唯一索引冲突。因此 **不能直接执行物理 Track 合并**。
3. 推荐正式 v4 先采用 **redirect-first**：保存旧 stableKey → canonical stableKey 的重定向，先让读写路径兼容旧 key；保留两条物理 Track 和全部版本，另行审计重复 LyricsVersion。这样不会因为迁移而删除或覆盖歌词、翻译、时间轴或锁定版本。
4. `恋風 / Lilas` 的两条 Track 不是可自动合并的身份重复：Spotify ID、专辑和时长不同。它们各自存在重复的 LRCLIB 版本，但这是版本去重问题，不是 Track 合并问题。
5. 正式数据库没有 `automaticAlignment` LyricsVersion，也没有 AlignmentProvenance sidecar 文件；本次没有需要移动或重建的 provenance。
6. 正式数据库只读审计与 redirect-first 副本 dry-run 通过；物理 reparent dry-run 被唯一索引安全阻止并完整回滚。**不建议现在执行正式迁移。**

## 2. 保护措施与数据库边界

正式数据库实际路径：

```text
/Users/apple/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3
```

本次使用 SQLite read-only URI 连接读取正式库，并在独立 `/tmp` 副本中执行模拟。正式库审计前后 SHA-256 相同：

```text
34b3aae5c1eb779daa29d3396d8059d8e12bd95a2afefca4e16577a3ca1f66fa
```

正式库没有被提升 schema version、删除记录或写入 v4 表。未提交业务代码。

## 3. 当前源码与 v4 方案复核

### 3.1 当前 stableKey 生成

当前实现文件：

```text
/Users/apple/backup/sptifylyrics/SpotifyLyrics/Lyrics/TrackIdentity.swift
```

当前逻辑仍然把 Spotify ID 做 trim/lowercase，但不把以下形式 canonicalize 成同一个裸 Track ID：

- `5mqkkcsrujqyakvolven0w`
- `spotify:track:5mqkkcsrujqyakvolven0w`
- `https://open.spotify.com/track/5mqkkcsrujqyakvolven0w?...`

因此 stableKey 仍是：

```text
<primary>|metadata:<normalized title>|<normalized artist>|<normalized album>|<rounded duration>
```

现有方案文档 `/Users/apple/backup/sptifylyrics/docs/TRACK_IDENTITY_MIGRATION_V4_PLAN.md` 中提出的裸 ID canonicalization、ISRC 比较规范化和 redirect 表方向正确；但正式实施前必须补充本次发现的唯一索引冲突规则。

### 3.2 当前 v3 schema

正式库 `PRAGMA user_version = 3`，`schema_migrations` 有 v1、v2、v3 三条记录。

| 表 | 当前用途 |
|---|---|
| `tracks` | Track stableKey、Spotify ID/URI、ISRC、标题、艺人、专辑、时长、封面和更新时间 |
| `track_aliases` | TrackAlias，复合主键包含 `track_stable_key`、field、kind、value |
| `lyrics_versions` | 歌词版本、来源、providerSourceID、原文、content hash、锁定状态、`parent_version_id` |
| `lyric_lines` | 原文、kana、romaji、翻译和逐行 start/end 时间 |
| `translation_versions` | 独立翻译版本、sourceKind、targetLanguage、模型、source content hash、锁定状态、`parent_version_id` |
| `translation_lines` | 逐行翻译 |
| `lyric_reading_layers` | 独立读音层；当前为空 |
| `schema_migrations` | v1/v2/v3 migration 记录 |

当前 v1 创建的唯一索引仍存在：

```text
lyrics_versions_dedup(track_stable_key, source, provider_source_id, content_hash)
```

它正是物理重定向水曜日版本时触发冲突的原因。

### 3.3 当前源码中的持久化边界

- `LyricsVersion` 与 `LyricLine` 通过 UUID 和外键关联；本次不改变任何 UUID。
- `TranslationVersion` 与 `TranslationLine` 通过翻译版本 UUID 关联；本次不改变任何 UUID。
- 当前 schema 没有“当前选中版本”独立表；恢复时由 Repository 按锁定、手动选择和最新版本规则计算，因此 v4 必须把这条恢复规则作为兼容性检查，而不是假设有一张状态表可迁移。
- `parent_version_id` 的缺失父记录为零。
- 有两条翻译 parent 跨越不同 LyricsVersion，但父翻译记录本身存在，属于派生关系，不是 orphan；不能在 Track 合并时删除或重写。

## 4. 正式数据库真实统计

| 项目 | 数量/状态 |
|---|---:|
| Track | 64 |
| TrackAlias | 150 |
| LyricsVersion | 82 |
| LyricLine | 3,968 |
| TranslationVersion | 9 |
| TranslationLine | 405 |
| Reading layer | 0 |
| `automaticAlignment` LyricsVersion | 0 |
| AlignmentProvenance sidecar | 0；目录当前不存在 |
| schema version | 3 |

版本保护状态：

| 状态 | LyricsVersion | TranslationVersion |
|---|---:|---:|
| locked | 4 | 4 |
| manuallyEdited | 3 | 3 |
| `manualImport` | 1 | 不适用 |
| `manualCreate` | 0 | 不适用 |
| `manualEdit` source | 3 | 3 条翻译版本为 `manualEdit` |

歌词来源分布：

| source | 数量 |
|---|---:|
| `lrclib` | 38 |
| `netEaseExperimental` | 16 |
| `qqExperimental` | 24 |
| `manualEdit` | 3 |
| `manualImport` | 1 |

翻译来源分布：

| sourceKind / targetLanguage / status | 数量 |
|---|---:|
| `ai` / `zh-Hans` / complete | 4 |
| `manualEdit` / `zh-Hans` / complete | 3 |
| `legacyImported` / `und` / incomplete | 2 |

## 5. 完整性与孤儿记录

在启用 `foreign_keys=ON` 的独立验证连接中：

- `PRAGMA integrity_check`：`ok`
- `PRAGMA foreign_key_check`：空
- orphan TrackAlias：0
- orphan LyricsVersion：0
- orphan LyricLine：0
- orphan TranslationVersion：0
- orphan TranslationLine：0
- orphan Reading layer：0
- 缺失 parent：0
- 跨 Track 的 LyricsVersion parent：0

发现 2 条跨 LyricsVersion 的 TranslationVersion parent 链，但父翻译版本存在：

| 子翻译 | 父翻译 | 语义 |
|---|---|---|
| `C87C9FCE-17E8-43ED-8A1F-4D70EA488123` | `E2C8D141-B636-4145-B61D-941BE56E9971` | 恋風人工翻译派生链 |
| `9264E6AB-4BAA-4E57-A0B7-B38E8A9B3A29` | `F48256FC-CB31-4AFC-A3A7-C86C8DAB029F` | 水曜日 AI 翻译到人工翻译的派生链 |

这两条关系在 Track 合并时应原样保留。

## 6. 重复检测结果

### 6.1 Track 级重复

| 检测维度 | 结果 |
|---|---:|
| 重复原始 `spotify_id` | 0 组 |
| 重复 canonical Spotify ID | 1 组 |
| 重复原始 URI | 1 组 |
| 重复 canonical URI | 1 组 |
| 重复规范化 ISRC | 0 组 |
| 标题、艺人、专辑、时长完全相同 | 1 组 |
| 规范化标题 + 艺人相同 | 2 组：恋風、水曜日の約束 |

### 6.2 G01：水曜日の約束 / Kawasaki.Rio

两条 Track 的字段：

| 字段 | 记录 A | 记录 B |
|---|---|---|
| stableKey | `spotify-id:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171` | `spotify-id:spotify:track:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171` |
| 原始 Spotify ID | `5mqkkcsrujqyakvolven0w` | `spotify:track:5mqkkcsrujqyakvolven0w` |
| URI | 相同：`spotify:track:5mqkkcsrujqyakvolven0w` | 相同 |
| 标题 / 艺人 / 专辑 | 水曜日の約束 / Kawasaki.Rio / 水曜日の約束 | 相同 |
| 时长 | 171.177 | 171.177 |
| ISRC | `JP92N2518615` | 空 |
| 封面 | 相同 | 相同 |
| 歌词版本 | QQ 32 行纯文本 | QQ 32 行纯文本 + 3 条人工派生版本 |

**推荐 canonical：** 记录 A 的裸 ID stableKey。理由：

1. 与 v4 方案规定的 `spotify-id:<canonical ID>|metadata:...` 形式一致；
2. 具有同一个 Spotify URI 和可靠 ISRC；
3. 记录 B 的锁定/人工版本可按 UUID 完整保留并重定向到 A；
4. 记录 B 的非空字段应在真正迁移前进入审计快照，不能因为删除 Track 壳而丢失历史输入。

**Track 身份结论：** `autoMergeTrackIdentity`，强证据为 canonical Spotify ID + 完整 metadata 一致，无版本 trait 冲突。

**版本结论：** 不能自动删除任何 LyricsVersion。记录 A 的 QQ 版本和记录 B 的 QQ 版本在重定向后会落在同一个 `(track, source, providerSourceID, content_hash)` 唯一键下；记录 B 还有翻译和人工锁定派生链。Track 合并与 LyricsVersion 去重必须分开处理。

### 6.3 恋風 / Lilas：必须人工确认，禁止自动合并

当前存在两条独立 Spotify Track：

| Spotify ID | 专辑 | 时长 | 歌词 |
|---|---|---:|---|
| `6qgudk8ty8lan39gtwtxwk` | 恋風 | 182.029 | LRCLIB 2 条 + manualEdit 1 条 |
| `3gw8n3dg28vayguvc3lqxl` | Laugh | 183.560 | LRCLIB 2 条 |

标题和艺人相同不足以合并。两条 Spotify ID、专辑和时长不同，当前没有 ISRC 作为跨证据。判定为 `manualConfirmation`；在没有版本映射或 ISRC 前，实际操作上应保持分离。

### 6.4 版本重复而非 Track 重复

正式库有 **18 组**相同 `source + providerSourceID` 的重复 LyricsVersion，涉及 18 个额外版本行。这些组都保留在同一个物理 Track 下，不能当作 Track 身份重复。

共同特征：同组记录的 `raw_text` 和 `lyric_lines` 语义内容、行数、时间轴相同，但历史保存的 `content_hash` 在 17 组中不同；部分组只有一条记录带有 legacy/翻译关联。说明旧 hash/保存时机存在历史差异，不能仅凭 provider ID 直接删除。

| 歌曲 | source | providerSourceID | 行数 | 版本组 |
|---|---|---|---:|---:|
| 星月夜 / YU-KA | lrclib | `lrclib:11058305` | 43 | 2 |
| 離開我的依賴 / 王艷薇 | lrclib | `lrclib:13057413` | 38 | 2 |
| 青春不打烊 / 王梓钰 | lrclib | `lrclib:13834667` | 36 | 2 |
| fragrance - Remix / 茉ひる | lrclib | `lrclib:17538249` | 45 | 2 |
| 恋風 / Lilas | lrclib | `lrclib:18558378` | 42 | 2 |
| hot coffee / AYANE | lrclib | `lrclib:29779820` | 51 | 2 |
| 恋風 / Lilas（Laugh） | lrclib | `lrclib:32307048` | 42 | 2 |
| First Love / 宇多田光 | lrclib | `lrclib:6642373` | 31 | 2 |
| また君と / JAY'ED | lrclib | `lrclib:9375035` | 33 | 2 |
| Love my tune / coco. | netEaseExperimental | `netease:2004322811` | 38 | 2 |
| Tell me (feat. Lil Chill) / coco. | netEaseExperimental | `netease:2034475160` | 80 | 2 |
| Veil / 茉ひる | netEaseExperimental | `netease:2043989411` | 73 | 2 |
| 遥恋歌 / stb | netEaseExperimental | `netease:2685797767` | 68 | 2 |
| 00 / Kentaro | netEaseExperimental | `netease:2757594254` | 50 | 2 |
| キミがいないと / AYANE | netEaseExperimental | `netease:3318205326` | 74 | 2 |
| You & Me / H-Slang | qqExperimental | `qq:0038syDT3uo5I7` | 101 | 2 |
| Yell (feat. sleep cat & Lil Chill) / coco. | qqExperimental | `qq:003WweWs3rX7lJ` | 74 | 2 |
| 水曜日の約束 / Kawasaki.Rio | qqExperimental | `qq:004YkjHH0g5pRt` | 32 | 2 |

这 18 组在本轮全部标为“保留、待独立版本去重审计”，不删除、不覆盖 locked/manual 关系。

## 7. 重点样本复核

| 样本 | 正式库真实内容 | 当前判断 |
|---|---|---|
| 水曜日の約束 / Kawasaki.Rio | 2 个 Track；裸 ID 记录有 ISRC；共 5 个 LyricsVersion（QQ 纯文本、manualEdit、manualImport、manualEdit） | Track 身份可确认同一首；redirect-first；版本全部保留 |
| 恋風 / Lilas | 2 个不同 Spotify ID、不同专辑和时长；42 行 LRCLIB 版本重复；其中一条 Track 有锁定人工版本 | 禁止自动合并 Track；版本重复另审 |
| 体面 - Live / Kelly Yu | 正式库没有匹配 Track 行 | 本次没有可供数据库合并的证据；Live 保护仍需运行时回归 |
| 春を告げる - From THE FIRST TAKE | 正式库只有 `春を告げる / yama` studio 记录（196.497 秒、ISRC `TCJPK2087568`、1 条 LRCLIB 同步版本），没有 First Take 记录 | 不能把 studio 记录当作 First Take；未来出现候选时必须版本人工确认 |
| fragrance - Remix | 只有一个明确带 Remix trait 的 Track（茉ひる，205.625 秒），该 Track 有 2 条 LRCLIB 重复版本 | Remix Track 保持独立；版本重复另审 |
| Forever / VILLSHANA, Mahiru | 正式库有 `Forever / VILLSHANA / KILL is LOVE / 168.75 秒`，Spotify ID 存在，但 ISRC 为空，artistDisplay 未保存 Mahiru，且没有 LyricsVersion | metadata 不完整和无歌词分开处理；不能凭现有记录推断 featured artist 或合并其他 Forever |
| あやふや / みさき | 1 个 Track，ISRC `JPPO02501718`，无 LyricsVersion | 没有 Track 重复；无歌词不是身份迁移问题 |
| 千本桜 / MOSAIC.TUNE feat.初音ミク | 正式库没有匹配 Track 行 | 无法从正式库执行身份合并判断 |

## 8. 合并分组分类

### 可进入自动 Track 合并候选

- **G01 水曜日の約束：** 只有 canonical Spotify ID 完全相同，且标题、艺人、专辑、时长一致；没有 Live、Remix、Acoustic、Instrumental、Karaoke、Cover 或 First Take 冲突。
- 但当前推荐的执行方式是 **只写 redirect，不做物理 reparent/delete**，因为唯一索引和版本保留规则尚未解决。

### 必须人工确认

- **恋風两条 Track：** 标题和艺人相同，但 Spotify ID、专辑、时长不同。
- 18 组重复 provider 版本：同 provider ID 并不等价于可删除；必须先按原文、时间轴、stored/content hash、翻译关系、parent、locked/manual 和 provenance 逐组确认。
- 任何未来只凭标题、艺人字符串包含关系或宽松 alias 得到的组。

### 禁止自动合并

- 当前恋風两条不同 Spotify ID 记录。
- 未来的 Live ↔ Studio、Remix ↔ 原版、Acoustic ↔ Studio、Instrumental/Karaoke ↔ Vocal、Cover ↔ 原唱、First Take ↔ 正式录音室版、不同演唱者同名歌曲。
- `春を告げる` studio 记录与未来可能出现的 First Take 记录。
- `fragrance - Remix` 与无 Remix trait 的同名记录。

## 9. canonical Track 与版本/翻译重定向设计

推荐的第一阶段 v4 映射：

```text
old:
spotify-id:spotify:track:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171

canonical:
spotify-id:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171
```

重定向时：

1. TrackAlias 读取先解析到 canonical；同值 alias 只在副本验证一致后去重。
2. LyricsVersion UUID 不变，只记录归属映射；本次不删除 62D666A6、BED618B5 或任何人工/锁定版本。
3. LyricLine 不单独搬运，始终随 LyricsVersion UUID 保持。
4. TranslationVersion 和 TranslationLine 不单独重建，UUID 与 parent 关系保持。
5. `parent_version_id` 原值保留；跨 LyricsVersion 的翻译派生链不可因为 Track 重定向被清理。
6. 当前没有独立“当前选中版本”表，恢复状态继续由现有选择规则计算；正式实现必须在迁移前后对同一 Track 做选择结果快照比较。
7. 当前没有 automaticAlignment 子版本和 sidecar，故本次没有 sidecar 操作；未来若有版本 UUID 变更，必须在同一事务外层的文件操作协议中原子复制/回滚 sidecar。

## 10. 正式迁移前必须补充的安全设计

现有方案中的“直接 reparent 全部 LyricsVersion，再删除旧 Track”在本库上不可执行。正式 v4 方案需补充：

1. **redirect-first 读写兼容：** `track_identity_redirects` 先落库，Repository 查找、保存和恢复均解析 canonical key；旧 Track 暂时保留。
2. **unique index 处理策略：** 不得静默删除水曜日的两个 QQ 版本。需要单独提出“版本重复审计/人工确认”或保留旧 Track 存储壳的方案。
3. **metadata audit snapshot：** 若未来物理删除旧 Track，需要保留旧 raw Spotify ID、URI、ISRC、时间戳和来源的迁移审计快照，不能只保留一个 stableKey 字符串。
4. **alias 冲突策略：** 同值的 2 条水曜日 alias 可在副本确认后折叠；非同值 alias 必须全部保留并记录来源。
5. **版本选择回归：** 记录水曜日的 plain、manualImport、manualEdit 和 locked 翻译选择结果，迁移后必须逐一比较。
6. **幂等 marker：** `user_version` 只能在所有校验成功后提升；旧 App 不应打开已提升到 v4 的库，直到正式 App 支持 v4。

## 11. 正式迁移建议

**当前建议：不执行正式迁移。**

建议顺序：

1. 先确认是否接受 redirect-first v4，不做物理 Track 删除。
2. 为 Repository 增加 canonical identity 解析和 redirect 读取测试。
3. 单独做 LyricsVersion duplicate audit，不把 Track 合并和版本删除放进同一个不可逆操作。
4. 对水曜日、恋風、Remix、Live/Studio 夹具做副本回放，确认 locked/manual/translation 选择不变。
5. 只有在用户明确确认版本重复处理规则后，才讨论物理删除旧 Track 壳和提升 schema version。
