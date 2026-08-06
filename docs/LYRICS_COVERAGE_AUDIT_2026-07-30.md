# 歌词覆盖率与缺漏审计（2026-07-30）

> 本文是只读审计记录。本轮未修改业务源码、Provider、匹配算法或正式数据库，也未提交 commit。

## 1. 审计范围与证据边界

- 工作目录：`/Users/apple/backup/sptifylyrics`；branch：`ui-redesign-phase-1`；HEAD：`e8caced8af640146d146728d4e5929a96378994b`。
- 真实 App：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`；进程由该绝对路径启动/核对。
- Spotify Desktop 当前真实播放身份可见为 `恋風 / Lilas`，约 3:02；Spotify Desktop 搜索页也能看到 `水曜日の約束 / Kawasaki.Rio` 的真实单曲页。
- 本次 App 内 Spotify Web API 状态实际为“未授权 Spotify 在线曲库”。Zen 中出现了授权同意页，但本审计没有点击“同意”，因此不把 Web API 搜索成功冒充为已授权的 App 结果。
- 为保证样本可复现，使用 Spotify 公共 Web Player 的只读搜索/公开曲目页核对 39 个真实 Spotify ID、标题、艺人、专辑、时长和封面存在性；ISRC 未从公开页验证，不能报告为 App API 已取得。
- Provider 直探：39 首、四个当前 Provider，使用标题+艺人规范查询；不写 SQLite。
- 主路径回放：14 首，真实运行 `LyricsSearchManager → QueryPlanner → SafeMatcher`，覆盖四个已知样本、候选、纯音乐、Live/版本冲突和罗马音查询。其余 25 首的表格标注“直探”，不能冒充完整主路径覆盖。
- 生产 SQLite 只读核对：`/Users/apple/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3`；未清空、未插入、未修改用户锁定版本。

缩写：`B42/S`=正文 42 行且有逐行时间；`B56/P`=正文 56 行但纯文本；`C77×0.00`=候选正文 77 行、最高 SafeMatcher 分数 0.00；`NM`=无匹配；`NL`=明确无歌词；`M`=真实 LyricsSearchManager 回放。

## 2. 39 首真实歌曲总表

|#|Spotify 曲目（ID）|查询与元数据（标题 / 艺人 / 专辑 / 时长）|ISRC|SQLite|Local|LRCLIB|网易|QQ|SafeMatcher / 主路径|正文、时间轴、翻译|Session / 主要分类|人工导入|
|---:|---|---|---|---|---|---|---|---|---|---|---|---|
|1|恋風 / Lilas<br>`6QGuDk8tY8Lan39gTWtXWK`|`恋風` / Lilas / 恋風 / 3:02|未验证|S|NM|B42/S|C49×0.53|NM|M match 42行/S conf 1.00|有正文 / 有轴 / SQLite 有翻译版本|SQLite S|可选（不必导入）|
|2|水曜日の約束 / Kawasaki.Rio<br>`5MqkkCSrUjqyaKVOlvEn0w`|`水曜日の約束` / Kawasaki.Rio / 水曜日の約束 / 2:51|未验证|S+P+duplicateKey|NM|NM|C46×0.05|NM|M match 32行/P conf 1.00|有正文 / 无轴 / —|SQLite P|是（需后续排轴）|
|3|あやふや / みさき<br>`4l6XKftR34zrUw0bTnwoVv`|`あやふや` / みさき / あやふや / 1:59|未验证|—|NM|NM|C77×0.00|NM|M noMatch|无可信正文 / — / —|M noMatch|条件可解决（用户提供文本/LRC）|
|4|Forever / VILLSHANA , Mahiru<br>`2cLlZmf690vuBEyA4EMm3g`|`Forever` / VILLSHANA , Mahiru / KILL is LOVE (EP) / 2:49|未验证|—|NM|NM|C41×0.05|NM|M noMatch|无可信正文 / — / —|M noMatch|条件可解决（用户提供文本/LRC）|
|5|春を告げる - From THE FIRST TAKE / yama<br>`0QDjYBER1ZqISxA2Gc0cJe`|`春を告げる - From THE FIRST TAKE` / yama / 春を告げる - From THE FIRST TAKE / 5:01|未验证|—|NM|B40/S|C54×0.98|B59/S|M match 40行/S conf 1.00|有正文 / 有轴 / —|M match 40行/S conf 1.00|可选（不必导入）|
|6|夜に駆ける / YOASOBI<br>`3dPtXHP0oXQ4HCWHsOA9js`|`夜に駆ける` / YOASOBI / 夜に駆ける / 4:21|未验证|—|NM|B56/S|C60×0.98|B69/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 56行/S|可选（不必导入）|
|7|群青 / YOASOBI<br>`0T4AitQuq8IJhWBWuZwkFA`|`群青` / YOASOBI / 群青 / 4:08|未验证|—|NM|B80/P|C79×0.98|B81/S|直探 max 0.98/autoHigh|有正文 / 无轴 / —|直探 plain|是（需后续排轴）|
|8|怪物 / YOASOBI<br>`06XQvnJb53SUYmlWIhUXUi`|`怪物` / YOASOBI / 怪物 / 3:26|未验证|—|NM|B56/S|C59×0.98|B62/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 56行/S|可选（不必导入）|
|9|アイドル / YOASOBI<br>`7ovUcF5uHTBRzUpB6ZOmvt`|`アイドル` / YOASOBI / アイドル / 3:33|未验证|—|NM|B151/S|C83×0.98|B79/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 151行/S|可选（不必导入）|
|10|Lemon / Kenshi Yonezu<br>`04TshWXkhV1qkqHzf31Hn6`|`Lemon` / Kenshi Yonezu / STRAY SHEEP / 4:16|未验证|—|NM|B56/P|C46×0.45|C1×0.38|M match 56行/P conf 1.00|有正文 / 无轴 / —|M match 56行/P conf 1.00|是（需后续排轴）|
|11|Pretender / OFFICIAL HIGE DANDISM<br>`1OBAWkIciXl8rmbKtrp9ZG`|`Pretender` / OFFICIAL HIGE DANDISM / Pretender / 5:26|未验证|—|NM|B52/S|C56×0.53|B75/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 52行/S|可选（不必导入）|
|12|ドライフラワー / Yuuri<br>`7dH0dpi751EoguDDg3xx6J`|`ドライフラワー` / Yuuri / ドライフラワー / 4:46|未验证|—|NM|B47/S|C50×0.53|NM|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 47行/S|可选（不必导入）|
|13|ただ君に晴れ / Yorushika<br>`3wJHCry960drNlAUGrJLmz`|`ただ君に晴れ` / Yorushika / 負け犬にアンコールはいらない / 3:19|未验证|—|NM|B35/S|C44×0.53|B54/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 35行/S|可选（不必导入）|
|14|unravel / TK from Ling tosite sigure<br>`3COJDrvCeD6jCefragOBuK`|`unravel` / TK from Ling tosite sigure / egomaniac feedback / 4:04|未验证|—|NM|B27/S|C49×0.35|NM|M match 27行/S conf 1.00|有正文 / 有轴 / —|M match 27行/S conf 1.00|可选（不必导入）|
|15|Kaikai Kitan / Eve<br>`6y4GYuZszeXNOXuBFsJlos`|`Kaikai Kitan` / Eve / Kaikai Kitan / Ao No Waltz / 3:41|未验证|—|NM|B57/S|C58×0.55|NM|M match 57行/S conf 1.00|有正文 / 有轴 / —|M match 57行/S conf 1.00|可选（不必导入）|
|16|紅蓮華 / LiSA<br>`0qMip0B2D4ePEjBJvAtYre`|`紅蓮華` / LiSA / LEO-NiNE / 3:58|未验证|—|NM|B34/S|C47×0.90|B57/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 34行/S|可选（不必导入）|
|17|千本桜 / MOSAIC.TUNE feat.初音ミク , Hatsune Miku<br>`5zYrqFyz0NPqQpx6XrAz2g`|`千本桜` / MOSAIC.TUNE feat.初音ミク , Hatsune Miku / みんなみくみくにしてあげる♪～Heartsnative2～ / 4:16|未验证|—|NM|NM|C48×0.35|NM|M candidates 1 top 0.73|候选正文 / 未采用 / —|M candidates 1 top 0.73|是（需选择/确认）|
|18|ロキ / Mikito P<br>`5WCK18MbTKuOcmLsOXMaHd`|`ロキ` / Mikito P / DAISAN WAVE / 3:50|未验证|—|NM|B34/S|C47×0.45|NM|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 34行/S|可选（不必导入）|
|19|First Love / Hikaru Utada , David Sanborn<br>`7tPjWFHyp0csjVuba7CgQ9`|`First Love` / Hikaru Utada , David Sanborn / First Love / 4:17|未验证|—|NM|C32×0.53|C36×0.53|NM|M match 32行/S conf 0.74|有正文 / 有轴 / —|M match 32行/S conf 0.74|可选（不必导入）|
|20|Merry-Go-Round of Life / Joe Hisaishi , Royal Philharmonic Orchestra<br>`1CHswVnHopmeIly3bTSnmF`|`Merry-Go-Round of Life` / Joe Hisaishi , Royal Philharmonic Orchestra / Merry-Go-Round of Life (from 'Howl’s Moving Castle') / 2:45|未验证|—|NM|NL|NM|NM|M noLyrics|无歌词（NL） / — / —|M noLyrics|否（无歌词目标）|
|21|Blinding Lights / The Weeknd<br>`0VjIjW4GlUZAMYd2vXMi3b`|`Blinding Lights` / The Weeknd / After Hours / 3:20|未验证|—|NM|B35/S|NM|B48/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 35行/S|可选（不必导入）|
|22|Flowers / Miley Cyrus<br>`7DSAEUvxU8FajXtRloy8M0`|`Flowers` / Miley Cyrus / Endless Summer Vacation / 3:21|未验证|—|NM|B46/S|C48×0.90|B52/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 46行/S|可选（不必导入）|
|23|Shape of You / Ed Sheeran<br>`7qiZfU4dY1lWllzX7mPBI3`|`Shape of You` / Ed Sheeran / ÷ (Deluxe) / 3:54|未验证|—|NM|B90/S|C116×0.90|B92/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 90行/S|可选（不必导入）|
|24|Someone Like You / Adele<br>`3bNv3VuUOKgrf5hu3YcuRo`|`Someone Like You` / Adele / 21 / 4:45|未验证|—|NM|B39/S|C70×0.90|B52/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 39行/S|可选（不必导入）|
|25|Fix You / Coldplay<br>`7LVHVU3tWfcxj5aiPFEW4Q`|`Fix You` / Coldplay / X&Y / 4:56|未验证|—|NM|B27/S|NM|B31/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 27行/S|可选（不必导入）|
|26|Bohemian Rhapsody / Queen<br>`2JiDi0qAXsPwhPqA2qaKGt`|`Bohemian Rhapsody` / Queen / A Night At The Opera / 5:54|未验证|—|NM|B50/S|NM|B63/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 50行/S|可选（不必导入）|
|27|See You Again / Wiz Khalifa , Charlie Puth<br>`3N2CRRKaJ3CHfDHsRfo8wW`|`See You Again` / Wiz Khalifa , Charlie Puth / WAP - New Rap Cutz / 3:50|未验证|—|NM|B46/S|NM|B85/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 46行/S|可选（不必导入）|
|28|Señorita / Shawn Mendes , Camila Cabello<br>`0TK2YIli7K1leLovkQiNik`|`Señorita` / Shawn Mendes , Camila Cabello / Señorita / 3:11|未验证|—|NM|B56/S|NM|B68/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 56行/S|可选（不必导入）|
|29|Kiss Me More (feat. SZA) / Doja Cat , SZA<br>`3DarAbFujv6eYNliUTyqtz`|`Kiss Me More (feat. SZA)` / Doja Cat , SZA / Planet Her / 3:29|未验证|—|NM|B66/S|NM|NM|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 66行/S|可选（不必导入）|
|30|晴天 / Jay Chou<br>`5pIcwtJYNJx93l420oR2Vm`|`晴天` / Jay Chou / 葉惠美 / 4:30|未验证|—|NM|B42/S|C65×0.23|NM|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 42行/S|可选（不必导入）|
|31|光年之外 (電影 《Passengers》 中國區主題曲) / G.E.M.<br>`1bkvGbgK4HU8B7Ue4k7O7I`|`光年之外 (電影 《Passengers》 中國區主題曲)` / G.E.M. / 光年之外 (電影 《Passengers》 中國區主題曲) / 3:56|未验证|—|NM|B39/S|B63/S|B46/S|M match 39行/S conf 1.00|有正文 / 有轴 / —|M match 39行/S conf 1.00|可选（不必导入）|
|32|体面 - Live / Kelly Yu<br>`47NmE3V5KYuRBmFJIdhEBu`|`体面 - Live` / Kelly Yu / 剧好听的歌 第10期 / 4:41|未验证|—|NM|NM|C40×0.13|NM|M match 30行/P conf 0.85|有正文 / 选中版本错误风险 / —|M match 30行/P；版本冲突|是（需正确版本）|
|33|小幸運 / Hebe Tien<br>`1ZeVIrCWzEmsJexkrgvjFv`|`小幸運` / Hebe Tien / 小幸運 / 4:26|未验证|—|NM|B44/S|NM|NM|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 44行/S|可选（不必导入）|
|34|Dynamite / BTS<br>`5QDLhrAOJJdNAmCTJ8xMyW`|`Dynamite` / BTS / BE / 3:19|未验证|—|NM|B57/S|NM|B83/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 57行/S|可选（不必导入）|
|35|Ditto / NewJeans<br>`3r8RuvgbX9s7ammBn07D3W`|`Ditto` / NewJeans / Ditto / 3:06|未验证|—|NM|B44/S|C72×0.45|B73/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 44行/S|可选（不必导入）|
|36|LOVE DIVE / IVE<br>`0Q5VnK2DYzRyfqQRJuUtvi`|`LOVE DIVE` / IVE / LOVE DIVE / 2:57|未验证|—|NM|B43/S|NM|B55/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 43行/S|可选（不必导入）|
|37|APT. / ROSÉ , Bruno Mars<br>`5vNRhkKd0yEAg8suGBpjeY`|`APT.` / ROSÉ , Bruno Mars / APT. / 2:50|未验证|—|NM|B71/S|NM|B84/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 71行/S|可选（不必导入）|
|38|Golden / HUNTR/X , EJAE , AUDREY NUNA , REI AMI , KPop Demon Hunters Cast<br>`5Cp75TUMrHF6c8xbhdligS`|`Golden` / HUNTR/X , EJAE , AUDREY NUNA , REI AMI , KPop Demon Hunters Cast / Golden (from the Netflix film KPop Demon Hunters) / 3:15|未验证|—|NM|B40/S|C52×0.90|C48×0.90|M match 40行/S conf 1.00|有正文 / 有轴 / —|M match 40行/S conf 1.00|可选（不必导入）|
|39|Best Part (feat. H.E.R.) / Daniel Caesar , H.E.R.<br>`1Q7EgiMOuwDcB0PJC6AzON`|`Best Part (feat. H.E.R.)` / Daniel Caesar , H.E.R. / Freudian / 3:30|未验证|—|NM|B50/S|NM|B57/S|直探 max 0.98/autoHigh|有正文 / 有轴 / —|直探 LRCLIB 50行/S|可选（不必导入）|

注：表中的候选行数、Provider 命中和 SafeMatcher 分数只记录摘要，不记录歌词正文。对于 25 个直探样本，`LRCLIB/网易/QQ`列是 Provider 直探，不等同于完整 Manager 顺序；完整主路径证据只对 14 行明确标为 `M`。

## 3. 主要分类与覆盖率

- `cachedSynced`：1/39（2.6%）
- `cachedPlain`：1/39（2.6%）
- `providerSynced`：30/39（76.9%）
- `providerPlain`：2/39（5.1%）
- `candidateNeedsSelection`：1/39（2.6%）
- `versionConflict`：1/39（2.6%）
- `noTextSource`：2/39（5.1%）
- `instrumental`：1/39（2.6%）

|指标|结果|口径|
|---|---:|---|
|已缓存同步歌词|1/39（2.6%）|SQLite 当前主结果为同步|
|已缓存纯文本歌词|1/39（2.6%）|SQLite 当前主结果为纯文本；水曜日的约束的旧手工同步测试版本不计入真实 Provider 同步覆盖|
|Provider 直接得到并可作为同步正文的样本|30/39（76.9%）|排除候选未采用和 #32 Live 版本冲突|
|Provider 直接得到纯文本正文|2/39（5.1%）|#7 群青、#10 Lemon；#2 由完整 Manager 主路径确认 QQ 32 行纯文本|
|当前主分类可见的同步歌词|31/39（79.5%）|缓存恋風 1 + Provider 同步 30；不把水曜日旧手工同步测试 artifact 计入|
|当前主分类可见的纯文本歌词|3/39（7.7%）|缓存水曜日 1 + Provider 纯文本 2|
|无可信正文（不含纯音乐）|2/39（5.1%）|あやふや、Forever；候选正文被 SafeMatcher 拒绝/未采用|
|纯音乐|1/39（2.6%）|Merry-Go-Round of Life，LRCLIB 明确 noLyrics|
|候选需要选择|1/39（2.6%）|千本桜，主路径仍返回 candidates|
|版本冲突|1/39（2.6%）|体面 - Live 被当前 Manager 的宽松版本查询采到非 Live LRCLIB 版本|
|人工导入/手工创建条件可解决|38/39（97.4%）|除纯音乐外，只要用户拥有文本或 LRC；这不是网络自动覆盖率|

### Provider 直探统计（39 首；不是完整 Manager 成功率）

|Provider|正文|候选|无匹配|无歌词|运行错误|说明|
|---|---:|---:|---:|---:|---:|---|
|Local LRC|0|0|39|0|0|本地索引只读扫描未命中本批歌曲；不代表用户目录绝对没有其它文件|
|LRCLIB|32（82.1%）|1|5|1|0|正文以同步/纯文本区分；20 号明确 noLyrics|
|网易云实验源|1（2.6%）|26|12|0|0|大量候选未达到 SafeMatcher 采用条件；候选不等于正文已可用|
|QQ 音乐实验源|22（56.4%）|2|15|0|0|直探下命中 22；水曜日的约束的完整 Manager 回放通过查询变体获得 QQ 32 行纯文本|

这批请求没有观察到 timeout、network、429 或 parse failure；这只能说明本次时间窗内未触发，不能推导 Provider 长期稳定性。App 层 Spotify Web API 则因未授权明确属于“未授权”，不是搜索无结果。

## 4. 已知样本与 Forever 完整诊断

### 恋風 / Lilas
- Spotify 真实 ID：`6QGuDk8tY8Lan39gTWtXWK`，时长约 3:02；ISRC 本次未由公开页验证。
- Manager：Local NM → LRCLIB match；42 行、同步、`providerSourceID=lrclib:18558378`，SafeMatcher 直探约 0.98/autoHigh。
- 真实 App 当前播放界面已显示该曲并加载缓存歌词/翻译；SQLite 有重复 LRCLIB 版本，另有一个锁定 manualEdit，说明“能显示”与“缓存去重干净”是两个问题。

### 水曜日の約束 / Kawasaki.Rio
- Spotify 真实 ID：`5MqkkCSrUjqyaKVOlvEn0w`，171.177 秒（Spotify Desktop 页显示 2:51）。
- 完整 Manager：Local NM → LRCLIB NM → 网易候选 → QQ match；32 行、纯文本、无逐行时间轴，`providerSourceID=qq:004YkjHH0g5pRt`。
- SQLite 有 QQ 32 行纯文本，但同时存在两个 stableKey、重复 QQ 版本，以及早期手工导入/手工同步测试 artifact。当前应以 QQ 纯文本与 locked 手工纯文本为真实覆盖，不能把旧测试同步版本当作自动排轴成功。

### あやふや / みさき
- Spotify 真实 ID：`4l6XKftR34zrUw0bTnwoVv`，119.160 秒。
- 完整 Manager 实际尝试了原始标题+艺人、罗马音变体、仅标题宽松查询；Local/LRCLIB/QQ 无匹配，网易返回候选但 SafeMatcher 最高为拒绝级，最终 Session 为 noMatch。
- 主要分类：`noTextSource`；次要标签：`candidateBodyRejectedBySafeMatcher`。这表示当前系统没有可安全自动采用的正文，不等于证明互联网任何页面绝对没有歌词。

### Forever / VILLSHANA（要求的完整诊断）
- Spotify 公共曲目页返回：ID `2cLlZmf690vuBEyA4EMm3g`，标题 `Forever`，艺人 `VILLSHANA, Mahiru`（这是多艺人 metadata，和只写 VILLSHANA 的查询输入存在差异），专辑为 `KILL is LOVE (EP)`，时长 168.750 秒；ISRC 未由本次公开页验证。
- SQLite：只有 TrackRecord，没有 LyricsVersion；没有缓存正文。
- 完整 Manager：Local NM、LRCLIB NM、QQ NM；网易在原始标题和仅标题变体都返回候选，但最终 noMatch；候选正文约 41 行，SafeMatcher 最高约 0.05/reject。
- 因此它不是“Spotify 目录找不到正确歌曲”：真实 Spotify ID 已找到；也不是当前代码完全没跑 Provider。主要问题是 `candidateBodyRejectedBySafeMatcher`，最终用户可见状态是 `noTextSource`。
- 处理建议：先保留候选供人工确认或要求更强的 ISRC/版本证据；不能因存在 41 行候选就自动采用，尤其要防止把同名、翻唱或版本不同的歌词写入缓存。若用户有外部文本/LRC，人工导入可以解决；本轮未把其内容写入数据库。

## 5. 缺漏原因判断

### 本批最常见的三类
1. **Provider 返回候选但 SafeMatcher 不允许自动采用**：网易直探 26/39 为候选；其中水曜日、あやふや、Forever 的候选都不能直接证明身份。该形态是冷门日语歌曲最显著的缺漏形状。
2. **有正文但没有时间轴**：本批至少观察到 Lemon、群青和水曜日的约束为纯文本；这不是 Provider 无正文，下一步如果要同步必须走真实音频排轴，不能平均铺开。
3. **缓存身份/版本历史存在重复或冲突**：水曜日存在重复 stableKey、重复 QQ 版本和旧手工同步 artifact；恋風存在相同 LRCLIB providerSourceID 的重复版本。另有 #32 体面 - Live 暴露出版本标记保护缺口。

### 对 11 类原因的落点
- Spotify 目录找不到正确歌曲：本批公共 Spotify 页 39/39 得到真实 ID；但 App Web API 当前未授权，所以只能说公共目录可解析，不能宣称 App Web API 认证搜索已通过。
- Spotify metadata 不完整：ISRC 在本次公开页均未验证；Forever 的多艺人显示说明如果 App metadata 仅保留单一艺人，可能影响匹配，但本轮未用 OAuth API 证实字段缺失。
- 查询别名不足：#15 需要罗马音回退才能建立测试样本；manager 对 #3/#4/#17 已实际尝试部分变体但仍未得到可采用正文，别名不是唯一问题。
- Provider 有正确候选但无正文：本批没有可靠证据证明候选一定是正确版本且正文已可安全采用；表中明确区分候选和正文。
- Provider 有正文但 SafeMatcher 未采用：Forever、あやふや、部分网易候选属于此类；#17 仍需选择。
- 错误版本/Live/翻唱/伴奏：#32 体面 - Live 发生了非 Live LRCLIB 候选被 Manager 接受的版本冲突风险；Merry-Go-Round of Life 被判纯音乐/无歌词。
- 有纯文本无时间轴：#2、#7、#10。
- 有同步但质量差：本轮只验证是否有逐行时间字段，没有对音频演唱点做质量评估，因此不能给出“时间轴质量通过”。
- SQLite 旧 stableKey/重复：#1、#2 已真实查到。
- 网络/限流/解析：本次 39 首 Provider 请求未触发；不能排除长期发生。
- 网络上确实找不到歌词：对 #3/#4 只能称当前已启用 Provider 无可信正文，不能据此宣称全网无歌词。
- 当前代码未运行 Provider：14 首 Manager 回放均产生 Provider diagnostics，未发现本批存在“完全没跑主路径”的证据；25 首直探不用于证明主路径已运行。

## 6. 数据与运行状态

- 正式数据库：`/Users/apple/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3`，schema version 3，约 1,081,344 bytes。
- 只读统计：Track 48、TrackAlias 118、LyricsVersion 51、LyricLine 2462、TranslationVersion 9、TranslationLine 405、ReadingLayer 0。
- 本批已查到：恋風有缓存同步版本；水曜日有缓存纯文本和历史人工/导入版本；あやふや与 Forever 无 LyricsVersion。
- 没有把候选、noMatch、failed 或人工未确认内容写进数据库；没有修改现有 locked 版本。
- 真实 App 进程核对：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics`。

## 7. 下一阶段方案

|方案|收益|风险|预计修改文件/依赖|
|---|---|---|---|
|A. 先修 QueryPlanner + SafeMatcher 版本证据|优先处理候选被拒、艺人别名、feat/Live/remix 负证据；可降低 Forever/あやふや 的误判和 #32 错版本风险|阈值放宽会把翻唱/Live 歌词错配；需要更强 Spotify ID/ISRC/时长证据和候选确认 UI|`SpotifyLyrics/Lyrics/LyricsQueryPlanner.swift`、`LyricsSafeMatcher.swift`、`TrackTextNormalizer.swift`、相关合同/真实回放测试；不新增 Provider|
|B. 选一个来源做针对性覆盖实验|在 A 之后只验证冷门日语来源是否真的有正文，避免继续盲目堆 Provider|授权、反爬、稳定性和版本错配风险；本批还没有足够证据证明某一家能解决 Forever|对应单一 Provider 文件、能力矩阵和 20 首日语复测；需要条款/接口条件|
|C. 真实本地音频逐行排轴 V1|直接解决已知纯文本缺时间轴，尤其水曜日；保留原文并输出低置信度|必须拿到当前歌曲对应的完整音频；模型和演唱版本不一致会产生漂移，不能用 TTS 或平均铺时|`AlignmentService`、音频导入/校验、对齐 helper、预览保存路径；依赖真实音频|

### 推荐
推荐 **A → B → C**，但下一阶段只选 A。原因是本批最危险的缺漏不是“所有来源都没有数据”，而是大量候选无法安全采用，且 #32 已证明版本标记保护仍有漏洞。先修证据链可以提升覆盖而不牺牲正确率；随后再用单一 Provider 做冷门覆盖验证；最后对确认的纯文本做真实音频排轴。

## 8. 审计结论

- 本批 39 首中，当前 Provider 链实际得到可用正文（同步或纯文本）约 32 首，另有 1 首缓存同步和 1 首缓存纯文本；但这是样本覆盖，不是全库覆盖率。
- 可靠同步正文是当前主要成功形态；纯文本缺时间轴和候选被 SafeMatcher 拒绝分别是主要产品缺口。
- Forever 的最终状态应记录为：**Spotify 曲目已找到；Provider 候选存在；SafeMatcher 拒绝；Session 无可信正文；需要人工确认或导入**。不能简单写成 Spotify 搜索失败。
- 本轮未修改业务源码，不提交 commit；报告生成后暂停等待下一步决定。
