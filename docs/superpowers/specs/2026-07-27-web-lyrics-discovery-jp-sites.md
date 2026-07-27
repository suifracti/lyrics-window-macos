# Web Lyrics Discovery — 日语三站（AWA / Uta-Net / UtaTime）审计与设计

> 日期：2026-07-27（Asia/Shanghai）  
> 状态：**设计 + 黑盒审计，等待确认后再实现**  
> 范围：Lyrics Recovery 的网页发现层；**不实现自动抓取歌词正文**  
> 关联：`docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md`  
> 触发曲：`あやふや / みさき` · Spotify `4l6XKftR34zrUw0bTnwoVv` · 时长约 `119.16s`  
> 错误 URL 警示：用户曾提供的 AWA 链接对应 **`水曜日の約束 / Kawasaki.Rio`**，**不得**绑定到当前曲。

---

## 0. 结论先行

1. 冷门日语曲（如 `あやふや`）在 LRCLIB 常 `noMatch`；Uta-Net / UtaTime 公开索引里**能找到页面**，AWA **公开 Web 曲库搜索不可用**。  
2. 本阶段三站只进入 **Web Lyrics Discovery**：搜索候选 → 匹配分数 → **外链 / 复制查询词 / 用户手动粘贴导入**。  
3. **不**默认抓取正文、**不**永久缓存在线歌词、**不**绕过 Cloudflare / 403 / 验证码 / 登录、**不**用 WKWebView 伪装成站内页。  
4. Uta-Net 条款与链接政策明确限制复制与框架嵌入 → 角色锁定为 **search / match / outbound only**。  
5. UtaTime（含历史域名 Lyrical Nonsense）对 `あやふや` 确认有 **原文 + 罗马音 + credits + 视频位**；自动化 `curl` 常 403，第一版仍以发现+外链+手动导入为准。  
6. AWA 歌词能力在 **App 内播放路径（含 LYRIC DIVE）**，不是公开 Web 歌词 API；Web 侧仅营销/条款/下载。  
7. 粘贴/导入必须先 **预览清洗**，用户确认后才可写入 session / 本地保存。

### 与用户诉求的对齐（边界说明）

冷门歌经常「三个站里只有一个有」——**发现层必须覆盖三站**。  
但「有页面」≠「应用可自动抽正文」。第一版把价值放在：

- 用别名矩阵找到**正确页面**（避免错绑 `水曜日の約束`）  
- 一键外链 / 复制检索词  
- 用户从浏览器复制后 **安全导入预览**  

自动正文抓取若要做，必须在后续单独评审（站点条款 + 可访问性 + 产品责任），**不在本轮实现**。

---

## 1. 黑盒审计摘要（2026-07-27）

### 1.1 访问通道

| 目标 | 自动化 curl（本机） | 检索索引 / 受控浏览 | 备注 |
|------|---------------------|---------------------|------|
| `awa.fm` 首页 | 200 | 可用 | Next.js 营销站 |
| `awa.fm/robots.txt` | 落到 404 HTML | 无真实 robots 文本 | SPA 式 404 |
| `awa.fm/search` · `s.awa.fm/search` | 404 | 无公开 Web 曲库搜索 | |
| `awa.fm/ja/terms` | 200 | 可用 | 日本服务利用规约 |
| `guide.awa.fm` 歌词帮助 | CF challenge | 公开新闻/二手描述可用 | 歌词在 App 播放中 |
| `uta-net.com/*` | **403 CF**（含 robots、kiyaku、song、search） | 搜索引擎摘要可见 | 不得绕过 |
| `lyrical-nonsense.com/robots.txt` | 200，再 301→`utatime.com` 后 robots 亦 403 | robots 正文曾可读 | 见 §3 |
| `utatime.com` / 歌词页 | **403 CF**（curl） | **browse 通道可读正文结构** | 品牌 UtaTime |
| `utatime.jp` / `www.utatime.jp` | SSL/连接失败 | 视为废弃域名 | 勿作为主入口 |

### 1.2 当前曲 `あやふや / みさき` 页面匹配（索引级）

| 来源 | 候选 URL（发现用，非授权抓取令牌） | 标题 | 艺人 | 发行 | credits | 时长 | 判定 |
|------|--------------------------------------|------|------|------|---------|------|------|
| Uta-Net | `https://www.uta-net.com/song/374864/` | あやふや | みさき | 2025-06-18（英页摘要） | 作词/作曲：みさき | **未在摘要确认** | **强候选**（名+艺人+作词作曲一致） |
| UtaTime JA | `https://www.lyrical-nonsense.com/lyrics/misaki/ayafuya/` → `utatime.com/lyrics/...` | あやふや | みさき | 2025.06.18 | 作词/作曲：みさき；编曲：Devincy・Luisx・Ryotaro | **未确认** | **强候选**；有原文 |
| UtaTime EN/Romaji | `.../global/lyrics/misaki/ayafuya/` | Ayafuya / あやふや | MISAKI / みさき | 2025.06.18 | 同上 | **未确认** | **强候选**；有罗马音层 |
| AWA Web | （无公开 song URL） | — | — | — | — | — | **Web 无候选**；勿使用错误曲 URL |
| 错误样例 | （用户曾给的 AWA 链） | 水曜日の約束 | Kawasaki.Rio | — | — | — | **必须拒绝** |

时长约 119s 目前只能作 **Spotify 侧证据**；三站公开摘要**均未稳定给出 duration**，故自动采用不得只靠页内时长。

---

## 2. 能力矩阵

图例：`Y` 已确认 · `P` 部分/条件 · `N` 无或不适用 · `U` 本轮自动化未验证（被拦或无公开页） · `App` 仅 App 内

| 能力 | AWA | Uta-Net（歌ネット） | UtaTime（旧 LN） |
|------|-----|---------------------|------------------|
| **歌名** | App / 营销；Web 搜索 N | Y（索引+歌页） | Y |
| **艺人** | App | Y | Y（日文+拉丁别名页） |
| **专辑** | App 可能；Web U | P/U（歌页结构常见有关联，本轮 CF 未直读 DOM） | P（封面/发行物引用，browse 见 jacket 关联） |
| **时长** | App 可能；Web U | U（摘要未见） | U（详情表未见 duration） |
| **封面** | App；Web 营销图非曲级 | U | P（站内 jacket 引用） |
| **发行日期** | App | Y（摘要 06-18-2025） | Y（2025.06.18） |
| **作词** | U/App | Y | Y |
| **作曲** | U/App | Y | Y |
| **编曲** | U | U | Y（Devincy・Luisx・Ryotaro） |
| **原文歌词** | **App 播放中**；Web API N | Y（站内展示；**禁止未许可复制**） | Y（站内展示） |
| **假名（振假名层）** | U | U/常见 N 或非独立层 | 本轮未见独立假名轨；原文即日文正字 |
| **罗马音** | U/N | N（主打日文歌词） | **Y**（global Romanized 页） |
| **英文/其他翻译** | U/N | N/少 | P（可 request/submit translation；本曲英译未在 browse 主列确认） |
| **逐行时间轴** | App LYRIC DIVE 动画歌词（播放同步） | N（静态歌词站） | N（静态；无 LRC 字段） |
| **相关视频** | U | U | Y（Live Performance / 视频区） |
| **外部播放入口** | 自身为流媒体；官方嵌入播放器（规约约束） | 通常链到站内/合作方；U | 外链分享；非 Spotify 深链保证 |
| **站内歌曲/歌词搜索** | **公开 Web 搜索 404**；App 内搜索 | Y（`/search/?Keyword=`，自动化 403） | Y（站内检索；自动化常 403） |
| **正式公开歌词 API** | **N** | **N** | **N** |
| **robots.txt** | 无有效文本（路径 404 HTML） | **不可读**（CF 403） | `lyrical-nonsense.com/robots.txt` 可读，含 Content-Signal（见 §3） |
| **利用条款（本轮）** | Y：权利归属 + 禁止超私的复制等 | 索引级：禁止未许可复制；链接政策限制歌词深链/框架 | 完整 ToS 页 curl 403；robots Content-Signal 部分约束 |
| **403 / 验证码 / 登录** | 条款页可开；帮助/部分资源 CF；歌词要 App | **全站 CF challenge（自动化）** | **curl 常 CF**；部分审计通道可读 |
| **iframe / WKWebView 嵌入歌词页** | `frame-ancestors 'none'` / `X-Frame-Options: SAMEORIGIN`（站点响应） | 链接政策要求框架外显示；**禁止当 App 内页伪装** | CF/`X-Frame-Options: SAMEORIGIN`（challenge 响应）；**勿嵌入伪装** |
| **适合 v1 产品角色** | 元数据/有歌词信号/App 外链（弱） | **发现+外链 only** | **发现+外链+罗马音存在标记**；正文靠用户粘贴 |

### 内容标记（映射到 `WebLyricsCandidate.availability`）

| 标记 | AWA | Uta-Net | UtaTime |
|------|-----|---------|---------|
| `originalLyrics` | App-only → candidate 标 `unknown`/`appOnly`，**not programReadable** | 页存在 → `true`，**programReadable=false** | 页存在 → `true`，v1 **programReadable=false** |
| `kana` | U | U/false | false（未见独立层） |
| `romaji` | U/false | false | **true**（global 页） |
| `translation` | false/U | false | partial/unknown |
| `credits` | U | true（作词作曲） | true（含编曲） |
| `video` | U | U | true |
| `timedLyrics` | App only | false | false |

---

## 3. 条款 / robots / 权利结论

### 3.1 AWA（`awa.fm`）

**已读：** `https://awa.fm/ja/terms/`（日本国内 AWA 服务利用规约）

| 点 | 结论 |
|----|------|
| 权利归属 | 第5条：服务提供的数据/文/音/影像等权利归 AWA 或第三方 |
| 禁止事项 | 第12条：对数据等超出著作权法私的使用范围的 **复制、颁布、转让、贷与、公众送信、逆向** 等禁止 |
| 嵌入 | 仅允许 **指定方法的嵌入播放器**；禁止改変、非指定方式使用 |
| 歌词 | 公开帮助/报道：歌词在 **App 再生中** 显示；**LYRIC DIVE** 为 App 内动画歌词，非 Web API |
| 公开 API | **未发现** 歌词或曲库 Web API |
| 产品含义 | v1：**不**抓取/不永久存 AWA 歌词正文；最多做「在 AWA 打开/下载 App」类外链与「App 内可能有词」提示（若未来有官方 deep link 再增强） |

**CSP/Frame：** 条款响应含 `frame-ancestors 'none'`、`X-Frame-Options: SAMEORIGIN` → **禁止** 把 AWA 页当 App 内嵌歌词浏览器。

### 3.2 Uta-Net（`uta-net.com`）

**直接读取：** robots / 规约 / 链接政策 / 歌页 **本轮均 CF 403**，不得绕过。

**公开索引与既有共识（搜索摘要，标注为间接证据）：**

- 歌词页存在且可被搜索引擎收录（例：`/song/374864/` あやふや）。  
- 利用规约方向：服务以浏览/配信为主；**未经许可的复制、改変等受限制**（社区与过往摘要一致；完整条文待用户浏览器过验证后复核）。  
- `info/link.html` 摘要：希望链到顶级域；**歌词显示页链接有额外限制**；要求在 **框架外（フレーム外）** 显示 → **禁止 iframe 套壳**。

| 产品含义 | 硬边界 |
|----------|--------|
| 允许 | 构造搜索 URL、展示候选标题/艺人/song id、**系统浏览器打开**、复制查询词 |
| 禁止 | 自动拉取完整歌词正文、默认持久化站内词、WKWebView 伪装站内页、绕过 CF |

`allowsProgrammaticRead = false`  
`outboundOnly = true`  
`rightsStatus = termsRestrictCopyAndFrame`（待用户过 CF 后把条款锚点补全）

### 3.3 UtaTime / Lyrical Nonsense

**域名：** 品牌 **UtaTime**；`lyrical-nonsense.com` → `utatime.com`。`utatime.jp` 不可用。

**robots（`https://www.lyrical-nonsense.com/robots.txt`，本轮曾成功读取）：**

```text
User-agent: *
Content-Signal: search=yes, ai-train=no, use=reference
Allow: /

# 多家 AI/扩展爬虫 Disallow（GPTBot、ClaudeBot、Bytespider 等）
```

解读（产品侧保守）：

- **search=yes**：为搜索索引构建、返回**超链接 + 短摘要**类发现，与「候选列表」方向一致。  
- **ai-train=no**：禁止把站内正文当训练语料。  
- **use=reference**：AI/系统消费偏向引用/参考，**不是**「全文搬运进 App 当默认歌词源」。  
- 大量 bot Disallow + 站点 CF → 自动化采集本身不可靠且不受欢迎。

**能力（browse 审计，あやふや）：**

- 原文歌词页（JA）  
- Romanized 页（EN global）  
- 详情：发行日、作词、作曲、编曲、Official Full 状态、视频区  
- **无** 公开 API；**无** 确认的逐行 LRC  

**完整利用条款页：** curl 403，本轮不假装已逐条审计。v1 仍按 **发现 + 外链 + 用户粘贴**；不默认 program read。

| 产品含义 | v1 |
|----------|----|
| `romaji` 可用性可标 true（有 global 页时） | 是 |
| 自动正文 | **否** |
| 用户粘贴导入 | 是（预览+清洗+确认） |

### 3.4 总表：权利 / 技术闸门

| 站点 | API | 自动正文 v1 | 外链 | 嵌入 WebView | 绕过防护 | 默认持久化在线词 |
|------|-----|-------------|------|--------------|----------|------------------|
| AWA | N | N | P（App/站） | N | N | N |
| Uta-Net | N | **N** | Y | **N** | N | N |
| UtaTime | N | **N** | Y | N | N | N |

---

## 4. 页面匹配方案

### 4.1 输入

已确认的 `TrackIdentity` + `TrackMetadata` +（可选）`[TrackAlias]`（见日语别名设计）+ Spotify 时长/ISRC/ID。

**禁止：** 把任意用户粘贴的 URL 在未校验前写成 identity 绑定。

### 4.2 查询生成（有序，复用别名矩阵）

对每个 provider 生成 `WebDiscoveryQuery` 列表（截断 top-N，默认 6）：

1. `originalTitle + originalArtist`  
2. `normalizedTitle + normalizedArtist`（NFC/NFKC、全半角、空白标点、feat. 剥离）  
3. `kanaTitle + artist`（若有）  
4. `romajiTitle + romajiOrOriginalArtist`  
5. `officialEnglish + artist`  
6. `provider/user aliases`  
7. `title-only loose`（降权，仅扩大召回）

**あやふや示例查询（节选）：**

- `あやふや みさき`  
- `あやふや MISAKI`  
- `Ayafuya Misaki` / `Ayafuya MISAKI`  
- song id 直链仅在**已验证**后缓存为 candidate URL，不从错误曲继承  

### 4.3 Provider 搜索 URL 模板（发现用，非 scraper）

| Provider | 模板 | 备注 |
|----------|------|------|
| AWA | **无稳定公开 search**；可选 `https://awa.fm/` 或官方 App store / guide 落地 | `searchSupported=false` |
| Uta-Net | `https://www.uta-net.com/search/?Keyword={urlquery}` | 结果页可能 CF；仍可「浏览器打开此搜索」 |
| UtaTime | 优先站内 search（若模板稳定）；并支持 slug 猜测仅作 **低置信** | 已知命中可记 `https://www.utatime.com/lyrics/{artist-slug}/{title-slug}/` 与 `/global/lyrics/...`；**slug 猜中 ≠ 身份证明** |

### 4.4 候选解析与打分（不自动采用正文）

`WebLyricsCandidate.matchScore`（0...1）建议因子：

| 因子 | 权重方向 |
|------|----------|
| 标题 exact / normalized / alias | 高 |
| 艺人 exact / alias（みさき ↔ MISAKI） | 高 |
| 作词/作曲与艺人一致（自写自唱） | 中 |
| 发行日接近已知发行 | 中低 |
| 专辑名 | 中 |
| 时长差 ≤2s / ≤5s | 高（**仅当页内有时长**） |
| Spotify ID / ISRC 页内出现 | 极高（罕见） |
| 仅标题命中、艺人冲突 | 封顶低分，**不得** auto-open 为唯一结果 |
| 与当前 identity 明显不同曲（例：水曜日の約束） | **score=0 reject** |

**安全规则（继承别名设计）：**

1. 发现命中 **只扩大恢复入口**，不证明 lyrics 已加载。  
2. **不得**因网页候选自动覆盖已有 Local/LRCLIB 成功结果。  
3. 同名、翻唱、live、instrumental 全部进列表。  
4. 官方别名 > provider 别名 > 机器罗马音。  
5. 无时长/ISRC 时，UI 只展示「打开网页 / 复制 / 手动导入」，不显示「已自动匹配歌词」。

### 4.5 错误 URL 防护（回归用例）

```text
given TrackIdentity(あやふや, みさき, duration≈119.16, spotify=4l6XKftR34zrUw0bTnwoVv)
when candidate = AWA_or_any(title: 水曜日の約束, artist: Kawasaki.Rio)
then reject (matchScore=0, reason=titleArtistMismatch)
and never bind URL into TrackIdentity
```

### 4.6 Provider 失败隔离

与 LRCLIB 相同哲学：

- 每站独立超时（建议 8–12s 发现请求；**v1 若只生成 URL 则无网络**）  
- 独立错误：`blocked` / `challenge` / `timeout` / `network` / `noResults` / `unsupported`  
- 一站 403 **不得**清空其他站候选  
- 切歌：`searchID` / `Task` 取消，丢弃乱序回调  
- **不得**把失败显示成全局「程序崩溃」；文案区分「源站限制访问」vs「无候选」

---

## 5. 架构设计（拟实现，本轮不写生产代码）

### 5.1 类型

```text
WebLyricsContentFlags
  originalLyrics: Bool
  kana: Bool
  romaji: Bool
  translation: Bool
  credits: Bool
  video: Bool
  timedLyrics: Bool

WebRightsStatus
  unknown
  outboundOnly
  termsRestrictCopyAndFrame
  robotsAllowSearchReferenceOnly
  appOnlyContent
  userImportOnly

WebLyricsCandidate
  id: String
  trackIdentity: TrackIdentity          // 查询上下文，不是「网页已证明同一首歌」
  source: WebLyricsSource               // awa | utaNet | utaTime
  pageTitle: String?
  artistName: String?
  pageURL: URL
  searchURL: URL?                       // 列表/搜索页
  availability: WebLyricsContentFlags
  matchScore: Double
  allowsProgrammaticRead: Bool          // v1 全 false
  outboundOnly: Bool
  rightsStatus: WebRightsStatus
  releaseDateText: String?
  creditsSummary: String?
  diagnostics: String?                  // 不可展示密钥
  fetchedAt: Date

WebLyricsDiscoveryQuery
  title: String
  artist: String?
  strategy: enum
  aliasesUsed: [TrackAlias.ID]

WebLyricsDiscoveryResult
  provider: WebLyricsSource
  queries: [WebLyricsDiscoveryQuery]
  candidates: [WebLyricsCandidate]
  error: WebDiscoveryError?
```

### 5.2 协议与实现类

```text
protocol WebLyricsDiscoveryProvider
  var id: WebLyricsSource { get }
  var displayName: String { get }
  func discover(identity: TrackIdentity,
                metadata: TrackMetadata,
                aliases: [TrackAlias],
                signal: CancellationSignal) async -> WebLyricsDiscoveryResult

WebLyricsDiscoveryManager
  // 并行 fan-out；隔离错误；合并排序；绑定 search generation

AWAWebDiscoveryProvider
  // searchSupported=false
  // 返回：引导性 candidate 或 empty + appOnly hint（无错绑 URL）

UtaNetWebDiscoveryProvider
  // 构造 Keyword 搜索 URL；可选：若未来有「用户粘贴的 uta-net song URL」则解析 id
  // allowsProgrammaticRead=false, outboundOnly=true

UtaTimeWebDiscoveryProvider
  // 构造搜索/已知 slug 候选；标记 romaji 页 URL 为第二 candidate
  // allowsProgrammaticRead=false；rightsStatus=robotsAllowSearchReferenceOnly 或 unknown
```

**v1 推荐默认实现策略（仍待你确认）：**

- **A. URL 构造 + 浏览器打开（零抓取）** —— 最低风险，可先做。  
- **B. 可选：用户完成系统浏览器访问后「分享 URL 到 App」再解析元数据字段** —— 仍不批量爬。  
- **C. 服务端/官方 API** —— 无则不做。  

**明确不做：** 后台静默 HTML 全文歌词抽取、验证码破解、cookie 共享伪装登录。

### 5.3 接入 Lyrics Recovery 状态机

扩展既有 `LyricsRecoveryState`（别名设计 §2.7）：

```text
providersExhausted
  → webDiscovery(loading)
  → webDiscovery(results: [WebLyricsCandidate])
  → webDiscovery(partialFailure)
  → manualImport(preview)
  → manualTiming
  → resolved / dismissed
```

触发条件：Local + LRCLIB（+ 未来中文插件）均 `noMatch`/`failed`，或用户点「网页恢复」。

### 5.4 Recovery UI（文案可中文）

当进入网页恢复：

1. **AWA** 区：无 Web 命中时说明「AWA 歌词主要在 App 内」+ 复制曲名艺人 +（可选）打开 AWA 站点  
2. **Uta-Net** 区：候选行（标题/艺人/分数/「仅外链」徽章）+ **在浏览器打开** + 打开搜索页  
3. **UtaTime** 区：原文页 / 罗马音页分条 + 打开浏览器  
4. 全局动作：  
   - 复制当前搜索词（多别名切换）  
   - 从剪贴板粘贴歌词  
   - 导入 TXT / LRC / TTML  
   - 手动创建空白歌词  
5. 粘贴/导入 → **预览编辑器**（非立即覆盖）

### 5.5 粘贴与清洗管线

```text
RawImport
  sourceURL?: URL
  importedAt: Date
  rawText: String                 // 不可变副本
  cleanedText: String
  layers: detect → original / romaji / translation / unknown
  timing: none | lrc | ttml | manual
  userEdits: ...
  status: preview | confirmed | discarded
```

清洗规则（启发式，可关）：

- 去掉导航/菜单/「コピー」「感想」「ランキング」「利用規約」等 chrome 块  
- 压缩空行但保留段落  
- 检测罗马音行（拉丁比例）与日文行分层  
- 保留 `rawText` 始终可「恢复原始粘贴」  
- `timing.none` 时提供手动逐行排轴入口（后续音频辅助另案）  
- **确认前** 不写 LocalLyrics 库、不改当前 locked lyrics  

---

## 6. 拟修改 / 新增文件

> 确认前仅文档；实现阶段再动代码。

### 6.1 文档（本轮）

| 文件 | 动作 |
|------|------|
| `docs/superpowers/specs/2026-07-27-web-lyrics-discovery-jp-sites.md` | **本文件（新增）** |
| `docs/superpowers/specs/2026-07-27-japanese-alias-lyrics-recovery-design.md` | 后续补交叉链接（实现前） |

### 6.2 模型与发现层（实现阶段）

| 文件 | 职责 |
|------|------|
| `SpotifyLyrics/Lyrics/WebLyricsDiscoveryModels.swift` | `WebLyricsCandidate`、flags、rights、errors |
| `SpotifyLyrics/Lyrics/WebLyricsDiscoveryProvider.swift` | protocol + `WebLyricsDiscoveryManager` |
| `SpotifyLyrics/Lyrics/AWAWebDiscoveryProvider.swift` | AWA：无 Web 搜索时的降级发现 |
| `SpotifyLyrics/Lyrics/UtaNetWebDiscoveryProvider.swift` | Uta-Net 搜索 URL / 外链候选 |
| `SpotifyLyrics/Lyrics/UtaTimeWebDiscoveryProvider.swift` | UtaTime 原文+romaji URL 候选 |
| `SpotifyLyrics/Lyrics/WebDiscoveryQueryBuilder.swift` | 别名 → 有序查询（复用 alias normalizer） |
| `SpotifyLyrics/Lyrics/WebCandidateMatcher.swift` | 打分与错误 URL 拒绝 |
| `SpotifyLyrics/Lyrics/LyricsImportPipeline.swift` | 粘贴/文件导入、清洗、分层、preview |
| `SpotifyLyrics/Lyrics/LyricsRecoveryModels.swift` | 恢复状态（若尚未从别名设计落地） |
| `SpotifyLyrics/Lyrics/LyricsRecoveryController.swift` | 串联 provider 失败 → web discovery → import |

### 6.3 UI（实现阶段）

| 文件 | 职责 |
|------|------|
| `SpotifyLyrics/Views/Components/LyricsRecoveryPanel.swift` | 三站结果 + 动作按钮 |
| `SpotifyLyrics/Views/Components/LyricsImportPreviewView.swift` | 预览/分层/确认 |
| `SpotifyLyrics/Views/MainWindow/*` 或现有歌词空态 | 接入「网页恢复」入口（无回归播放控件） |

### 6.4 测试（实现阶段；本轮可选红合同）

| 文件 | 职责 |
|------|------|
| `Tests/web_lyrics_discovery_contract.swift` | 模型字段、错误隔离、错误 URL 拒绝 |
| `Tests/web_lyrics_discovery_contract.sh` | 编译/断言入口 |
| `Tests/lyrics_import_pipeline_contract.swift` | 清洗不丢 raw、确认前不覆盖 |
| 扩展 `provider_failure_contract.swift` | Web provider 403 不影响 Local/LRCLIB |

### 6.5 明确不修改（本轮/ v1 发现）

- `LRCLIBLyricsProvider` 隔离逻辑  
- Spotify Desktop 播放控制  
- `LocalLyricsIndex` 只读扫描契约  
- 不把 Web discovery 并回 `TrackSearchManager` 自由文本曲库  

---

## 7. 合同测试案例（设计级，待实现）

1. **职责隔离：** `WebLyricsDiscoveryProvider` 不返回 `LyricsDocument` 正文。  
2. **错误 URL：** `水曜日の約束` 候选对 `あやふや` identity → reject。  
3. **Uta-Net rights：** candidate `allowsProgrammaticRead == false && outboundOnly == true`。  
4. **UtaTime romaji flag：** global ayafuya URL → `availability.romaji == true`。  
5. **AWA search：** `searchSupported == false`，不抛全局 fatal。  
6. **部分失败：** Uta-Net `blocked`，UtaTime 仍可有 outbound candidates。  
7. **切歌取消：** generation-N 结果在 generation-N+1 丢弃。  
8. **粘贴预览：** import 后当前 `LyricsLoadState` 不变直至 confirm。  
9. **清洗保留 raw：** `rawText` 与 `cleanedText` 独立。  
10. **无时间轴：** plain text → `timing.none`。  
11. **Frame：** 不存在默认 `WKWebView(url: uta-net song)` 代码路径（静态扫描/结构断言）。  
12. **不写盘：** discovery 成功不创建 Lyrics/ 下在线缓存文件。

---

## 8. 非目标（Non-goals）

- 自动抓取 Uta-Net / UtaTime / AWA 歌词全文  
- 绕过 Cloudflare、验证码、登录墙  
- 用 WKWebView 嵌歌词页并注入脚本抽 DOM  
- 默认持久化在线歌词到 Local index  
- Spotify Web OAuth、网易云/QQ/酷狗核心化（仍插件实验）  
- 将 Web 发现误当作 Track 曲库搜索 Provider  

---

## 9. 建议落地顺序（确认后）

| 步 | 内容 | 风险 |
|----|------|------|
| P0 | 模型 + QueryBuilder + Matcher + 仅 URL 外链 UI | 低 |
| P1 | 粘贴/导入预览管线 + timing.none | 低 |
| P2 | 与别名矩阵打通（Ayafuya 等） | 中 |
| P3 | （可选）用户分享 URL 回填元数据 | 中 |
| P4 | 任何「程序可读正文」→ **单独授权/条款复核** | 高 |

---

## 10. 待你确认的问题

1. v1 是否接受 **纯外链 + 手动粘贴**（推荐），还是必须先做「用户分享 URL 解析」？  
2. UtaTime 原文/罗马音是否在 UI 上拆成两个 candidate 行？  
3. AWA 在无 Web 命中时，是隐藏区块还是显示「App 内歌词」说明？  
4. 是否现在就加红色合同文件（不实现生产代码），与 `japanese_alias_contract` 同级？  

---

## 11. 审计证据索引

| 证据 | 来源 |
|------|------|
| AWA 条款第5/12/13条 | `https://awa.fm/ja/terms/` 2026-07-27 |
| AWA Web 搜索 404 | curl `awa.fm/search` / `s.awa.fm/search` |
| AWA 歌词在 App + LYRIC DIVE | guide/新闻公开描述（App 路径） |
| AWA frame 限制 | 响应 `frame-ancestors 'none'` / `X-Frame-Options` |
| Uta-Net CF 403 | curl robots/home/song/search/kiyaku/link |
| Uta-Net あやふや页 | 搜索索引 `song/374864` |
| Uta-Net 链接/框架 | 搜索摘要 `info/link.html` |
| UtaTime あやふや原文/罗马音/credits/video | browse `lyrical-nonsense`/`utatime` lyrics pages |
| UtaTime robots Content-Signal | `lyrical-nonsense.com/robots.txt` |
| 错误曲 | 用户 AWA URL ≠ あやふや |

---

**本轮交付结束：能力矩阵 · 条款结论 · 匹配方案 · 拟改文件。**  
**暂停实现自动歌词抓取，等待确认。**
