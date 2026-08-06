# 参考项目歌词源与歌词能力审计

审计日期：2026-07-30
SpotifyLyrics 基线：`63b555d841fd7f4fe2c6d680d7e30a94d410d519`
分支：`ui-redesign-phase-1`

> 本报告只做歌词来源、搜索机制、歌词格式、播放器接入和数据处理的技术审计。完全不把参考项目的 UI、布局、设置方式、视觉风格或交互设计作为研究对象，也不复制其代码、资源或私有接口。报告中的授权判断是工程风险筛查，不构成法律意见；真正接入前仍需对目标服务的最新条款、授权方式和地域限制做单独审查。

## 0. 结论摘要

1. 四个路径均已确认存在，但它们不是同一种证据：LyricsX 和 TaskbarLyrics 是可阅读的开源工程；Lyricify-App-main 是一个缺少实际实现源码的文档/资源快照；Dynamic Lyrics.app 是闭源成品，只能使用公开页面和黑盒可观察行为。
2. LyricsX、TaskbarLyrics、Lyricify 的歌词源高度重叠：本地歌词、LRCLIB、网易云、QQ 音乐、酷狗是主要交集。SpotifyLyrics 当前已经拥有 Local、SQLite、LRCLIB、网易云实验源和 QQ 实验源，因此“再接一个同样的来源”不会自动提高冷门日语覆盖。
3. 真正有新增技术价值的候选主要是：
   - Musixmatch：有逐行/逐字时间信息和翻译潜力，但参考实现依赖浏览器 `usertoken`，不是稳定、公开、适合直接复制的应用接口；
   - Apple Music：可能提供受授权控制的歌词/时间信息，但本地参考工程没有足够证据证明可通过合法、稳定的公开 API 直接取得目标歌词；
   - 酷狗：KRC/音频 hash/逐字时间信息有价值，但接口、解密和服务条款风险较高。
4. Spotify 私有歌词接口、Musixmatch 浏览器 token、网易云/QQ/酷狗未公开接口都不应因为“能请求”就直接作为产品 Provider。它们需要先完成授权和维护成本评估。
5. 如果必须只选一个下一步实验，推荐“**正式授权/合作前提下的 Musixmatch 能力验证**”，仅验证日语冷门歌曲覆盖、版本身份字段、逐字/翻译能力；不推荐抓取 `usertoken`。如果无法取得正式授权，则本阶段不应实现任何新的在线 Provider，优先继续使用现有来源和本地导入能力。

## 1. 审计范围、路径与证据等级

### 1.1 实际路径

| 对象 | 绝对路径 | 结果 | 可审计内容 |
|---|---|---|---|
| LyricsX | `/Users/apple/backup/sptifylyrics/LyricsX-master` | FOUND | Swift 应用源码、Package 配置、README、发布说明 |
| TaskbarLyrics | `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main` | FOUND | C# Core/App 源码、测试、技术文档 |
| Lyricify | `/Users/apple/backup/sptifylyrics/Lyricify-App-main` | FOUND | README、Lyricify 3 文档、XAML/图片/本地化资源；未发现实际 C# 工程源码 |
| Dynamic Lyrics | `/Applications/Dynamic Lyrics.app` | FOUND | 公开网站/App Store 信息和黑盒行为；不审计二进制内部实现 |

三个源码目录没有独立的嵌套 `.git`，它们在当前工作区中表现为参考目录，而不是可由各自 Git 提交验证的独立 checkout。故报告以实际文件内容、文件名、Package.swift 依赖声明和公开上游资料交叉核对，不把当前主仓库的 Git 提交误认为参考项目提交。

### 1.2 证据等级

- **A：本地实现证据**：在给定绝对路径中找到接口、Provider、解析器、注册和调用路径。
- **B：本地文档/发布说明证据**：README、技术文档、release note 提及，但实现不在给定目录或未能证明仍在主路径。
- **C：公开项目资料证据**：上游公开 README/仓库说明，用于解释外部依赖或独立 helper 的能力。
- **D：黑盒/公开产品证据**：只确认用户可观察的功能，不推断内部请求或实现。
- **未验证**：不能从当前路径或允许的公开证据推出当前可用性。

### 1.3 本轮运行边界

- LyricsX：未在本轮重新构建；其歌词 Provider 主要来自远程 Swift Package，给定目录不是完整依赖源码。报告不把“源码存在”写成“当前线上接口可用”。
- TaskbarLyrics：源码为 Windows/.NET 工程，本轮没有把它当作 macOS 应用运行；不把构建可行性与服务可用性混为一谈。
- Lyricify-App-main：给定目录没有可供构建的主应用 Provider 实现，本轮只读取文档和资源索引。
- Dynamic Lyrics：只采用公开页面和此前允许范围内的黑盒观察；没有反编译、提取资源、检查网络请求、还原私有接口或读取内部实现。

## 2. 许可证审计

### 2.1 总表

| 对象 | 根目录许可证 | 子模块/依赖情况 | 阅读 | 修改/移植 | 再分发 | 结论 |
|---|---|---|---|---|---|---|
| LyricsX | `LyricsX-master/LICENSE`：MPL 2.0，并标注 Incompatible With Secondary Licenses | `LyricsXPackage/Package.swift` 通过远程依赖引入 LyricsKit、MusicPlayer、FrameworkToolbox；这些依赖的许可证不由 LyricsX 根许可证代替 | 可以 | 可以，但修改文件须遵守 MPL 文件级义务 | 可以，需保留通知、许可证和源代码提供义务；要逐项审查依赖 | **可研究；不可直接复制进 SpotifyLyrics，除非先完成 MPL/依赖合规设计** |
| TaskbarLyrics | `TaskbarLyrics-main/LICENSE`：MIT | NuGet 依赖和 `Lyricify.Lyrics.Helper` 有独立许可证；根目录 MIT 不覆盖依赖 | 可以 | 可以 | 可以，保留 MIT 版权和许可文本 | **代码许可证相对宽松，但服务接口和歌词内容授权仍是独立风险** |
| Lyricify-App-main | 未发现根目录 `LICENSE`/`COPYING`/`NOTICE` | README 明确把歌词处理库指向独立的 `WXRIW/Lyricify-Lyrics-Helper`；该 helper 是另一个 Apache-2.0 项目，不能替代主仓库许可证 | 可以阅读和研究 | 未经作者授权不得移植主仓库实现 | 不应再分发主仓库源码、文档或资源 | **主仓库按无明确许可证处理：只研究概念；不复制** |
| Dynamic Lyrics.app | 闭源 App Store 成品；本地包没有可用于移植的开源许可证 | 以 App Store、官网和产品条款为准 | 仅限公开信息和黑盒观察 | 不适用 | 不适用 | **不可反编译、提取资源、还原接口或复制实现** |

### 2.2 许可证细节

#### LyricsX

`LyricsX-master/LICENSE` 是 MPL 2.0，且 Exhibit B 声明不兼容 Secondary Licenses。MPL 允许阅读、修改和分发，但对包含受保护代码的源文件有文件级公开修改义务，并要求保留版权/许可证/通知。`LyricsXPackage/Package.swift` 不是把所有依赖变成 LyricsX 许可证；LyricsKit、MusicPlayer、FrameworkToolbox、Swift Syntax 等必须按各自上游许可证分别审查。

#### TaskbarLyrics

根目录是 MIT。它允许使用、修改、合并、发布、再许可和销售，但必须保留版权和许可文本。`F23.StringSimilarity`、EF Core SQLite、OpenCC、`Lyricify.Lyrics.Helper` 等第三方组件的许可证仍要单独记录；尤其不能用 TaskbarLyrics 的 MIT 结论覆盖歌词平台服务或其返回内容的授权问题。

#### Lyricify

给定 `Lyricify-App-main` 未发现主仓库许可证。README 中关于 `Lyricify-Lyrics-Helper` 的 Apache-2.0 说明只适用于独立 helper，不适用于主应用、文档、图片、资源或未授权的服务端代码。README 还提到部分原创创意采用 CC BY-SA 4.0；那是创意/内容声明，不构成可以复制主仓库实现的许可证，本项目也不把其 UI 作为审计对象。

#### Dynamic Lyrics

只使用 [官方 FAQ](https://dynamiclyrics.app/faq)、[官方隐私说明](https://dynamiclyrics.app/privacy) 和 [App Store 页面](https://apps.apple.com/gb/app/dynamic-lyrics/id6476125287?platform=mac) 作为公开证据。没有把 App Store 成品当作可移植代码，也没有从包内推导歌词接口或服务端实现。

## 3. 四个对象的完整歌词来源表

状态约定：**主路径**=在当前可见调用链中创建/注册；**旧代码**=文件或发布说明存在，但不能证明当前默认运行；**只有声明**=文档提到，给定路径没有实现；**废弃**=项目资料明确停止/失效；**未知**=闭源或证据不足。

### 3.1 去重后的来源总表

| 来源 | 所属项目/证据 | 状态 | 搜索与取得 | 身份字段 | 格式能力 | 认证/请求风险 | 与 SpotifyLyrics 重合 |
|---|---|---|---|---|---|---|---|
| 本地歌词文件/音频内嵌 | LyricsX、TaskbarLyrics；Lyricify 文档也支持导入 | 主路径/本地 | 按当前歌曲、目录、文件关联或音频 metadata 查找；不访问网络 | 标题、艺人、专辑、时长取决于文件和 metadata；通常无 Spotify ID/ISRC | LRC；LyricsX 的 LRCX；Taskbar 还解析 QRC/KRC 和部分内嵌字段；可含纯文本、逐行、逐词 | 无网络认证；文件内容授权由用户负责 | **高度重合**，SpotifyLyrics 已有只读本地索引和导入/编辑能力；参考价值在格式兼容和扫描策略 |
| LRCLIB | LyricsX、TaskbarLyrics、SpotifyLyrics | 主路径 | `/api/search` 支持 query 或 track/artist 参数；按结果 ID 取歌词 | 主要是平台 ID、标题、艺人、专辑、时长；通常没有可靠 ISRC/Spotify ID | 纯文本和逐行同步（不同客户端解析范围不同） | 通常无账号/token；公共服务限流、接口变更和可用性风险 | **完全重合**；无新增来源价值 |
| 网易云音乐 | LyricsX、TaskbarLyrics、Lyricify helper；SpotifyLyrics | 主路径/实验源 | 搜索标题/艺人；可在播放器已有网易 ID 时直接取 | 网易 song ID、标题、首艺人、专辑、时长、封面；通常不提供 Spotify ID/ISRC | LRC；TLYRIC 翻译；KLYRIC/YRC 可提供词/音节时间（取决于歌曲） | 搜索接口、eAPI、加密参数、Cookie/CSRF/接口状态；未公开接口和反爬风险 | **完全重合**；重点只能用于比较解析和版本证据，不应重复接入 |
| QQ 音乐 | LyricsX、TaskbarLyrics、Lyricify helper；SpotifyLyrics | 主路径/实验源 | smartbox 搜索和桌面搜索接口；可用 QQ song ID/MID 直接取 | QQ song ID、MID、标题、歌手、专辑、时长、封面；ISRC/Spotify ID 通常不在歌词接口中 | LRC；QRC 逐字/音节时间；`ts` 翻译；部分歌曲存在官方读音辅助 | 未公开接口、Referer/请求参数、QRC/DES 解码；通常不要求用户登录，但稳定性与条款风险高 | **完全重合**；当前水曜日の約束 32 行正确命中证明它已有实际价值 |
| 酷狗 | LyricsX、TaskbarLyrics、Lyricify helper | 主路径/实验源（参考项目） | 先按关键词搜索，再用 hash/albumAudioID 查询歌词候选；下载 KRC | hash、albumAudioID、歌词 ID/accesskey、标题、歌手、专辑、时长、封面；hash 不是 Spotify/ISRC 身份证明 | KRC 逐词/音节时间；可有 `[language:...]` 翻译 | 未公开搜索/歌词接口、hash 绑定、KRC 解密；部分请求无登录但维护和授权风险高 | **当前 SpotifyLyrics 未把它作为现有主 Provider**；有潜在新增格式/覆盖，但风险明显高 |
| Musixmatch | LyricsX 可选 Provider；Lyricify helper 公开能力；Taskbar 间接依赖 helper | 可运行代码证据，但依赖浏览器 token；非正式公开 API | `track.search` 按标题/艺人，`macro.subtitles.get` 取字幕；可带 Spotify track id、专辑、时长等查询字段 | Musixmatch track ID、标题、艺人、专辑、时长；可尝试 Spotify ID 关联；ISRC 能力未在给定实现中稳定证明 | LRC/逐行；richsync/逐词时间；翻译接口/众包翻译能力因实现而异 | `usertoken`，通常通过浏览器会话取得；token 获取、服务条款、封禁和隐私风险高 | **新增价值主要是逐字与翻译**；不是低风险 Provider |
| Spotify 官方/私有歌词 | LyricsKit 远程依赖中的 Provider 证据 | 旧/私有路径 | 官方 Web API 搜索；另有 `spclient.wg.spotify.com` 私有歌词接口 | Spotify ID、标题、艺人、专辑、时长；官方搜索可有封面/市场信息；私有歌词接口依赖访问 token | 私有歌词响应可有同步行信息；不能据此保证逐字/翻译 | 官方 API 需 OAuth；私有接口依赖内部 token/header，不应复用或绕过 | SpotifyLyrics 已有 Desktop/Web 识别和目录 OAuth；私有歌词接口**不适合新增**，官方可授权能力需另行评估 |
| Apple Music | LyricsX 当前公开上游有相关历史/主线资料；本地 Package.swift 只声明远程 LyricsKit，未找到对应本地实现；Dynamic 公开支持 Apple Music | 旧代码/公开功能，当前路径未验证 | 合法路线应走 MusicKit/Apple Developer 授权；浏览器 cookie/private endpoint 不纳入方案 | Apple Music song/catalog ID、专辑、艺人、时长、封面；ISRC/歌词关系要以正式 API 权限为准 | 可能有歌词、翻译或 TTML/逐词信息；本地给定路径不足以确认实际返回 | Developer token/user authorization/地区和订阅限制；网页 token 是私有路线，不采用 | **潜在新增**，但授权、平台能力和覆盖必须先做官方可行性验证 |
| Soda | Lyricify helper 的公开搜索器列表 | 只有声明/外部 helper 能力 | helper README 列为可搜索来源；给定 Lyricify 主目录没有 Provider 实现或运行证据 | 字段和 ID 需要逐项实测；未从本地对象中确认 | 未确认 | 接口、授权、维护状态未确认 | 当前无重合证据；但证据不足，不推荐直接接入 |
| Lyricify/WXRIW 服务端 | Lyricify 文档/本地化字符串中有服务或人工上报提示 | 只有声明/闭源服务 | 文档提到通过 QQ songmid、网易 id 或服务端管理歌词；给定主目录没有可核对协议 | 平台 ID 可能是核心映射；字段和服务稳定性未知 | 可能有行级/增强歌词；不可从当前路径确认 | 服务端、账号、条款和 API 未公开 | 无法作为可维护 Provider 评估；不复制、不依赖 |
| TTPod、Gecimi、Syair、Xiami、ViewLyrics 等 | LyricsKit 公共来源列表中的历史条目 | 废弃/失效历史 | 公开列表标记停用或不可用；本地没有主路径实现 | 不适用 | 不适用 | 域名/服务已停或接口不可用 | 不推荐 |
| Dynamic Lyrics 自有/第三方来源 | 官网、App Store、黑盒运行 | 未知、不可审计 | 只观察到它连接受支持的音乐服务并显示歌词；没有推断内部来源 | 黑盒可观察到当前歌曲 metadata；内部映射未知 | 公开资料提到翻译、word-by-word、TTML 本地能力；具体网络格式未知 | 以官方授权、服务连接和产品条款为准；无私有接口审计 | 不可作为技术 Provider 参考；只能记录公开能力边界 |

### 3.2 LyricsX 的来源与调用链

本地应用层的关键路径是：

```text
AppController
  → updateLyricsManager()
  → LyricsProviders.Group
  → lyricsManager.lyrics(for: request)
  → 用户/当前歌曲选择结果
```

关键文件：

- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/Component/AppController.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/Search/SearchLyricsViewController.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/Preferences/PreferenceSourceViewController.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/View/KaraokeLabel.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/Utility/Extension.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsXPackage/Package.swift`

`AppController` 默认创建不需要认证的 Provider Group；如果 UserDefaults 中存在 Musixmatch usertoken，再追加 Musixmatch Provider。搜索页面以 `AsyncStream`/异步任务消费候选，用户可选择歌词。来源优先级和 offset 通过设置/歌词 metadata 调整。Provider 的具体 HTTP 实现不在本地工程，而在 `Package.swift` 声明的远程 LyricsKit 依赖中；给定目录没有提交 `Package.resolved`，因此不能把“README 支持”误判为当前本地目录已经包含全部可构建实现。

LyricsX 的 `KaraokeLabel.swift` 展示了一个有用但不应直接复制的格式能力：CoreText tokenizer 对日文词段建立范围，利用 `CTRubyAnnotation` 放置 furigana，并额外绘制 romaji；歌词行还可按字符/词时间显示进度。该能力依赖歌词数据已有的注音或 annotation，不等于任意汉字都能可靠自动生成读音。

### 3.3 TaskbarLyrics 的来源与调用链

TaskbarLyrics 的本地可见调用链是：

```text
SMTC track/session
  → LyricSyncService
  → ILyricProviderRegistry
  → LocalLyricProvider / GenericSmtcLyricProvider / LyricifyLyricProvider
  → LyricMatcher / routing policy
  → line/syllable parser and cache
```

关键文件：

- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.App/AppCompositionRoot.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Services.LyricProviderRegistry.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Services.LocalLyricProvider.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Services.LyricifyLyricProvider.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Services.GenericSmtcLyricProvider.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Utilities/LyricMatcher.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.App/AppSettings.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/docs/功能与技术说明.md`

`AppCompositionRoot` 注册 LRCLIB、可选本地 Provider、网易云、QQ、酷狗。`LyricProviderRegistry` 使用统一取消令牌、Provider 隔离、并发/软等待和质量路由；播放器已有 QQ/网易/酷狗 ID 时，可以跳过搜索直接按平台 ID 取歌词。缓存只保存成功歌词，文档显示没有把“无结果”作为永久负缓存。SQLite 用于 song map 和 offset 等映射，不是完整歌词版本账本。

Taskbar 的 `LyricMatcher` 还会区分 live、remix、acoustic、demo、instrumental 等版本特征，并结合 Jaro-Winkler、token overlap、时长等评分。这是机制参考；SpotifyLyrics 当前 `QueryPlanner/SafeMatcher` 已有更严格的硬冲突保护，本报告不建议直接复制 Taskbar 的固定阈值。

### 3.4 Lyricify-App-main 的证据边界

`/Users/apple/backup/sptifylyrics/Lyricify-App-main` 未发现 `.cs`、`.csproj`、Swift 或可用于重建主应用 Provider 的源码，主要是 README、旧版本文档、XAML、图片和本地化资源。README 的明确事实包括：

- Lyricify 4 面向 Spotify；Lyricify Lite 面向接入 SMTC 的 Windows 播放器；
- Lyricify 3 已 EOL，文档提到 Spotify、iTunes、Apple Music、QQ、网易云、YesPlayMusic 等；
- 歌词处理代码指向独立的 `WXRIW/Lyricify-Lyrics-Helper`，不是本地 `Lyricify-App-main` 的主应用源码；
- helper 公开 README 列出 QQ、网易云、酷狗、Soda、Apple Music、Musixmatch 搜索，并支持 LRC、QRC、KRC、YRC、TTML、Spotify raw JSON、Musixmatch raw JSON 等解析。

因此 Lyricify 主目录的来源表只能标为“文档/历史/只有声明”。helper 的能力可作为公开资料研究，但不能将 helper 的 Apache-2.0 许可证或实现路径自动套用到主仓库。

### 3.5 Dynamic Lyrics 的允许审计结论

根据公开 App Store、官网 FAQ/隐私页和黑盒观察，只能确认：

- 产品公开支持 Spotify、Apple Music 等音乐服务连接；
- 官方说明承认歌词可用性受授权、地区、网络和同步质量影响；
- 公共版本说明提到翻译、逐词歌词选项，以及本地 TTML 能力；
- 黑盒运行可观察到当前曲 metadata、带时间的歌词列表和翻译层。

不能从这些证据推出它使用了哪个歌词 Provider、如何获取 token、请求了什么 URL、如何匹配版本、如何缓存、是否有内部授权协议。此对象在报告中所有“来源/接口/实现”均标为未知，不作为实现依据。

## 4. 来源能力与数据字段矩阵

### 4.1 身份字段

| 来源 | 平台 ID | Spotify ID | ISRC | hash/音频身份 | 时长 | 版本字段质量 |
|---|---:|---:|---:|---:|---:|---|
| 本地文件 | 可选 | 通常无 | 通常无 | 可从文件计算，但不是平台身份 | 常见 | 取决于文件名/metadata |
| LRCLIB | 有 | 通常无 | 未稳定证明 | 无 | 有 | 标题/艺人/专辑/时长，版本语义较弱 |
| 网易云 | 有 song ID | 通常无 | 未稳定证明 | 无 | 有 | 依赖搜索结果标题与艺人；Live/翻唱需额外判断 |
| QQ | 有 song ID/MID | 通常无 | 未稳定证明 | 无 | 有 | 标题/歌手/专辑/时长；QRC 本身不证明 Spotify 身份 |
| 酷狗 | lyric ID/accesskey、hash、albumAudioID | 通常无 | 未稳定证明 | **有 hash，但不能单独当作 TrackIdentity** | 有 | 音频 hash 有帮助，但仍需标题/艺人/时长和版本判断 |
| Musixmatch | track ID | 可作为查询字段/关联字段 | 给定实现中未稳定证明 | 无 | 有 | 可返回丰富 metadata，仍需处理翻唱/Live/版本 |
| Spotify Web API | Spotify ID/URI | **有** | API 能取得时有 | 无 | 有 | 目录 metadata 最强；不代表歌词有正文 |
| Apple Music 正式路线 | catalog ID | 无 | 可能有 | 无 | 有 | 需权限和具体响应验证 |

结论：参考项目普遍依赖“平台歌曲 ID + 标题/艺人/时长”而不是 ISRC。酷狗 hash 可以提高取词成功率，却不能消除错误版本问题。SpotifyLyrics 当前以 Spotify ID、URI、ISRC、艺人、专辑、时长和版本 traits 做 SafeMatcher，身份层已经比单一字符串包含关系安全。

### 4.2 歌词格式

| 格式 | 主要来源/项目 | 颗粒度 | 翻译承载 | 对 SpotifyLyrics 的意义 |
|---|---|---|---|---|
| 纯文本 | 所有来源/本地 | 无时间 | 可能另字段 | 当前已有；仍需明确 `alignmentQueued`，不能伪造同步 |
| LRC | LRCLIB、网易、QQ、酷狗、本地 | 逐行 | 独立翻译 LRC 或 provider 字段 | 当前已有，成熟兼容层 |
| LRCX | LyricsX | LRC 扩展 | `tr` 等附件 | 说明元数据/翻译/词时间可以独立于原文保存，但许可证和格式要单独实现 |
| QRC | QQ | 逐词/音节 | `ts` 等翻译字段 | 有潜在逐字价值；当前 SpotifyLyrics 主要按行模型，尚未等价支持 |
| KRC | 酷狗 | 逐词/音节 | language JSON 等 | 有潜在逐字价值；涉及解密、hash 和服务风险 |
| YRC/KLYRIC | 网易云 | 逐词/音节或增强歌词 | TLYRIC/其他字段 | 可能补充逐词时间；现有 SpotifyLyrics 网易链路已有部分正文价值，但不应以格式存在假设授权 |
| TTML | Apple/Dynamic/本地工具生态 | 逐行或逐词，视文档 | 可有多语言层 | SpotifyLyrics 编辑器当前不纳入 TTML；以后应独立导入/导出设计 |
| Spotify/Musixmatch raw JSON | helper/LyricsKit 公开资料 | 逐行/逐词，视响应 | 可有翻译 | 不能因为解析器存在就直接使用私有请求 |

### 4.3 日语能力

- LyricsX 的展示层能从已有 annotation 显示 furigana/romaji；它不是完整日语形态分析器，也不应被当作读音生成来源。
- QQ helper 资料中有官方读音/日文辅助处理的迹象，但不是每首歌都保证存在，且来源字段和授权需逐曲验证。
- 参考项目没有提供一套可以证明覆盖人名、艺名、当て字、助词读法和活用变化的通用日语读音数据库。
- 没有任何一个被审计的来源能够保证同时提供原文、官方假名、罗马音、翻译和逐字时间轴。SpotifyLyrics 现有的 `originalText/kanaText/romajiText/translationText` 分层仍然是更可控的数据模型。

## 5. 机制审计

### 5.1 Provider 插件与路由

| 机制 | 参考项目证据 | SpotifyLyrics 对照 | 结论 |
|---|---|---|---|
| Provider 协议/注册表 | LyricsKit `Group`；Taskbar `ILyricProvider`/`ILyricProviderRegistry`；helper `Searchers` | 已有 Track/Lyrics Manager 与 Provider 分层 | **当前已经拥有主结构**；可吸收注册表和来源诊断思想 |
| 并发搜索 | LyricsKit Group 异步流；Taskbar Registry 分批并发、软等待 | 已有独立 Provider 错误、取消和乱序保护 | 当前实现更符合 macOS 主路径；无需复制外部阈值 |
| 搜索取消 | LyricsX `Task` 取消；Taskbar linked `CancellationToken` | 已有切歌/旧请求取消 | **已有**；继续保留当前 TrackIdentity 守卫 |
| 候选评分 | LyricsX quality/priority；Taskbar Jaro-Winkler、时长、版本 traits；helper CompareHelper | 当前已有 QueryPlanner/SafeMatcher、hard conflict 和解释 | **我们已有实现更好**，只可对照测试样本 |
| 艺人别名 | helper ArtistHelper/CompareHelper 有有限辅助；没有证据显示完整 alias DB | SpotifyLyrics 有 TrackAlias/QueryPlanner，但来源覆盖仍有限 | **部分拥有**；继续扩展数据而不是复制 helper |
| 平台 ID 映射 | QQ MID、网易 ID、酷狗 hash/ID、Musixmatch ID、Spotify ID | providerSourceID 可保存来源标识；跨平台可信映射仍不完整 | **部分拥有**；值得独立设计可信映射，不把 hash 当强身份 |
| 音频 hash | 酷狗搜索/取词依赖 hash | 当前有音频 hash 用于 alignment provenance，不用于 Provider 身份 | **用途不同**；不应强行引入酷狗 hash 依赖 |
| 逐字解析 | QRC/KRC/YRC、LRCX `tt`、Musixmatch richsync、TTML | 当前主要是逐行时间轴；排轴 V1 也只做逐行 | **当前缺失**；但属于独立格式/数据模型阶段，不是本轮接 Provider 的理由 |
| 翻译合并 | 网易 TLYRIC、QQ `ts`、酷狗 language JSON、Musixmatch 翻译 | Provider 翻译与 AI Translation V1 已分层 | **部分拥有**；来源翻译必须保持 sourceKind，不覆盖 AI/人工版本 |
| 单曲偏移 | LyricsX global offset；Taskbar player/per-track/source offset | 当前有播放位置/时间轴状态，但没有完整跨来源 offset 账本证据 | **部分拥有**；值得吸收“按歌曲/来源保存偏移”，不应改 UI |
| 本地文件扫描 | LyricsX 拖放/本地持久化；Taskbar Local provider 读 LRC/QRC/KRC/内嵌 | 当前有共用只读本地歌词索引与编辑/导入 | **我们已有实现更好**；可参考格式识别和文件关联 |
| 缓存 | LyricsX 本地 LRC/LRCX；Taskbar 成功歌词 JSON + song map/offset SQLite | SpotifyLyrics 有 SQLite Track/Lyrics/Translation/编辑版本 | **我们已有版本管理更完整**，不采用永久 negative cache |
| 播放器适配 | LyricsX 依赖 MusicPlayer；Taskbar Windows SMTC；Lyricify 支持多个宿主 | SpotifyLyrics 专注 Spotify Desktop + Web Catalog | 多播放器不是当前目标；不适合扩大范围 |
| 无歌词/人工导入 | LyricsX 搜索和拖放；Taskbar 本地/纯音乐分支；Lyricify 文档有手动导入/上报 | SpotifyLyrics 有 noTextSource、LRC 导入、编辑版本 | **当前部分/较完整**；应优先改善错误可解释性，而非复制 UI |

### 5.2 参考项目中值得吸收的非 UI 思想

1. Provider Registry 统一返回“来源、候选、质量、失败分类”，而不是让每个 Provider 直接修改当前歌词。
2. 当前播放器若有可靠的平台 song ID，优先按 ID 取词；没有 ID 时才走标题/艺人/时长匹配。
3. 竞争请求要区分“先返回可用候选”和“等待完整批次”，并且任何结果都必须再次检查取消令牌与 TrackIdentity。
4. 来源缓存只缓存成功内容；不把一次网络失败固化成永久 no-lyrics。
5. 逐行歌词、逐词歌词、翻译层、偏移量和原始响应应当是不同的数据层，不能把所有内容拼入一条普通 LRC 正文。

### 5.3 不应吸收的做法

- 用浏览器 `usertoken`、Cookie、Referer 或内部 WebPlayer token 作为正式产品认证。
- 通过酷狗 hash、QQ MID 或网易 ID 单独证明 Spotify Track 身份。
- 用固定低阈值解决 Forever 这类艺人/版本证据不足的问题。
- 直接复用未明确许可证的 Lyricify 主仓库代码或资源。
- 把 Dynamic Lyrics 的不可观察行为猜成某个 Provider 的实现。

## 6. 与 SpotifyLyrics 的能力对照

以本次基线 `63b555d` 的真实源码结构为准，不以旧 progress 文档或合同脚本替代代码证据。

| 能力 | 当前状态 | 对照结论 |
|---|---|---|
| LocalLyricsProvider / 只读本地索引 | 已完整拥有 | 与参考项目的本地路径相当；当前共用索引、不改用户文件的边界更清晰 |
| SQLite Track/Lyrics/Translation/编辑版本 | 已完整拥有（已完成 v1-v3 主路径） | 比 Taskbar 的 cache + map 更接近真正版本管理；无需移植其 JSON cache |
| LRCLIB | 已接入主路径 | 与参考项目完全重合；没有新增来源价值 |
| 网易云实验源 | 已接入主路径 | 与 LyricsX/Taskbar/helper 重合；可参考解析/错误分类，不再重复造 Provider |
| QQ 实验源 | 已接入主路径 | 与参考项目重合；水曜日の約束 32 行是当前正确回归，不得破坏 |
| 酷狗 Provider | 当前缺失 | 技术上可能增加 KRC/冷门覆盖，风险和维护成本高；需授权/实测后再决定 |
| Musixmatch Provider | 当前缺失 | 可能增加逐字和翻译；正式授权是前提，浏览器 token 不可作为默认方案 |
| Apple Music lyrics Provider | 当前缺失 | 可能有日本语和 TTML 价值，但需要官方 API/权限验证；不采用私有 cookie 路径 |
| Spotify 私有 color-lyrics | 当前不应接入 | 当前目录 OAuth/Spotify Desktop 识别已够用，私有 endpoint 不是安全新增能力 |
| Spotify Web API 搜索 | 已完整拥有 | 参考项目中部分路径依赖 Spotify/播放器 metadata；我们已有正式 OAuth/PKCE 和 TrackMetadata 映射 |
| QueryPlanner / SafeMatcher / version traits | 已有且近期修复 | 对 Live、Remix、Instrumental、Cover 等身份保护应保持当前方案，不降低阈值 |
| 多艺人/别名 | 部分拥有 | 当前方向正确，但外部项目没有可直接移植的完整日语别名库 |
| 逐行 LRC | 已完整拥有 | 当前主能力成熟 |
| 逐字 QRC/KRC/YRC/LRCX/TTML | 当前缺失或仅部分解析 | 值得另行做格式/数据模型审计；不应在本轮直接接入高风险来源 |
| Provider 翻译 + AI 翻译版本 | 部分/已分层 | 现有 sourceKind 和 TranslationVersion 设计比参考项目的混合字段安全 |
| 全局/单曲/来源偏移 | 部分拥有 | 可吸收 Taskbar 的数据层思想，不能从外部 UI 推断需求 |
| 本地目录监控 | 部分拥有 | 当前索引是只读扫描；持续监听需另行评估，非本轮 |
| 播放器适配 | Spotify Desktop 已完整；其他播放器缺失 | 多宿主不是本产品当前边界 |
| LRC 导入/导出和人工编辑 | V1 已完成 | 与参考项目功能相当；TTML 仍未实现 |
| 无歌词/失败/加载状态 | 已有主状态 | 当前应继续强调 providerNoBody、noTextSource、candidate 等可解释分类 |

## 7. 当前仍可能可用、已失效和高风险来源

### 7.1 仍可能可用

“仍可能可用”只表示代码或公开文档存在现实调用路径，不表示本日一定可用：

- 本地 LRC/LRCX/QRC/KRC/内嵌歌词：最稳定，且用户对文件有控制权。
- LRCLIB：无账号、接口简单，但覆盖和限流不保证。
- 网易云、QQ、酷狗：参考项目中存在实际请求/解析代码；当前可用性受接口变更、反爬和服务条款影响。
- Musixmatch：技术数据价值高，但给定实现使用 usertoken，不应视为可直接产品化接口。
- Apple Music：仅在正式 MusicKit/开发者授权路径成立时考虑，当前没有足够证据证明本项目可以直接接入。

### 7.2 已失效或仅历史存在

LyricsKit 的公开来源列表中，TTPod、Gecimi、Syair、Xiami 和 ViewLyrics 被标记为停用或不可用；本地 Dynamic 包中的网络例外名单不能作为“当前可用来源”证据，也不在本报告采用。Lyricify 3 已由其 README 标注为 EOL，不能按其旧文档推断 Lyricify 4 当前 Provider 实现。

### 7.3 风险分级

| 风险级别 | 来源/路径 | 原因 |
|---|---|---|
| 低 | 用户本地文件、正式 Spotify Web API | 认证和数据边界可控；歌词内容授权仍由用户/服务条款决定 |
| 中 | LRCLIB | 公共服务依赖、覆盖和限流不确定；当前已接入，继续做好独立失败即可 |
| 中高 | 网易云、QQ、酷狗未公开接口 | 反爬、参数加密、接口变更、地域和服务条款风险；当前已有实验源，新增重复实现收益低 |
| 高 | Musixmatch 浏览器 usertoken | token 获取方式、隐私、封禁和 ToS 风险；必须换成正式授权/合作接口才能产品化 |
| 高 | Spotify 私有歌词 endpoint | 非公开接口、内部 token/header、随时变化；不应复制 |
| 高 | Apple Music 私有网页 token / Dynamic 内部来源 | 不可验证授权和内部协议；不能靠黑盒还原 |
| 未知 | Soda、WXRIW 服务端 | 给定路径没有足够协议、稳定性和授权证据 |

## 8. 针对冷门日语歌曲的评估

当前审计没有找到一个同时满足“冷门日语覆盖、正式可授权、版本身份可靠、无需 Cookie/签名、能提供逐行/逐字和翻译”的现成来源。

对 `水曜日の約束 / Kawasaki.Rio` 这类歌曲，参考项目能说明的只是：QQ/网易/酷狗/外部 helper 有更多搜索入口或格式解析器；它不能证明这些平台一定有正文，也不能证明候选就是 Spotify 当前版本。对 `Forever / VILLSHANA, Mahiru`、`あやふや / みさき` 这类样本，扩大来源数量仍然可能只得到“有歌曲候选、没有可读取正文”或“版本证据不足”。

因此冷门覆盖的关键瓶颈仍然是：

1. 平台是否真正存有正文，而不是是否能搜到歌曲页面；
2. 平台候选是否能与 Spotify 版本建立可信身份；
3. 返回的是原文、纯文本、逐行、逐字还是翻译；
4. 服务是否允许应用长期自动读取、缓存和展示；
5. 失败后是否能给出可解释的 noTextSource，而不是错误版本。

## 9. 最值得真实实验的前三个来源

### 9.1 第一名：Musixmatch（仅正式授权/合作 API 路线）

**新增价值：**逐字/富同步歌词、翻译和可能的 Spotify track 关联字段，正好补足当前“有正文但缺逐字/翻译”的数据层。
**风险：**参考实现需要 `usertoken`；从浏览器会话获取 token、复制请求头或依赖内部 endpoint 都不应进入 SpotifyLyrics。
**实验前置：**取得正式 API/合作授权、确认日本语覆盖和允许的缓存/展示范围；用 20 首已知 LRCLIB 无正文的日语歌曲做单独覆盖测试。
**不保证：**它不一定比 QQ/网易更覆盖真正冷门的日本独立发行，也不一定每首都有逐字层。

### 9.2 第二名：Apple Music（官方 MusicKit/开发者授权路线）

**新增价值：**可能补充另一套商业授权歌词数据和 TTML/逐词结构，且可能覆盖部分日本语目录。
**风险：**开发者 token、用户授权、地区/订阅限制、API 能力和歌词内容权限都需要验证；不采用浏览器 cookie 或 Dynamic 内部协议。
**实验前置：**先做官方文档级可行性和最小授权实验，不把 Dynamic 的黑盒行为当作 API 证明。
**不保证：**能查询 Spotify 未在 Apple Music 匹配的冷门曲，也不保证 Mac App 以当前用户状态取得歌词。

### 9.3 第三名：酷狗（仅授权/用户自有 KRC 路线）

**新增价值：**KRC 逐字/音节时间、hash 绑定和部分翻译，可能补充当前缺少的逐字格式。
**风险：**参考代码依赖未公开接口、hash 搜索和 KRC 解密；自动抓取/长期缓存的条款和维护风险高。
**实验前置：**优先验证用户自己导入的 KRC 解析，而不是先做网络爬取；若无正式接口或许可，维持“本地 KRC 导入”而不新增在线 Provider。

## 10. 推荐只先实现的一个 Provider

### 推荐

**先做 Musixmatch 的“正式授权可行性实验”，而不是立即实现抓取 Provider。**

实验顺序应为：

```text
确认官方授权/接口资格
  → 仅取 20 首冷门日语样本的候选和歌词能力
  → 记录原文/逐行/逐字/翻译/版本/时长/错误
  → 与现有 QQ、网易、LRCLIB 做去重比较
  → 只有新增覆盖和授权边界都成立，才设计正式 Provider
```

选择原因：

- 它是被审计来源中最可能补足“逐字时间和翻译”的来源，而不是再提供一份相同 LRC；
- 其候选查询可带标题、艺人、专辑、时长和 Spotify 关联字段，适合验证 SafeMatcher 的身份证据；
- 它的主要问题不是技术上无法请求，而是 token、授权、条款和可维护性；先做授权实验可以避免把高风险逆向路径写进主工程。

### 为什么不推荐其他来源作为第一实现

- **LRCLIB**：SpotifyLyrics 已有，重复度最高。
- **网易云/QQ**：SpotifyLyrics 已有真实主路径；继续堆同一来源的变体不会解决“平台本身没有正文”。
- **酷狗**：有新格式价值，但网络路径依赖 hash/加密/未公开接口；先做本地 KRC 解析比直接抓取安全。
- **Apple Music**：长期可能是更合规的新增来源，但必须先证明官方 API 权限、歌词访问范围和日语覆盖；当前不能把 Dynamic 或历史代码当作接入依据。
- **Spotify 私有歌词**：内部 endpoint 和 token 风险过高，且产品已有 Spotify Desktop/Web API 识别链路。
- **Soda/WXRIW 服务端**：本地证据不足，协议和长期维护不可评估。
- **历史来源**：已标记停用或不可用。
- **Dynamic Lyrics**：闭源，不可从黑盒行为还原 Provider。

## 11. 后续若进入实现，建议的验收边界

本报告不实现任何 Provider；若后续确认采用推荐方向，最小实验应满足：

1. 不使用浏览器 token、Cookie 复制、私有 header 或绕过登录/反爬。
2. Provider 只返回平台候选和歌词候选，不修改 Spotify 播放位置。
3. 每个结果记录 source、providerSourceID、查询 kind、正文类型、行数、是否逐字、翻译可用性和错误分类。
4. SafeMatcher 先处理主艺人、时长、Live/Remix/Cover/Instrumental 等硬冲突，再考虑总分。
5. 仅在用户确认或高置信度、无版本冲突时写入 SQLite；候选和失败不写入。
6. 任何在线歌词都不默认永久保存，除非授权/条款允许；保存时保留 sourceKind 和内容指纹。
7. 先用冷门日语样本验证“真的有正文”，不使用中文热门歌曲覆盖率替代。

## 12. 本轮交付与未修改范围

本轮仅新增本报告：

`/Users/apple/backup/sptifylyrics/docs/REFERENCE_PROJECTS_LYRICS_AUDIT.md`

没有修改 SpotifyLyrics 业务源码、Provider、QueryPlanner、SafeMatcher、数据库、UI、AI、编辑器或自动排轴；没有新增 Provider；没有执行数据库合并；没有创建 commit。参考目录、旧审计文档和 DerivedData 备份的 Git 状态属于审计开始前已有未跟踪内容，本轮不处理。

## 13. 资料索引

### 本地文件

- `/Users/apple/backup/sptifylyrics/LyricsX-master/LICENSE`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/README.md`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/Component/AppController.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/Search/SearchLyricsViewController.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsX/View/KaraokeLabel.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/LyricsXPackage/Package.swift`
- `/Users/apple/backup/sptifylyrics/LyricsX-master/appcast.xml`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/LICENSE`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/docs/功能与技术说明.md`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.App/AppCompositionRoot.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Services.LyricProviderRegistry.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Services.LyricifyLyricProvider.cs`
- `/Users/apple/backup/sptifylyrics/TaskbarLyrics-main/TaskbarLyrics.Core/Services.LocalLyricProvider.cs`
- `/Users/apple/backup/sptifylyrics/Lyricify-App-main/README.md`
- `/Applications/Dynamic Lyrics.app`（仅作产品存在性/黑盒对象，不作为源码来源）

### 公开资料

- [LyricsKit README 与支持的来源/格式](https://github.com/MxIris-LyricsX-Project/LyricsKit)
- [Lyricify Lyrics Helper（Apache-2.0，独立于 Lyricify 主仓库）](https://github.com/WXRIW/Lyricify-Lyrics-Helper)
- [TaskbarLyrics README/源码仓库](https://github.com/anync/TaskbarLyrics)
- [Dynamic Lyrics App Store](https://apps.apple.com/gb/app/dynamic-lyrics/id6476125287?platform=mac)
- [Dynamic Lyrics FAQ](https://dynamiclyrics.app/faq)
- [Dynamic Lyrics Privacy](https://dynamiclyrics.app/privacy)
