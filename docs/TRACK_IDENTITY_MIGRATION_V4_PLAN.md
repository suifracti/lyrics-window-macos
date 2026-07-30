# TrackIdentity Migration V4 方案（仅方案，未执行）

> 本文只记录后续安全迁移方案。本轮 QueryPlanner / SafeMatcher 修复不会修改正式 SQLite，不合并、不删除 Track 或 LyricsVersion。

## 1. 当前 V3 stableKey 规则

当前 `TrackIdentity.init(track:)` 的优先级为：

1. `spotify-id:<normalizeIdentifier(track.spotifyId)>`
2. `spotify-uri:<normalizeIdentifier(track.spotifyURL)>`
3. `isrc:<normalizeIdentifier(track.isrc)>`
4. `metadata:<title>|<artist>|<album>|<rounded duration>`

最终 stableKey 是：

```text
<primary>|metadata:<metadataFingerprint>
```

目前 `normalizeIdentifier` 只做 trim + lowercase，没有把 `spotify:track:<id>` 解析成裸 Track ID，也没有把 Spotify URL、Spotify URI 和裸 ID canonicalize 成同一值。

## 2. 已核实的重复原因

正式数据库只读检查到水曜日的約束存在两条 TrackRecord：

```text
spotify-id:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171
spotify-id:spotify:track:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171
```

第一条来自 Spotify Web/API 形态的裸 ID，第二条把 Desktop 返回的 `spotify:track:<id>` 当成了 `spotify_id`。二者指向同一 Spotify Track，但 V3 规则把它们当成不同 primary key。

恋風还存在相同 `source=lrclib`、相同 `providerSourceID` 的重复 LyricsVersion；这不是 stableKey 生成差异，而是同一身份上的重复保存/去重边界问题。迁移不能把它误判成两首歌，也不能直接删除其中的 locked 或人工版本。

## 3. V4 目标 canonical identity

新增纯函数 canonicalization（先在测试夹具和读路径验证，迁移时再使用）：

- `spotify:track:<id>` → `<id>`
- `https://open.spotify.com/track/<id>?…` → `<id>`
- Spotify Track ID 统一 lowercase、去空白
- ISRC 统一 uppercase、去分隔空白和连字符用于比较，但保留原始显示字段
- URI 只作为可回溯字段保存，不能同时充当另一个 Track primary key

建议 canonical key：

```text
spotify-id:<canonical Spotify Track ID>|metadata:<fingerprint>
```

metadata fingerprint 仍然保留，避免把 Spotify ID 相同但播放版本/metadata 明显变化的快照静默合成一条；版本差异由 version traits 和 LyricsVersion 处理，而不是靠删除 metadata。

## 4. 候选合并判定

按强度分层，不允许仅凭标题或字符串包含关系合并：

### 自动进入合并候选

1. canonical Spotify Track ID 完全一致；或
2. ISRC 完全一致，并且标题、主艺人、时长均在安全范围；或
3. 无 ID/ISRC 时，标题、主艺人、专辑、时长和版本 traits 全部一致，且没有 Live/remix/cover/instrumental 等冲突。

### 必须人工确认

- 只有标题相同；
- 主艺人不同或只能通过别名猜测；
- Live、Acoustic、Remix、Cover、Karaoke、Instrumental、电影/动画版冲突；
- 时长明显不同；
- 同一 ID 下 metadata fingerprint 明显不同且没有可解释的版本标记。

## 5. 建议 migration v4 结构

迁移前创建带时间戳的数据库副本，并在事务中执行。建议新增：

```sql
CREATE TABLE IF NOT EXISTS track_identity_redirects (
    old_stable_key TEXT PRIMARY KEY NOT NULL,
    canonical_stable_key TEXT NOT NULL,
    reason TEXT NOT NULL,
    migration_id TEXT NOT NULL,
    created_at REAL NOT NULL,
    FOREIGN KEY (canonical_stable_key) REFERENCES tracks(stable_key)
);

CREATE INDEX IF NOT EXISTS idx_track_identity_redirects_canonical
    ON track_identity_redirects(canonical_stable_key);
```

可选的审计表：

```sql
CREATE TABLE IF NOT EXISTS track_identity_merge_audit (
    migration_id TEXT NOT NULL,
    old_stable_key TEXT NOT NULL,
    canonical_stable_key TEXT NOT NULL,
    match_basis TEXT NOT NULL,
    review_required INTEGER NOT NULL,
    created_at REAL NOT NULL
);
```

迁移不应依赖把旧 primary key 直接改写成新值。先建立 redirect，读路径可以兼容旧 key；确认所有引用重定向完成后，才考虑下一次版本中的物理整理。

## 6. 事务内合并顺序

1. 检查 schema version 和 `foreign_keys`；创建备份并记录 `migration_id`。
2. 计算每个 TrackRecord 的 canonical identity，不在内存中覆盖原始字段。
3. 选择 survivor：优先 canonical Spotify ID 记录；其次字段更完整、ISRC 存在、更新时间较新的记录。
4. 写入 `track_identity_redirects` 和 merge audit。
5. 将 aliases 重定向到 survivor；同值冲突时保留官方、用户锁定和高 confidence 记录，不丢弃来源信息。
6. 将 lyrics_versions 的 `track_stable_key` 重定向；同一 source/provider/content hash 的重复版本先标记为 duplicate group，不直接删除。
7. 将 lyric_lines、translation_versions、translation_lines、reading layers 随所属 version 保持不变，只更新外键归属。
8. 重新检查 locked、manuallyEdited、sourceContentHash、lineIndex 集合和当前版本选择。
9. 更新 `tracks` 的完整 metadata，但保留原始 Spotify URI/ID 字段用于审计。
10. 全部校验通过后提交事务；任意一步失败则 rollback，旧数据库和备份都可继续启动。

## 7. 重复 LyricsVersion 规则

- `locked` 或 `isManuallyEdited` 版本不得因为内容相同而删除。
- 相同 `track + source + providerSourceID + content_hash` 的未锁定重复项可以进入待整理列表，但第一版迁移只记录 redirect/audit，不做物理删除。
- 当前用户选择的版本、locked 版本和最新高置信版本的优先级必须在迁移前后保持一致。
- 纯文本与同步版本不能按行数粗暴判为重复；`is_synced`、时间轴、原文内容 hash 都必须参与比较。

## 8. 幂等与回滚

- `PRAGMA user_version` 只有事务成功后才推进到 4。
- `track_identity_redirects.old_stable_key` 使用 primary key，重复运行只验证已有映射是否一致。
- migration 失败不得留下半条 redirect、孤立 alias 或孤立 lyrics version。
- 启动读取遇到 v4 错误时显示明确数据库错误，不在主线程死锁，也不删除数据库自救。
- 正式执行前必须用水曜日、恋風、一个 Live、一个同名歌曲和一个无 ID Track 做夹具回放，并验证查询数量、锁定版本和翻译关联不变。

## 9. 本轮边界

本轮只改查询规划、SafeMatcher 证据和版本 traits。正式 SQLite 未写入，未执行 stableKey canonicalization、Track 合并、重复 LyricsVersion 删除或 foreign key 重写。
