# 歌曲目录与歌词来源调研及可执行方案

> 调查日期：2026-07-27（Asia/Shanghai）  
> 范围：歌曲目录搜索、当前播放识别、歌词版本搜索与发布风险  
> 本轮边界：只做调研和架构审计，不修改 Swift 源码、不接入新的 Provider、不提交业务实现。

## 0. 结论先行

当前项目最需要先拆开的不是“再加几个搜索接口”，而是三个不同问题：

1. **当前播放识别**：Spotify Desktop Apple Events 已经能得到正在播放的歌曲、封面和进度；它不是一个可输入任意关键词的曲库搜索服务。
2. **歌曲目录搜索**：根据自由文本找到歌曲元数据（标题、艺人、专辑、时长、封面、ISRC、平台 ID）。
3. **歌词版本搜索**：在一个已经确认的 `TrackIdentity` 上寻找普通歌词、逐行歌词、翻译或逐字歌词，并按匹配置信度选择或展示候选。

因此建议最终拆成：

```text
TrackSearchManager
├── SpotifyCatalogSearchProvider
├── AppleMusicCatalogSearchProvider（可选）
├── LocalTrackSearchProvider
├── MusicBrainzMetadataProvider（可选）
└── CurrentTrackResolver（Spotify Desktop，非目录搜索）

LyricsSearchManager
├── LocalLyricsProvider
├── LRCLIBLyricsProvider
├── MusixmatchLyricsProvider（取得授权后）
├── NetEaseLyricsProvider（实验插件）
├── QQMusicLyricsProvider（实验插件）
└── KuGouLyricsProvider（实验插件）
```

### 最推荐的第一阶段组合

- 保留现有 `SpotifyDesktopProvider`，在架构上改名/定位为 `CurrentTrackResolver`。
- 立即保留只读的 `LocalLyricsProvider`，作为最高优先级；它不复制、修改或保存用户文件。
- 继续使用 `LRCLIBLyricsProvider`，但仅作为**个人桌面、明确可关闭的外部来源**，设置有限超时、手动重试、无旧歌回退和可观测的 Provider 状态。
- 本阶段不接网易云、QQ 音乐或酷狗的非公开接口，不接 Spotify 私有歌词接口，也不把 Apple Music 的 `hasLyrics` 误当作歌词正文。
- 如果目标转向公开发行或 App Store，LRCLIB 不能直接视为权利清晰的歌词数据库；应先取得 Musixmatch 等有明确授权的商业合同，再开放在线歌词默认路径。

## 1. 调查边界、日期和验证方法

- 官方文档优先；无法确认官方能力时标为“未找到/未证实”，不以旧博客替代结论。
- 对开放服务和中文平台做了最小只读请求：LRCLIB `/api/search`、`/api/get`，网易云公开网页接口，QQ Music 搜索及歌词接口，酷狗移动搜索接口，MusicBrainz 查询接口。请求只读取公开响应，不保存歌词或平台资源。
- Spotify Web API、Apple Music/MusicKit、Musixmatch 使用当前官方文档/官方 API 说明，不伪造凭证进行登录测试。
- 本轮**没有启动、读取、解包、反编译或检查** `/Applications/Dynamic Lyrics.app` 的闭源实现、二进制、私有接口或资源。此前 UI 黑盒审计资产不作为本轮 Provider 结论或可复用实现。
- 代码/数据版权与服务条款是两个问题：开源仓库的许可证通常只覆盖代码，不自动授予歌词数据库、封面或平台接口数据的再分发权。本文件是工程调研，不是法律意见。

## 2. Lyricify-App-main 公开参考审计

### 许可证结论

在 `/Users/apple/backup/sptifylyrics/Lyricify-App-main` 检查了根目录和常见子目录，没有发现 `LICENSE`、`LICENSE.*` 或 `COPYING*`。该副本也不是一个独立 Git checkout，不能把本地文件当成可复制源码许可。

公开 GitHub 项目 README 明确说，歌词处理部分另行开源在 `WXRIW/Lyricify-Lyrics-Helper`，该仓库的 `LICENSE` 是 Apache License 2.0。Apache 2.0 只给该 helper 仓库代码的许可证权限；不能据此复制 Lyricify 产品品牌、图标、截图、服务凭据或未经授权的平台数据。

### 实际读取的公开文件和线索

- `Lyricify-App-main/README.md`：Lyricify 4 的 Spotify 定位、历史版本支持的播放器、公开截图入口、helper 仓库链接。
- `Lyricify-App-main/README.3.md`：旧版本能力说明。
- `Lyricify-App-main/docs/Lyricify 3/README.md`：旧版本架构/功能说明。
- `Lyricify-App-main/docs/Lyricify 4/README.md`、`docs/Lyricify 4/Lyrics.md`：歌词搜索、导入、编辑、时间轴偏移等产品行为。
- `Lyricify-App-main/docs/Lyricify 4/CustomClient/Readme.md`、`Readme.zh-CN.md`：自定义 Spotify Client 的旧文档；内容提示 Spotify API、Premium、redirect URI 和上游 API 变化，属于维护风险证据，不能当作当前接入步骤。
- `Lyricify-App-main/i18n/Lyricify 3/Lang_CN.xaml`、`Lang_EN.xaml`：语言文案出现 QQ Music、网易云按平台 ID 取歌词等线索，但不是 Provider 实现。
- `Lyricify-App-main/images/readme/*` 和 `docs/Lyricify 4/img/*`：只作为既有产品行为的公开截图证据，不进入 SpotifyLyrics 资源包。

公开 helper 的架构线索（通过其 README/公开目录审计）：

- `Providers/` 与 `Searchers/` 分开；搜索器包含 Apple Music、Kugou、LRCLIB、Musixmatch、NetEase、QQ Music、Soda Music、Spotify 等。
- 搜索器返回 `ISearchResult`，Provider 根据搜索结果获得歌词；`IProviderResult` 将 Provider 与搜索结果关联。
- 支持 LRC、QRC、KRC、YRC、TTML、Spotify raw JSON、Musixmatch raw JSON 等解析格式。
- helper 是 .NET/Windows 生态代码；即使 Apache 2.0 允许复用某些通用解析代码，也不代表其中平台 endpoint、签名算法、Cookie、密钥或数据使用方式适合原生 macOS。当前建议只借鉴“目录搜索”和“歌词 Provider”分层，不复制实现。

公开仓库与 helper：

- [Lyricify-App README](https://github.com/WXRIW/Lyricify-App)
- [Lyricify-Lyrics-Helper README](https://github.com/WXRIW/Lyricify-Lyrics-Helper)
- [Lyricify-Lyrics-Helper Apache-2.0 LICENSE](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/LICENSE)

## 3. 来源对比总表

符号说明：`✓` 官方/公开支持；`△` 需授权、地区或只能通过非官方方案；`—` 当前官方资料未提供；`?` 本轮无法从当前公开资料确认。

| 来源 | 官方公开 API / macOS | 认证、账号、审核 | 目录搜索 | 标题/多艺人/专辑/时长/封面/ISRC/平台 ID | 普通/逐行/逐字/翻译歌词 | 限额、地域、成本 | 缓存、发布和维护判断 | 本项目难度 | 分层 |
|---|---|---|---|---|---|---|---|---|---|
| Spotify Web API | ✓ REST；macOS 可用 | OAuth 2.0；桌面应使用 Authorization Code + PKCE；开发模式需 Premium owner、最多 5 个 allowlist 用户 | ✓ `/search` | ✓ 全部常用 Track 字段（多艺人数组、`duration_ms`、图片、`external_ids.isrc`、Spotify ID/URL） | 官方当前参考未找到公共歌词正文接口 | 配额模式、429；2026-02 搜索结果 limit 收紧；扩展配额需审核/组织条件 | 临时元数据/封面缓存受条款限制；桌面密钥管理和 Spotify 条款是发布风险；不要调用私有歌词接口 | 中高：OAuth、回调、Token/PKCE、配额与隐私 | 推荐后续接入 |
| Spotify Desktop Apple Events | ✓ 本机 Apple Events；非目录 API | macOS TCC “控制 Spotify”权限；无需 Web OAuth | —（只读当前歌曲） | ✓ 当前字典可读歌曲、艺人、专辑、时长、position、playing、artwork URL、Spotify ID/URI | — | 受本机 Spotify 运行状态、TCC 和版本字典影响 | 不应把本机快照当远程曲库；维持现有调度和插值 | 低（已有实现） | 立即保留为 CurrentTrackResolver |
| Local files | ✓ 文件系统，不依赖平台 | 用户自己授予目录访问；无账号 | △ 以文件名/标签/LRC 索引 | 取决于文件名和 LRC 元数据；封面/ISRC 通常没有 | ✓ 纯文本、LRC；格式可扩展，翻译/罗马音取决文件 | 无网络限额；用户自行负责版权 | 只读、用户导入最高优先级；不得自动复制/修改；最适合公开发布 | 低：已有目录规则和 LRC 解析 | 推荐立即接入 |
| LRCLIB | ✓ 公开 HTTP 服务（非平台官方） | 无 OAuth；服务可变 | ✓ `/api/search`；`/api/get` 精确匹配 | 有标题/艺人/专辑/时长/记录 ID；封面、ISRC 不稳定或不保证 | ✓ plain + synced；翻译/逐字不保证 | 免费公共服务；HTTP 4xx/5xx、地区/可用性变化；无稳定 SLA | 仓库 MIT 不等于数据库歌词可再分发；个人桌面可选，App Store/商业发布需另审 | 低中：已有实现；需健康状态、超时、重试和缓存政策 | 推荐立即接入（个人桌面） |
| Apple Music / MusicKit | ✓ 官方 MusicKit/Apple Music API；原生 macOS 友好 | Apple Developer Program、签名 developer token；个人库需 Music User Token、授权和 `NSAppleMusicUsageDescription` | ✓ `MusicCatalogSearchRequest` | ✓ Song title/artist(s)/album/artwork/duration/ISRC/Apple ID/URL；有 `hasLyrics` | 官方公开目录接口只确认 `hasLyrics`，未提供歌词正文、逐行或逐字读取接口 | storefront/地区；文档说明临时 429；固定公共额度未见 | 目录元数据可用；歌词正文和 Music.app 私有 TTML 不可当公共 API；需 entitlements/签名 | 中：token、storefront、授权、映射 | 推荐后续接入（目录元数据） |
| MusicBrainz + Cover Art Archive | ✓ 开放元数据/封面 API；macOS HTTP 可用 | 无 API key；需有意义 User-Agent；商业使用需看数据许可证/联系方案 | ✓ recording/release 搜索 | 标题/艺人/专辑/时长/MBID；封面通过 CAA；ISRC 关联不保证 | — | MusicBrainz 通常约 1 req/s/IP；地区无明显限制；CAA 也可能 503 | 核心数据 CC0；补充数据 CC BY-NC-SA 3.0，封面版权另计；只做 metadata resolver | 低中：查询、限速、匹配 | 推荐后续接入 |
| Musixmatch | ✓ 官方/商业 Lyrics API | API key、计划/商业授权；密钥不可嵌入桌面公开包 | ✓ matcher/track | ✓ title/artist/album/duration/ISRC/Spotify ID 等 | ✓ plain lyrics、翻译状态、subtitle 行时间轴、rich sync（按计划/区域） | 付费和计划额度；region restriction；需与供应商确认 | 这是最有希望的授权在线歌词来源，但存储/展示/再分发必须按合同；适合正式发布前接入 | 中：密钥代理/用户配置、版权字段、区域与配额 | 推荐后续接入（取得合同后） |
| 网易云音乐 | 未找到官方公开第三方 API/原生 macOS SDK | 非官方 endpoint 常需 Cookie/加密/反爬；无可接受公开授权 | △ 非官方搜索 | ✓ 非官方响应常有 title/artist/album/duration/id/artwork | ✓ 非官方常有 LRC、翻译，部分有逐字/罗马音 | 地域、登录、反爬和接口失效风险；无稳定配额 | `NeteaseCloudMusicApi` 无可识别许可证，旧提交/大量 Issue；不能作为核心或公开默认 | 中高：代理、加密、会话、合规 | 仅可选实验插件 |
| QQ Music | 官方腾讯连连 H5 音乐服务，但非通用 native macOS API | QQ Music 登录；H5 SDK 及平台审核/商务条款 | △ 官方 H5 `searchMusic`；native REST 未确认 | ✓ 官方 H5 文档含多艺人、专辑、时长、封面、SongId/SongMid | ✓ 官方 H5 `describeLyric`（授权场景）；公开 native lyric endpoint 不稳定 | 登录、地区、反滥用；非官方接口可能 1310；商业授权需确认 | `QQMusicApi` 为 GPL-3.0 Node 代理，依赖 referer/Cookie；不能直接放入 Swift 核心 | 高：H5/授权/会话或代理 | 仅可选实验插件/商务方案 |
| 酷狗音乐 | 官方 Open Platform 主要为 H5/移动 mini-player | appid/appkey/ticket、平台审核；无通用 macOS lyric API | △ 官方产品集成搜索；非官方 endpoint 可搜 | ✓ 非官方常有 song/hash/album/duration/artwork | ✓ 非官方常见 LRC/KRC，但无稳定公开授权 | 地域、证书、反爬、版权；官方 SDK/产品条款需商务确认 | `KuGouMusicApi` 虽 MIT，但 README 明确 study-only/noncommercial、24h 清理；不适合正式发布 | 高：hash、签名/代理、格式解析 | 仅可选实验插件 |
| Genius | 官方偏搜索/歌曲/艺人 metadata | API token/账号；歌词文本不在公开授权接口中确认 | ✓ metadata search | ✓ metadata/URL；封面和时长取决资源 | — 官方歌词正文未确认；抓网页不建议 | 条款和网页结构变化 | 只做 metadata enrichment；禁止把 scraper 当歌词 Provider | 低中 | 不建议作为歌词来源 |
| Deezer | 有开发者门户，但当前文档入口需登录 | App ID/token/条款待确认 | △ 目录能力可能可用 | 元数据可能丰富；本轮未确认完整公开字段/额度 | — 未确认公共歌词正文 | 登录、区域和条款不确定 | 暂不纳入核心；需要帐户和条款复核 | 中 | 可选后续 metadata |

## 4. 各来源的详细审计

### 4.1 Spotify Web API

官方 [Search for an Item](https://developer.spotify.com/documentation/web-api/reference/search) 支持 `album`、`artist`、`track` 等类型与 `isrc`、年份、流派等过滤。Track 结果天然适合 `TrackMetadata`：标题、艺人数组、专辑、`duration_ms`、封面图片、Spotify `id`/URL、`external_ids.isrc`。

官方 [Authorization](https://developer.spotify.com/documentation/web-api/concepts/authorization) 对桌面/移动应用推荐 Authorization Code with PKCE；client secret 不能安全放进公开 macOS 二进制。开发模式和用户数量/ Premium 条件、429 行为和 2026 年 quota 调整应以 [Quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)、[Rate limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits)、[2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide) 和 [2026-07-23 quota update](https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates) 为准。元数据、封面和本地缓存边界还要逐条核对 [Spotify Developer Terms](https://developer.spotify.com/terms) 与 [Developer Policy](https://developer.spotify.com/policy)，不能只看 SDK 能否请求成功。

本轮没有在项目中创建 Spotify Web Client 或 OAuth 应用；这不是缺陷，而是遵守“先调研、等待确认”。目前官方 Web API 参考没有给出公共歌词正文读取端点，不能把 Dynamic Lyrics、Spotify 客户端或私有接口中的歌词当成官方能力。

**建议**：后续作为 `SpotifyCatalogSearchProvider` 接入；保留本机 Apple Events 作为实时播放器识别，不让 Web API 替代桌面 provider。

### 4.2 LRCLIB

本轮对 `https://lrclib.net` 做了最小只读验证：`/api/search?q=Bohemian%20Rhapsody` 返回 HTTP 200 和记录元数据、`plainLyrics`、`syncedLyrics`；`/api/get` 精确请求也返回 plain/synced。错误行为可观察：精确 metadata miss 为 404，首轮异常查询为 400，故客户端必须区分 no-match、bad-request、网络失败与服务端错误。

服务端仓库 [tranxuanthang/lrclib](https://github.com/tranxuanthang/lrclib) 是 MIT，但 MIT 只覆盖仓库代码；托管歌词文本、封面和版权声明不因此自动授予本地保存或再分发权。GitHub API 在 2026-07-27 显示最近 push 为 2026-06-24、62 个 open issues，说明仍在维护但没有商业 SLA。

**建议**：本地文件之后作为个人桌面默认在线来源；每个请求有限超时，网络恢复最多自动重试一次，保留手动重搜；未经用户开启不持久化歌词，Release 不依赖源码目录；公开发布前重新做数据权利评审。

### 4.3 网易云音乐

没有找到官方开放给第三方原生 macOS 应用的稳定歌曲/歌词 API。只读请求验证了常见网页接口在当前时点可返回 Queen 的搜索元数据与 LRC/翻译，但这些是未文档化的路径，依赖反爬策略、Cookie、`weapi/eapi` 加密和地区/登录状态。

公开代理 [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) 的仓库未发现可识别的 LICENSE，GitHub API 在 2026-07-27 显示最近 push 为 2024-02-28、147 个 open issues。不能把该代理代码或接口当作可合法再分发的 Swift Provider。

**建议**：若未来只为个人本地实验，可做独立插件进程/本地代理，默认关闭、无持久化、无内置 Cookie；不要放进核心 App 或 App Store 构建。

### 4.4 QQ 音乐

腾讯云 [音乐服务](https://cloud.tencent.com/document/product/1081/67456) 文档描述的是 Tencent 连连 H5 panel SDK：`searchMusic`、`describeSongInfoBatch`、`describeLyric` 等能力存在，但除登录/匿名能力外通常需要 QQ Music 授权；这不是一个已证明可直接发给 native macOS Swift 客户端的公共 REST 合同。

本轮对常见搜索路径得到 HTTP 200 元数据；对应 lyric 请求得到 JSON `retcode:-1310`，说明会话/反滥用条件不能省略。公开 Node 代理 [jsososo/QQMusicApi](https://github.com/jsososo/QQMusicApi) 是 GPL-3.0、依赖 referer/Cookie 的非官方桥接，不能作为本项目内置实现。

**建议**：优先等待腾讯的正式 native/商务授权；如果做实验插件，进程边界隔离代理、用户自行登录、不保存 Cookie，所有歌词结果只在内存中短暂使用。

### 4.5 酷狗音乐

酷狗 [Open Platform](https://open.kugou.com/) 的公开能力集中在 H5/mini-player，文档要求 appid/appkey/ticket 和平台审核；本轮没有确认一个面向原生 macOS 的通用歌词检索 API。

公开 [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) 虽然仓库许可证显示 MIT，但 README 明确写出 study-only/non-commercial 和 24 小时清理版权数据要求；其实现调用未公开接口，通常涉及 hash、签名、LRC/KRC 和反爬。一次只读移动搜索请求返回元数据，歌词 detail 请求没有稳定结果。

**建议**：不进入核心 Provider；只有在取得酷狗许可或用户明确启用本地实验时才考虑独立 adapter。

### 4.6 Apple Music / MusicKit

官方 [MusicCatalogSearchRequest](https://developer.apple.com/documentation/musickit/musiccatalogsearchrequest) 支持按关键词搜索歌曲、专辑、艺人等。官方 [Song](https://developer.apple.com/documentation/musickit/song) 字段包含标题、艺人集合、专辑、封面、时长、ISRC、Apple Music ID/URL 和 `hasLyrics`。

使用需要 [developer token](https://developer.apple.com/documentation/applemusicapi/generating-developer-tokens)，原生 Apple 平台可使用 MusicKit 的自动 token 生成；访问个人库还需要 Music User Token、授权及 `NSAppleMusicUsageDescription`。官方文档只把 `hasLyrics` 暴露为“是否有歌词”，没有在当前公共 Apple Music API 参考中找到歌词正文、逐行或逐字歌词读取 API。因此不能读取 Music.app 私有 TTML 或猜测私有接口。

**建议**：作为可选的 `AppleMusicCatalogSearchProvider`，只返回目录元数据和歌词可用性提示；不作为本阶段歌词来源。需要处理 storefront、429、开发者签名和未订阅用户的差异。

### 4.7 MusicBrainz 与 Cover Art Archive

官方 [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API) 支持 recording/release/artist 搜索，本轮带有意义的 User-Agent 的查询返回 HTTP 200。核心数据采用 CC0；补充数据可能适用 CC BY-NC-SA 3.0，且封面来自 [Cover Art Archive API](https://musicbrainz.org/doc/Cover_Art_Archive/API) 时仍有图片权利问题。MusicBrainz 要求客户端遵守约 1 req/s/IP 的速率约束和 User-Agent 规则，商业服务需按其数据许可联系。

**建议**：后续作为“元数据纠错/ISRC 补全” provider，不返回歌词；请求带限速、缓存和 attribution 配置。

### 4.8 Musixmatch

官方 [Lyrics API 文档](https://www.postman.com/musixmatch-dev/musixmatch-apis/documentation/pqm8o6w/lyrics-api) 明确每次请求需要 `apikey`，并展示 matcher 按标题/艺人/ISRC 匹配、track 元数据、普通歌词、subtitle 时间轴、翻译状态、`has_richsync` 与 region restriction。它不是免费匿名公共接口，计划、调用额度、存储和再分发必须通过商务合同确认。

**建议**：如果目标是可公开发布的歌词产品，这是最值得后续评估的在线来源。桌面端不应内置供应商密钥，建议服务端 token broker 或用户自带 key，Provider 只缓存合同允许的短期数据，并在 UI 传递版权/区域限制。

### 4.9 Genius 和 Deezer

Genius 适合补充歌曲/艺人搜索 metadata 和 canonical URL，但本轮公开文档没有确认一个可供第三方合法读取原始歌词文本的接口；网页抓取或 scraper 不纳入方案。Deezer 的开发者入口当前重定向登录，本轮无法确认完整的公开 native macOS 搜索合同、歌词正文、额度和存储条款，因此都不进入当前实现。

## 5. 当前仓库架构审计

### 已有文件和职责

- `SpotifyLyrics/Search/SongSearchModels.swift`：`SongSearchQuery`、`SongSearchResult`、`SongSearchState`、搜索评分。`SongSearchResult` 同时含 `Track` 和可选 `LyricsDocument`，这是当前最大职责混合点。
- `SpotifyLyrics/Search/SongSearchProvider.swift`：统一 `search(query:)` 协议，但协议名和返回值默认把歌曲搜索与歌词结果绑定。
- `SpotifyLyrics/Search/LocalSearchProvider.swift`：只读扫描用户目录、应用目录和 Debug `Lyrics/` 的 `.lrc`，实际是“本地歌词搜索”，不是完整曲库搜索。
- `SpotifyLyrics/Search/SpotifyCurrentTrackProvider.swift`：包装 `PlaybackProvider`，只从已播放快照生成“当前歌曲结果”；不是自由文本曲库 provider。
- `SpotifyLyrics/Search/LRCLIBProvider.swift`：把 LRCLIB 的歌曲搜索 JSON 与歌词正文解析合在同一个搜索结果里。
- `SpotifyLyrics/Search/SongSearchManager.swift`：Local → Spotify current → LRCLIB 顺序调度、取消旧任务、generation 防乱序、结果合并。
- `SpotifyLyrics/Lyrics/LyricsModels.swift`：`LyricsProvider`、`LyricsCandidate`、`LyricsDocument`、typed failure、纯文本/时间轴状态。
- `SpotifyLyrics/Lyrics/LocalLyricsProvider.swift` 和 `LRCLIBLyricsProvider.swift`：对已知 `TrackIdentity` 解析/匹配歌词版本。
- `SpotifyLyrics/Lyrics/TrackIdentity.swift`、`LyricsMatcher.swift`：严格 identity 优先级和匹配评分。
- `SpotifyLyrics/Services/LyricsSessionController.swift`、`PlaybackState.swift`：当前 identity/revision、取消、候选和播放状态的业务会话。

### 审计结论

现在的实现已经有较好的歌词会话安全边界，但 `SongSearchResult` 与 `SongSearchManager` 仍混合：

1. **目录搜索结果**（找到一个歌曲候选）。
2. **当前播放识别**（本机 Spotify 快照）。
3. **歌词版本结果**（LRC/plain/synced 文档）。

`SongSearchResult.searchMergeKey` 为 UI 去重而忽略 album/duration，这是可以保留的显示策略，但绝不能用来替代 `TrackIdentity`。任何歌词请求、背景请求和播放 seek 都必须继续携带严格 identity 和 generation。

## 6. 建议的统一数据模型（下一轮实现时使用）

```swift
struct TrackSearchQuery: Equatable, Sendable {
    var text: String
    var title: String?
    var artists: [String]
    var album: String?
    var duration: TimeInterval?
    var isrc: String?
    var externalIDs: [String: String]
    var locale: String?
}

struct TrackMetadata: Equatable, Sendable {
    var title: String
    var artists: [String]
    var album: String?
    var duration: TimeInterval?
    var releaseDate: Date?
}

struct TrackSearchResult: Identifiable, Equatable, Sendable {
    var id: String                 // provider-scoped ID
    var provider: String
    var metadata: TrackMetadata
    var artworkURL: URL?
    var isrc: String?
    var platformURL: URL?
    var identityHints: [TrackIdentityHint]
    var confidence: Double
    var availability: Availability
}

struct LyricsSearchQuery: Sendable {
    var identity: TrackIdentity
    var metadata: TrackMetadata
    var locale: String?
}

struct LyricsCandidate: Identifiable, Equatable, Sendable {
    var id: String                 // provider-scoped lyric version ID
    var provider: String
    var identity: TrackIdentity
    var lines: [LyricLine]
    var timing: LyricsTiming       // none / line / word
    var translation: LyricsLayer?
    var romanization: LyricsLayer?
    var confidence: Double
    var rights: LyricsRightsMetadata
}
```

模型规则：

- `TrackIdentity` 仍按 Spotify Track ID/URI → ISRC → 标准化标题、艺人、专辑、四舍五入时长回退；平台 ID 是证据，不自动跨平台等同。
- Track search 只返回元数据，不携带歌词正文。
- Lyrics search 只针对一个已确认 identity，结果必须携带 identity、provider、revision/generation。
- 普通纯文本的 `timing = none`，逐行时间轴为 `line`，逐字/富同步为 `word`；UI 不为 plain text 伪造高亮。
- `rights` 至少记录来源、是否允许缓存、过期时间、区域限制和展示版权行；不把这些信息丢在字符串里。

## 7. 失败、限流和接口失效隔离

每个 Provider 都应返回可分类的状态，而不是把所有错误合成“无歌词”：

```text
disabled
notConfigured
unauthorized
networkUnavailable
timedOut
rateLimited(retryAfter)
serverError(statusCode)
parseFailure
noMatch
success
```

`TrackSearchManager` 和 `LyricsSearchManager` 的行为：

1. Provider 之间并行或按策略串行，但一个 Provider 失败不能取消其他 Provider；最终结果允许“部分成功 + diagnostics”。
2. 每个 Provider 独立超时、指数退避和短时 circuit breaker；429 使用 `Retry-After` 或 provider policy，不做无限重试。
3. 新 query/新 TrackIdentity 立即取消旧 Task；返回时二次核对 identity + generation，旧歌词、旧封面和旧候选不能覆盖新歌曲。
4. 失败、noMatch、noLyrics、candidates 分开显示；网络恢复只允许当前 identity 有限自动重试，手动重搜不改变播放位置。
5. 本地 provider 永远不依赖网络；LRCLIB/Musixmatch/实验插件的缓存策略按来源单独配置，默认不把歌词写入用户目录。
6. 不记录歌词正文、Cookie、OAuth refresh token 或平台密钥到日志；诊断只保存 provider、错误类别、HTTP 状态、耗时和 request ID。
7. Release 构建关闭 Debug 源码 `Lyrics/` 路径和实验插件；未配置授权时 provider 是 `notConfigured`，不是伪造的空搜索。

## 8. 推荐接入分层

### 推荐立即接入

1. **LocalTrackSearchProvider / LocalLyricsProvider**：用户主动导入的 `.lrc`/纯文本，最高优先级、只读、无版权平台依赖。
2. **现有 Spotify Desktop CurrentTrackResolver**：继续提供实时歌曲、封面、播放状态和 seek，不冒充目录搜索。
3. **LRCLIBLyricsProvider**：个人桌面 opt-in 的同步/纯文本补充；在 UI 明示来源和失败状态。

### 推荐后续接入

1. **SpotifyCatalogSearchProvider**：用户确认要 OAuth/PKCE、开发者 Client ID、Premium/allowlist 与配额策略之后再做。
2. **MusixmatchLyricsProvider**：取得商业授权、API key 代理、区域/版权/缓存合同后再做；这是正式发布优先级最高的在线歌词来源。
3. **AppleMusicCatalogSearchProvider**：仅目录元数据/`hasLyrics`；需 Apple Developer/MusicKit 配置和 storefront 处理。
4. **MusicBrainzMetadataProvider + Cover Art**：用于 ISRC/元数据纠错和封面补全，遵守速率和许可。

### 只能作为可选实验插件

- 网易云、QQ 音乐、酷狗的非官方接口/本地代理。插件默认关闭、仅 Debug 或用户明确启用；不放入核心 App Store 构建，不内置 Cookie/签名密钥，不自动缓存或上传数据。
- Deezer metadata adapter：只有在重新确认开发者账号、条款、额度和公开字段后才考虑。

### 不建议接入

- Genius 网页抓取歌词、任何 scraper 或破解签名。
- Spotify/Apple Music/Dynamic Lyrics 的私有歌词接口、私有 token、应用内 Cookie 或反编译实现。
- 公共第三方代理中嵌入的账号、Cookie、密钥，以及未经许可的 lyric database 镜像。

## 9. 未来修改文件计划（本轮不执行）

第一步只做模型和适配层，不改现有主窗口：

```text
SpotifyLyrics/Search/TrackSearchModels.swift
SpotifyLyrics/Search/TrackSearchProvider.swift
SpotifyLyrics/Search/TrackSearchManager.swift
SpotifyLyrics/Search/CurrentTrackResolver.swift
SpotifyLyrics/Lyrics/LyricsSearchManager.swift
SpotifyLyrics/Lyrics/LyricsProviderHealth.swift
SpotifyLyrics/Lyrics/LyricsRightsMetadata.swift
Tests/search_models_contract.swift
Tests/provider_failure_contract.swift
```

随后再按来源一次只接入一个：

1. 把现有 `SongSearchResult` 迁移为 metadata-only `TrackSearchResult`，保留兼容层，确保当前 UI 不回归。
2. 把 `SpotifyCurrentTrackProvider` 改为 `CurrentTrackResolver` 适配器。
3. 将 `LocalSearchProvider` 与 `LocalLyricsProvider` 共用只读本地索引，避免重复扫描和 identity 漂移。
4. 将 `LRCLIBProvider` 拆为目录候选适配和 `LRCLIBLyricsProvider`，默认仍只在歌词管理器中启用。
5. 通过 fixtures、取消/乱序、429/超时/解析失败合同测试后，才实现 Spotify OAuth/PKCE 目录搜索。
6. 取得合同后再实现 Musixmatch；Apple Music/MusicBrainz 作为独立 metadata provider；中文平台最后才做实验插件。

## 10. 从低风险到高风险的开发顺序与验收

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| A | 仅新增统一模型/协议和兼容适配 | 当前 Spotify 实时播放、歌词 identity、切歌和 UI 全部无回归；无网络调用变化 |
| B | 本地索引重构 | 三个本地目录只读；用户文件字节不变；Release 不依赖源码 `Lyrics/` |
| C | LRCLIB 隔离 | 200/plain/synced、404、400、超时、网络断开、429 fixture；有限自动重试；不显示旧歌 |
| D | MusicBrainz/CAA metadata | 1 req/s 限速、User-Agent、CC0/补充许可 metadata；无歌词写入 |
| E | Spotify Web OAuth/PKCE | 正常签名 Debug 完成授权、回调、token 刷新、撤销；429/配额/无 Premium 清晰提示；桌面不含 secret |
| F | Musixmatch 合同 Provider | 合同字段、版权/地区限制、缓存 TTL、密钥代理和真实歌曲验证；未授权时默认 disabled |
| G | Apple Music catalog | developer token、storefront、`NSAppleMusicUsageDescription`、未订阅/无权限状态；只显示 metadata/hasLyrics |
| H | 中文实验插件 | 独立进程/feature flag、无默认启用、无 Cookie/密钥持久化；接口失效不影响核心 App |

每个阶段都要执行正常签名 Xcode 构建、合同测试和至少一轮真实运行；没有真实运行结果只能写“未验证”。

## 11. 最终建议与待确认项

请先确认以下组合，再开始修改 Swift：

1. 是否接受“Local + LRCLIB（个人桌面 opt-in）”作为下一小阶段？
2. 是否准备申请 Spotify Developer Client ID 并接受 OAuth/PKCE 与 Premium/allowlist 约束？
3. 是否有 Musixmatch 或其他授权歌词供应商的预算/合同目标？若没有，公开发布只能把 LRCLIB/中文实验接口作为关闭状态，不应默认宣传为正式歌词服务。
4. 中文平台是否只需要未来的本地实验插件，而不是核心/Release Provider？

在收到确认前，本轮不修改 `SpotifyLyrics/*.swift`，不新增 Provider 实现，也不提交业务 commit。
