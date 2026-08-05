# Phase 2.11C-S4.5 — Local Real-Song Evaluation Gate

| 项 | 值 |
|---|---|
| 产品 | Lyric Island |
| 日期 | 2026-08-05 |
| 分支 | `codex/phase-2-11c-s4-5-real-song-gate` |
| 基线 | `449af66` (S4 repeated sections) |
| 算法修改 | **无**（评估-only） |
| formal DB | `d6d5f121…420b` before = after · **未打开** |
| 证据 | `docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/` |

---

## 1. 目标与边界

补齐真实混合歌曲证据，用 **Whisper small + 既有完整链路** 对照可信同步时间轴，判断是否具备进入自动质量门控设计的资格。

**禁止修改** Normalizer / Splitter / S3A/S3B / Repeated resolver / Local window / Merger / SpeechEngine / UI / schema。

---

## 2. 样本选择（本地 DB 只读）

从 `~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3` **只读** 扫描 `is_synced=1` 且 timed lines ≥15 的版本。

| 语言（脚本检测） | 池大小 |
|---|---:|
| ja | 51 |
| zh | 9 |
| en | 1 |

自动填 8 槽（慢/快/重复/短句 × 日/中/英）→ 本地 `local-real-songs/`（**gitignored**）写入 plain/gt/meta。  
仓库只提交 `anonymous_manifest.json`。

### 匿名清单（摘要）

见 `s4-5-real-song-gate/anonymous_manifest.json`：

- RS01–RS07：有 GT，**音频 pending_capture**
- RS-EXIST-A / RS-EXIST-B：既有真实 SCK 捕获 WAV（夜の合図 / アイドル）

**英文重复副歌槽：池中不足，无法填满 8 槽语言覆盖。**

---

## 3. 捕获状态

| 方式 | 结果 |
|---|---|
| Spotify AppleScript / URI play | **失败**：`cannot get current track` / player stopped |
| 既有真实捕获 WAV | A、B 可用 |
| 新 SCK 捕获 | **未执行**（无可用播放会话） |

未伪造音频；未下载商业音轨。

---

## 4. 固定处理链

```
Whisper small
→ TranscriptNormalizer → TranscriptSegmentSplitter
→ S3A → S3B → RepeatedLyricsSectionResolver
→ LocalAlignmentWindow → Merger
```

参数不因曲目改动。评分脚本 `score_against_gt.py` 用 **GT 时间轴** 判对错（含 capture 偏移估计），不信任算法 self-confidence。

---

## 5. 每首指标

| ID | 音频 | sug | correct† | wrong | wrong_occ | capture_viol | median\|err\| | >3s | wall | peak RSS |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| RS-EXIST-A | real capture | 5 | 0‡ | 0 | 0 | 0 | n/a‡ | 0 | ~2s | ~0.9GB |
| RS-EXIST-B | real capture | 3 | 3 | 0 | 0 | 0 | 0.0s | 0 | ~3s | ~0.9GB |
| RS01–RS07 | **missing** | — | — | — | — | — | — | — | — | — |

† offset-aligned vs GT  
‡ A：DB/LRCLIB 无可用 timed GT（`timed_count=0`），仅能确认有建议且无 capture 违例  

完整 JSON：`per_song_metrics.json`、`metrics_raw.json`。

### 错误类型分布（已评 2 首）

| 类型 | 计数 |
|---|---:|
| wrong_occurrence | 0 |
| capture_violation | 0 |
| timing_error_gt3s | 0 |
| non_monotonic | 0 |
| wrong (total hard) | 0 |

### 代理二次审计

- EXIST-B：3 条 accepted；GT 映射 8 行；offset 对齐后 err 中位 0；无 wrong_occurrence  
- EXIST-A：5 条 accepted；无 timed GT；无 capture 违例  
- 未评 7 槽：音频缺口，无建议可审计  

---

## 6. Medium 补充

主统计仅 small。零建议失败才跑 medium；本轮已评样本均非零，**未跑 medium**。

---

## 7. 资格判断

| 门槛 | 结果 |
|---|---|
| ≥6/8 真实歌非零建议 | **否**（仅 2 首有音频） |
| wrong_occurrence = 0 | 是（已评） |
| capture violation = 0 | 是（已评） |
| 错误建议率可控 | 样本不足，无法推广 |
| 多语言覆盖 | **否**（无英文完整评；中文无音频） |

**不能**宣布进入自动质量门控设计。

---

## 8. TEMP / formal DB

| 项 | 值 |
|---|---|
| formal before | `d6d5f121152057908ccd70cf4b83d8c76d86b9f4b9c9929326c45a60eb5f420b` |
| formal after | 相同 |
| formal opened | **NO**（只读 URI 扫描；评估不写库） |
| 商业 WAV | 未进 Git |
| 完整歌词 | 仅 local-real-songs（gitignore） |
| 模型 | 未进 Git |

---

## 9. 合同

新增（PASS）：

1. `real_song_manifest_contract`  
2. `ground_truth_timeline_contract`  
3. `automatic_reference_scoring_contract`  
4. `wrong_occurrence_metric_contract`  
5. `captured_range_violation_contract`  
6. `commercial_audio_not_tracked_contract`  
7. `copyrighted_lyrics_not_tracked_contract`  
8. `real_song_gate_contract`  

S1–S4 合同保持 PASS（算法未改）。

---

## 10. 最终路线（由本轮真实数据决定）

# **D. 多语言真实样本不足，先补样本，不继续算法**

### 依据

1. 本地库 **有** 足够日/中 GT，但 **缺** 可自动捕获的播放会话（Spotify scripting 无 current track）  
2. 英文池仅 1 首，无法满足英文慢/重复双槽  
3. 仅 **2** 首真实混音完成 Whisper small 评测，**未达 6/8**  
4. 已评 2 首暂无 wrong_occurrence / capture 违例，**不能**据此推断 8 歌全体  

### 不是 A/B/C 的原因

- **A**：样本规模与语言覆盖未达标  
- **B**：算法改动阶段应在样本齐备后；本轮证据不足以定义下一刀改哪里  
- **C**：无足够「真实混音识别失败」对比集；Demucs 前提不成立  

### 下一步（不实施）

1. 恢复 Spotify 可播放会话后，按 `local-real-songs/*/meta.json` 的 capture 窗自动抓 30–50s  
2. 优先补：RS05/06（中文）、RS07 + 再寻英文重复副歌  
3. 满 8 歌并达标后再重开 gate（可能转 A 或 B）  

**暂停。** 不修改算法，不实施全局自动开关 / 自动保存 / 自动采用。
