# Track Identity Migration v4：数据库副本 dry-run

**日期：** 2026-08-01  
**正式数据库：** `/Users/apple/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3`  
**结论：** redirect-first dry-run PASS；物理 reparent dry-run BLOCKED 并已回滚；正式数据库未修改。

## 1. 副本与保护

本次从正式数据库复制到以下独立文件：

```text
/tmp/SpotifyLyrics-v4-pristine-20260801.sqlite3
/tmp/SpotifyLyrics-v4-redirect-dry-run-20260801.sqlite3
/tmp/SpotifyLyrics-v4-physical-attempt-20260801.sqlite3
```

正式数据库只读审计前后 SHA-256：

```text
34b3aae5c1eb779daa29d3396d8059d8e12bd95a2afefca4e16577a3ca1f66fa
```

前后相同。正式库 `user_version` 仍为 3，`integrity_check=ok`，`foreign_key_check` 为空。

## 2. 迁移映射

本次唯一进入自动 Track 身份映射的组：

```text
old_stable_key:
spotify-id:spotify:track:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171

canonical_stable_key:
spotify-id:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171
```

证据：canonical Spotify Track ID 相同；标题、完整艺人、专辑、时长和封面一致；没有版本 trait 冲突。记录 A 另有 ISRC `JP92N2518615`。

## 3. redirect-first dry-run：PASS

在 disposable redirect 副本中只创建提议的 `track_identity_redirects` 和 `track_identity_merge_audit`，写入 1 条映射，不改写任何正式表的 Track key，也不删除 Track/歌词/翻译。

| 表 | dry-run 前 | dry-run 后 | 变化 |
|---|---:|---:|---:|
| tracks | 64 | 64 | 0 |
| track_aliases | 150 | 150 | 0 |
| lyrics_versions | 82 | 82 | 0 |
| lyric_lines | 3,968 | 3,968 | 0 |
| translation_versions | 9 | 9 | 0 |
| translation_lines | 405 | 405 | 0 |
| lyric_reading_layers | 0 | 0 | 0 |
| schema_migrations | 3 | 3 | 0 |

检查结果：

- `PRAGMA integrity_check`：`ok`
- `PRAGMA foreign_key_check`：空
- `user_version`：3（特意保持 3，保证当前 App 可打开副本）
- LyricsVersion UUID 集合：不变
- TranslationVersion UUID 集合：不变
- LyricsVersion / TranslationVersion parent 映射：不变
- Sidecar：没有 automaticAlignment 版本，0 个文件，无需处理

这证明 redirect-first 可以在不触碰歌词正文、翻译正文、时间轴和 provenance 的情况下记录身份映射。

## 4. 物理 reparent dry-run：BLOCKED，事务已回滚

在另一份 disposable copy 中按旧方案尝试：

1. 创建 redirect/audit 记录；
2. 将旧 TrackAlias 合并到 canonical；
3. 将旧 Track 的 LyricsVersion 全部更新到 canonical；
4. 再删除旧 Track。

第 3 步触发 SQLite 错误：

```text
UNIQUE constraint failed:
lyrics_versions.track_stable_key,
lyrics_versions.source,
lyrics_versions.provider_source_id,
lyrics_versions.content_hash
```

原因是水曜日的两个 QQ 版本：

- `qqExperimental / qq:004YkjHH0g5pRt`
- 两者均为 32 行纯文本
- 两者 stored `content_hash` 相同
- 旧 Track 的版本还没有与 canonical Track 的版本合并空间
- 当前 v3 唯一索引不允许简单把两个 Track key 改成同一个 key

回滚结果：

| 表 | physical copy 事务前 | rollback 后 |
|---|---:|---:|
| tracks | 64 | 64 |
| track_aliases | 150 | 150 |
| lyrics_versions | 82 | 82 |
| lyric_lines | 3,968 | 3,968 |
| translation_versions | 9 | 9 |
| translation_lines | 405 | 405 |

回滚后副本检查仍为：

- `integrity_check=ok`
- `foreign_key_check` 为空
- `user_version=3`

这个失败不是数据库损坏，而是一个应当在正式迁移前处理的安全阻断条件。它证明当前不应把“Track 合并”和“LyricsVersion 去重”放在同一个隐式删除步骤中。

## 5. App 使用副本重启恢复

使用当前目标 Debug App 的绝对路径启动，且只注入副本数据库环境变量：

```text
/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app
```

运行进程实际来源：

```text
/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics
```

副本启动日志确认：

```text
PERSISTENCE startup ready
SESSION persistence hit ... source=lrclib ... lines=36 sync=true
```

本次副本 smoke 使用当时 Spotify 当前的 `青春不打烊 / 王梓钰`，验证了副本数据库可以被 App 启动并从 SQLite 恢复 36 行同步歌词。App 对副本的重复保存没有改变副本的表数量；退出后副本仍为 `integrity_check=ok`、`foreign_key_check` 为空。

正式库在验证后已回到审计前的相同 SHA-256；为了防止审计结束后再产生正式库写入，App 当前没有保持运行。

## 6. 预计的逻辑影响（不是已提交迁移结果）

如果未来只做水曜日的物理 Track reparent，并且解决唯一索引冲突，理论上的行数变化可能是：

- Track：64 → 63；
- exact duplicate TrackAlias：150 → 148；
- LyricsVersion、LyricLine、TranslationVersion、TranslationLine：原则上不减少；
- 所有 version UUID：不变；
- 所有 parent：不变；
- locked/manual/AI 翻译：全部保留。

上述数字只是“在版本冲突另行解决之后”的影响估算，不是本次 dry-run 的成功结果。当前推荐的 redirect-first 结果是各表数量保持不变。

## 7. provenance sidecar

正式路径：

```text
/Users/apple/Library/Application Support/SpotifyLyrics/AlignmentProvenance/
```

审计时目录不存在，正式数据库中 `automaticAlignment` LyricsVersion 数量为 0。因此：

- 本次没有 sidecar 需要复制、移动或删除；
- 没有旧 LyricsVersion ID → 新 ID 映射；
- 未来若物理迁移改变 LyricsVersion ID，必须先校验 sidecar 内部 `lyricsVersionID` / `parentVersionID`，再做原子文件操作；
- sidecar 缺失时不得猜测或生成 provenance。

## 8. 回滚方案（正式迁移前）

正式执行时建议：

1. 在同一 Application Support 下创建带 migration ID 的数据库备份，例如：

   ```text
   ~/Library/Application Support/SpotifyLyrics/Backups/SpotifyLyrics.sqlite3.v4-<migrationID>.bak
   ```

2. 若存在 provenance，完整复制到：

   ```text
   ~/Library/Application Support/SpotifyLyrics/Backups/AlignmentProvenance/<migrationID>/
   ```

3. 先写 redirect/audit，所有外键/版本选择检查通过后才允许提交事务。
4. `PRAGMA user_version` 只在事务成功后提升；中途崩溃时旧 schema 仍可启动。
5. 重复运行时，已存在的 redirect 必须验证目标完全一致；不一致就停止，不覆盖。
6. 数据库提交失败时回滚事务；sidecar 操作失败时删除本次临时副本并从备份恢复。
7. App 启动失败时先退出 App，再把备份数据库原子恢复到 `SpotifyLyrics.sqlite3`，同时恢复 sidecar 目录，最后启动 App 验证 `integrity_check` 和版本选择。

本次没有执行正式备份/正式 marker，因为本次明确禁止正式迁移。

## 9. 最终判断

- redirect-first dry-run：**PASS**
- physical Track reparent dry-run：**BLOCKED，已回滚**
- 正式数据库是否被修改：**否，SHA-256 前后一致**
- 是否建议现在执行正式迁移：**否**
- 正式迁移前仍需用户确认：
  1. 是否接受 redirect-first 而不是直接删除旧 Track；
  2. 18 组重复 Provider 版本是否只保留并标记，还是另做独立版本去重；
  3. 水曜日两条 QQ 版本及其翻译/人工派生链的选择优先级；
  4. 是否在后续 App 版本中新增 v4 schema 和 Repository redirect 解析；
  5. metadata 审计快照和历史 raw ID 是否需要长期保留。

