# 冷门日语曲 Provider 覆盖测试（最小只读）
生成时间：2026-07-27T21:42:41+0800
样本：`Tests/fixtures/cold_jp_tracks_20.json`（20 首）

## 总览
| 指标 | 命中 |
|------|------|
| lrclib_lyric | 16/20 |
| netease_track | 20/20 |
| netease_lyric | 18/20 |
| netease_lrc | 18/20 |
| netease_tlyric | 18/20 |
| qq_track | 20/20 |
| qq_lyric | 19/20 |
| qq_needs_cookie | 1/20 |
| kugou_track | 0/20 |
| kugou_lyric | 0/20 |

## LRCLIB 失败子集（cold）
- cold 数：4
- 网易云 lyric：2
- QQ lyric：3
- 酷狗 lyric：0

## 评分与推荐
```json
{
  "netease": 74,
  "qq": 65,
  "kugou": 0
}
```

**推荐第一家实验 Provider：`netease`**

## 逐曲摘要
| id | title | artist | LRCLIB | 网易云词 | QQ词 | 酷狗词 |
|----|-------|--------|--------|----------|------|--------|
| ayafuya | あやふや | みさき | N | N | N | N |
| suiyoubi | 水曜日の約束 | Kawasaki.Rio | N | N | Y | N |
| yoru_ni_kakeru | 夜に駆ける | YOASOBI | Y | Y | Y | N |
| lemon | Lemon | 米津玄師 | Y | Y | Y | N |
| pretender | Pretender | Official髭男dism | Y | Y | Y | N |
| gunjou | 群青 | YOASOBI | Y | Y | Y | N |
| idol | アイドル | YOASOBI | Y | Y | Y | N |
| kaisui | 海の幽霊 | 米津玄師 | Y | Y | Y | N |
| betelgeuse | ベテルギウス | 優里 | Y | Y | Y | N |
| dryflower | ドライフラワー | 優里 | Y | Y | Y | N |
| odorenai | 踊 | Ado | Y | Y | Y | N |
| usen | うっせぇわ | Ado | Y | Y | Y | N |
| kaibutsu | 怪獣の花唄 | Vaundy | Y | Y | Y | N |
| soranji | そらんじ | Mrs. GREEN APPLE | N | Y | Y | N |
| ao_to_natsu | 青と夏 | Mrs. GREEN APPLE | Y | Y | Y | N |
| specialz | SPECIALZ | King Gnu | Y | Y | Y | N |
| shinunoga | 死ぬのがいいわ | 藤井風 | Y | Y | Y | N |
| matsuri | まつり | 藤井風 | Y | Y | Y | N |
| independent1 | たゆたうままに | みさき | N | Y | Y | N |
| cover_live_guard | Lemon (Live) | 米津玄師 | Y | Y | Y | N |

## 能力备注
- 网易云：公开网页 lyric 常含 LRC + tlyric；yrc 视曲目；无需登录的只读样例较多。
- QQ：搜索较易；歌词接口常 `retcode -1310`/需 Cookie。
- 酷狗：搜索可用；歌词 candidates 有时有，下载/签名不稳定。
- 假名/罗马音：三家均不保证独立假名轨；本地词典层补全。
- **多别名不能解决来源无词。**

## 下一步
只实现 `netease` 实验插件，隔离于核心默认路径之外。


## 关键结论（实现依据）

1. **多别名 ≠ 有词**：`あやふや / みさき` 网易云 **能搜到正确 song id=2717111195（时长 119160ms）**，但 `/api/song/lyric` **lrc 为空**；QQ 能搜到 songmid，歌词 `retcode=-1901`；酷狗本轮搜索链路 0 命中。  
2. 因此即使用多别名命中目录，**仍可能没有任何 Provider 返回正文** → 需要 ASR/音频草稿分支（已设计未实现）。  
3. 全样本：网易云 track 20/20、lyric 18/20、tlyric 18/20；QQ track 20/20、lyric 19/20（少量需 Cookie）；酷狗 0。  
4. cold（LRCLIB 失败 4 首）：网易云 lyric 2、QQ lyric 3、酷狗 0。  
5. **第一家实验 Provider 选择：网易云**（综合 LRC+翻译覆盖与较低 Cookie 依赖）。QQ 作为 cold 第二候选；酷狗本轮不进。  
6. 错配风险：宽松搜索会拉到同艺人其他曲（如 `そらんじ` 探针首条曾偏到别曲）→ **必须 SafeMatcher + 时长**。

