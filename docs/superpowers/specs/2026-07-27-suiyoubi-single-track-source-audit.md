# 单曲来源穷尽审计：水曜日の約束 / Kawasaki.Rio

生成：2026-07-27T21:53:19+0800

> 规则：有歌曲页 ≠ 有歌词正文；不绕过登录/验证码/反爬。

## 查询变体

- `水曜日の約束`
- `水曜日の約束 Kawasaki.Rio`
- `水曜日の約束 Kawasaki Rio`
- `すいようびのやくそく`
- `すいようびのやくそく Kawasaki.Rio`
- `suiyoubi no yakusoku`
- `suiyoubi no yakusoku Kawasaki Rio`
- `suiyobi no yakusoku`
- `Wednesday Promise`
- `Wednesday Promise Kawasaki Rio`
- `Kawasaki.Rio 水曜日の約束`
- `kawasaki.rio`
- `Kawasaki Rio`
- `カワサキリオ`
- `かわさき りお`

## 结果矩阵

| 来源 | 正确歌曲 | 歌词正文 | 汉字原文 | 假名 | 罗马音 | 逐行轴 | 程序可读 |
|------|----------|----------|----------|------|--------|--------|----------|
| Local | N | N | N | ? | ? | ? | Y |
| LRCLIB | N | N | N | N | N | N | Y |
| 网易云 | Y | N | N | N | N | N | Y |
| QQ音乐 | Y | Y | Y | N | N | N | Y |
| 酷狗 | Y | N | N | N | N | N | N |
| Uta-Net | ? | N | N | N | N | N | N |
| UtaTime | ? | N | N | N | N | N | N |
| UtaTen | ? | N | N | N | N | N | N |
| J-Lyric | ? | N | N | N | N | N | N |
| AWA | ? | N | N | N | N | N | N |
| YouTube搜索 | ? | N | N | N | N | N | N |

## 关键发现

### 1) Kawasaki.Rio 本家 vs HoneyWorks 同名曲

- HoneyWorks / Gero 等「水曜日の約束」歌词以 `折り返し水曜日` 开头，**不是** Kawasaki.Rio。
- Kawasaki.Rio 正文（QQ `songmid=004YkjHH0g5pRt`）以 `「これでおわり」って言われた夜` 开头。
- SafeMatcher 必须以艺人+时长约束，禁止同名自动串台。

### 2) 各源

- **Local**：无命中文件。
- **LRCLIB**：多变体 search/get → **无正确曲 / 404 TrackNotFound**。
- **网易云**：正确曲 id=`2695572249`（Kawasaki.Rio），**lyric 正文为空**；同名其他艺人有词但不可用。
- **QQ音乐**：正确曲 `004YkjHH0g5pRt`，**有可程序读取正文（无时间轴 plain）**，retcode=0。
- **酷狗**：本轮无稳定程序可读正文。
- **Uta-Net / UtaTime / UtaTen / J-Lyric / AWA**：无公开 API；CF/条款下本轮 **不程序取正文**。
- **官网/YT 说明**：未获可程序读取正文。

## 决策

- **outcome**: `hasTextSource`
- **programmable_body_sources**: `['qq']`
- **next_step**: `import_best_body` → 采用 QQ 正文；无时间轴 → `alignmentQueued`；补假名/罗马音。
- **不**因总体覆盖率默认接 QQ；**因本单曲穷尽验证** QQ 是唯一可读正文源。
- 对仍无正文的冷门曲（如 あやふや）走 **ASR 本地音频** 路径。
