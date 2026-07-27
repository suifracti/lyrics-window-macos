# 水曜日の約束：时长不匹配验收记录

## 结论

此前“32 行已排轴并保存”的验收无效。它使用的 `kawasaki_tts.wav` 是约 **79.8255 秒**的合成语音测试夹具，而 Spotify 当前播放的「水曜日の約束 / Kawasaki.Rio」时长是 **171.177 秒（2:51）**。因此旧结果在约 1:18 结束，并且可能在真实歌曲歌手开口前显示歌词；它不是该歌曲的有效时间轴。

已将旧的错误 `.aligned.lrc` 移出用户歌词目录，避免只读本地索引继续加载它。旧的预览/确认截图也不再作为验收证据保留。

## 修复

- `AlignmentDurationValidator` 在语音识别前比较本地音频与当前 Track 时长。
- 允许小幅片头/片尾差异（10%，且至少 8 秒），拒绝明显不同的音频。
- 时长不匹配时抛出明确错误，不生成、不保存、不覆盖同步歌词。
- 前置未匹配歌词行不再插值到第一条真实识别证据之前，避免歌手尚未开口时歌词开始移动。
- UI 保持 QQ 返回的 32 行纯文本，并显示“待对齐时间轴”和具体失败原因。

## 真实 App 证据

- 运行二进制：`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`
- 运行身份：`spotify:track:5MqkkCSrUjqyaKVOlvEn0w`
- App 日志：`align_e2e_run.log`
- 截图：`app-duration-mismatch-queued.jpg`
- 关键结果：`UI align failed 所选音频时长 79.8 秒与当前歌曲 171.2 秒不匹配，未生成时间轴`
- 本地结果：`~/Music/SpotifyLyrics/Lyrics/Kawasaki.Rio - 水曜日の約束.aligned.lrc` 不存在

## 当前未验证项

这次验证证明了错误夹具会被拒绝，但没有对应的 171 秒真实本地音频，因此不能声称该歌曲已经生成了有效逐行时间轴。下一次成功验收必须使用与当前播放版本相符的完整本地音频；不能用 TTS 夹具替代。
