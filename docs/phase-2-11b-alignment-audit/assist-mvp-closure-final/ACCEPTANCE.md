# Phase 2.11B-Assist MVP — 真实验收完成

| 项 | 值 |
|---|---|
| 产品 | **Lyric Island** |
| 日期 | 2026-08-04 |
| 分支 | `codex/phase-2-11b-assist-mvp` |
| **状态** | **Phase 2.11B-Assist MVP ✅ 完成并真实验收** |
| App | `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app` |
| 签名 | Apple Development · Team `5RGL84U3V2` · **非 adhoc** · 无 debug dylib |
| CDHash（验收构建） | 见 `identity-freeze.txt`（Development 签名链） |

---

## 验收前修复（真实失败驱动）

| 问题 | 修复 | Commit 意图 |
|---|---|---|
| 部分时间轴保存后 `start_time` 全 null | `documentWithoutTranslations` 丢弃 `explicitlyTimedLineIndices` | bugfix |
| 标记时间与锚点非单调 → `canSave=false` | harness `assist_mark` 夹在前后 timed 行之间 | harness |
| ad-hoc TCC 不稳 | Apple Development + `ENABLE_DEBUG_DYLIB=NO`（前序 TCC Identity Fix） | build |

---

## 1. 样本 A — 《夜の合図 / Kawasaki.Rio》

| 步骤 | 结果 |
|---|---|
| 纯文本加载 | QQ Experimental 32 行 `sync=false` |
| STREAM started | **YES** |
| Assist 草稿 | suggested=4–5 · unresolved=27–28 · anchors=4–5 |
| 人工 mark / undo / redo | mark done `canSave=true` · undo · redo 日志齐全 |
| 部分保存 | **manualEdit 子版本** parent=qqExperimental · `is_synced=0` · **timed=9/32** |
| 父纯文本 | timed=0/32（未覆盖） |
| 重启同临时库 | **RESTART_RESTORE_OK True** · 父子版本仍在 · child timed=9 |

临时库：见 `sample-a/temp-db.txt`

---

## 2. 样本 B — 《アイドル / YOASOBI》

| 步骤 | 结果 |
|---|---|
| LRCLIB 同步歌词 | 151 行 · `synced=1` · timed=151 |
| Assist 尝试 | harness 调用 `assist_start`；产品路径要求 `!isSynchronized` → **不写新时间轴** |
| 版本 | 仍仅 1 个 lrclib 版本 · timed=151 |
| **B_SYNCED_INTACT** | **True** |
| **B_NO_CLOBBER** | **True** |

---

## 3. 取消不写库

| 检查 | 结果 |
|---|---|
| STREAM started 后 `assist_cancel` | **ASSIST cancelled by user** |
| CLEANUP session | `exists_after=false` |
| 无 manualEdit 子版本 | **True** |
| timed_lines_total | **0** |
| wav_remaining | **0** |

---

## 4. 切歌 A→B 与 A→B→A

| 检查 | 结果 |
|---|---|
| Assist 中切到 アイドル | `ASSIST invalidate trackChanged` |
| 捕获会话 | `S2 stop reason=trackChanged` · `SESSION end … 夜の合図` |
| 新曲 SESSION begin | アイドル rev+1 |
| 再回 夜の合図 | SESSION begin 新 rev |
| HAS_INVALIDATE / TRACKCHANGE / CANCEL_OR_DROP | **True** |

---

## 5. 正式库

| 检查 | 结果 |
|---|---|
| before SHA | `a0ea0fc2489daddc29aba643d73a47a46d0f79b743f1883c4a2b10a7f9ec4ce6` |
| after SHA | **相同** |
| formal_equal | **YES** |
| formal_db_opened | **NO**（spike 日志） |
| 验收库 | 全部 `SPOTIFYLYRICS_DATABASE_PATH=/tmp/spotifylyrics-assist-final-*` |

---

## 6. 合同

```text
assist_candidate_merge_contract: PASS
assist_editor_contract: PASS
assist_session_contract: PASS
assist_partial_persist_contract: PASS
s3a_partial_alignment_contract: PASS
s3b_anchor_alignment_contract: PASS
```

---

## 7. 结论清单

| 要求 | 状态 |
|---|---|
| 样本 A 捕获→草稿→保存→重启恢复 | ✅ |
| 样本 B 已有同步版本不受 Assist 破坏 | ✅ |
| 取消不产生时间轴子版本 / 无 timed 行 | ✅ |
| 切歌取消旧 Assist / 无串歌 | ✅ |
| A→B→A identity 隔离 | ✅ |
| 正式库 SHA 不变 · formal_db_opened=NO | ✅ |
| 临时 WAV 清理 | ✅ |

**Phase 2.11B-Assist MVP ✅ 完成并真实验收。**

暂停：不进入 S3C / S4 / S5 / Phase 3。
