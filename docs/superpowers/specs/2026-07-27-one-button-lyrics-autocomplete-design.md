# 一键自动补全歌词 — 状态机、数据层与实现计划

> 日期：2026-07-27（Asia/Shanghai）  
> 状态：**原则已定，基础实现进行中**  
> 产品原则：**主路径必须是一个按钮自动完成**；打开网页→人工复制→粘贴 **不是** v1 默认，只作高级兜底。

关联：
- `2026-07-27-japanese-alias-lyrics-recovery-design.md`（别名 / 查询矩阵 / SafeMatcher）
- `2026-07-27-web-lyrics-discovery-jp-sites.md`（AWA/Uta-Net/UtaTime 发现层，不绕过反爬）

---

## 1. 产品原则

1. 单一入口：`自动补全歌词` → `LyricsRecoveryOrchestrator.autoComplete`  
2. 用户不必选择来源、不必复制网页。  
3. `pasteOrImport` / 手动创建仅在 **全部来源穷尽** 或用户主动打开高级选项时出现。  
4. Provider 单独失败不得中断整条链路。  
5. 禁止 Mock / 其他歌曲歌词回退。  
6. 已锁定的 original / kana / romaji / translation **不得**被自动覆盖。  
7. 日本站无公开正文接口时：只做发现/元数据证据，**不绕过反爬**，继续尝试其他 Provider。

---

## 2. 歌词数据层（必须独立）

| 层 | 字段 | 规则 |
|----|------|------|
| 原文 | `originalText` | 汉字/假名/标点/分行原样；永不被假名/罗马音覆盖 |
| 假名 | `kanaText` | Provider 读音优先；否则本地确定性生成；可锁 |
| 罗马音 | `romajiText` | 默认由 kana 确定性 Hepburn ASCII（ou）；可锁 |
| 翻译 | `translationText` | 预留；后续整首上下文 AI；可锁 |

模型：`LyricsTextLayers` + `LyricsLayerLock` + `LyricsLayerEnricher`  
行模型 `LyricLine` 已含 `originalText` / `kanaText` / `romajiText` / `translationText`。

本地假名：
- 纯假名/片假名：保留或转平假名  
- 含大量汉字：不猜中国音，返回 nil，等待 Provider/人工  

---

## 3. 一键状态机

```text
idle
  → planning            // TrackMetadata.bootstrap + QueryPlanner
  → queryingProviders   // Local → LRCLIB → experimental CN → licensed JP …
  → matching            // LyricsSafeMatcher per candidate
  → enrichingLayers     // kana/romaji fill, respect locks
  → alignmentQueued     // timing.none → 队列（暂不自动排轴）
  → saving              // 本地结果钩子（后续）
  → loaded

分支：
  matching → candidates     // 同名/翻唱/live/remix 冲突
  querying* → failed(isol.) // 单 Provider 失败，继续
  all exhausted → noMatchExhausted
       options: autoComplete(retry), openWebDiscovery,
                pasteOrImport(advanced), manualCreate
```

切歌：`generation` 递增；旧结果 `cancelled`，不得上屏。

### 自动采用

| 条件 | 动作 |
|------|------|
| 高/中置信且无版本冲突 | 自动采用 |
| live/remix/inst/同名冲突 | `candidates` |
| 仅 machineGenerated 别名证据 | ceiling=`candidates` |
| 全部无结果 | `noMatchExhausted` |
| 锁定层 | 跳过自动写 |

---

## 4. Provider 阶梯（启用顺序）

1. Local（只读索引）  
2. LRCLIB（已有隔离）  
3. 可启用的网易云 / QQ / 酷狗 **实验** Provider（一次接一个）  
4. 后续授权日语 Provider（Musixmatch / PetitLyrics 等）  
5. Web Discovery（AWA/Uta-Net/UtaTime）：**页面发现 + 元数据证据**，无授权不读正文  

---

## 5. 文件计划

### 已实现（本轮基础）

```text
SpotifyLyrics/Lyrics/TrackAlias.swift
SpotifyLyrics/Lyrics/TrackMetadata.swift
SpotifyLyrics/Lyrics/TrackTextNormalizer.swift
SpotifyLyrics/Lyrics/JapaneseRomanizer.swift
SpotifyLyrics/Lyrics/JapaneseKanaGenerator.swift
SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift
SpotifyLyrics/Lyrics/LyricsSafeMatcher.swift
SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift
SpotifyLyrics/Lyrics/LyricsRecoveryOrchestrator.swift
```

### 下一步

```text
SpotifyLyrics/Lyrics/LyricsSearchManager.swift     // 改用 multi-variant + orchestrator
SpotifyLyrics/Services/PlaybackState.swift        // 绑定「自动补全」按钮
SpotifyLyrics/Views/.../LyricsRecoveryPanel.swift // 失败态高级兜底
SpotifyLyrics/Providers/NetEase... (experimental) // 一次一个
Tests/lyrics_autocomplete_contract.swift          // 扩合同
```

---

## 6. 合同测试变化

| ID | 内容 | 原状态 | 现目标 |
|----|------|--------|--------|
| A* N* Q* M* R* | 别名/归一/查询/安全匹配 | 红（缺文件） | **绿** |
| L1 | original 不被 kana/romaji 覆盖 | 新 | 绿 |
| L2 | lock 阻止自动写 | 新 | 绿 |
| L3 | 汉字行不臆造假名 | 新 | 绿 |
| O1 | 无 Provider → exhausted，无 mock | 新 | 绿 |
| O2 | 单 Provider 失败仍可被后续命中 | 新 | 绿 |
| O3 | generation 取消 | 新 | 绿 |
| P0 | 缺生产文件 | 红门槛 | 文件齐则编译跑断言 |

`Tests/japanese_alias_contract.sh` 现要求 one-button 设计文档与 Orchestrator 源文件。

---

## 7. 非目标（本轮）

- 绕过 CF/验证码抓 Uta-Net/UtaTime  
- AI 翻译正文  
- 最终自动排轴算法（仅 `alignmentQueued` 状态）  
- 一次接入全部中文平台  

---

## 8. 实现顺序（执行中）

1. ✅ TrackAlias / QueryPlanner / SafeMatcher 红→绿  
2. ✅ original/kana/romaji 层模型与本地生成管线  
3. ✅ LyricsRecoveryOrchestrator 一键骨架  
4. ⬜ 接入 PlaybackState UI 一键入口  
5. ⬜ 多 variant 串 Local+LRCLIB  
6. ⬜ 一次只接一个补充 Provider 验证冷门日语覆盖  
