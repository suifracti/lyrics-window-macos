# 水曜日の約束 / Kawasaki.Rio — 真实 App UI 端到端验收

## 环境
- App: `/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`
- Spotify track: `spotify:track:5MqkkCSrUjqyaKVOlvEn0w`
- 曲目: 水曜日の約束 / Kawasaki.Rio / duration≈171.177s
- HEAD rebuild after: remove dead Orchestrator; Session→LyricsSearchManager; fix E2E log deadlock

## 修复（验收中发现并修）
1. **`LyricsE2ELog.reset()` 死锁**：持 `NSLock` 时再调 `log()` → App 初始化卡死，UI 不更新、无日志。已改为非递归写。
2. **删除假接线**：移除 `LyricsRecoveryOrchestrator`（未接主路径）。主路径明确为  
   `PlaybackState` → `LyricsSessionController` → **`LyricsSearchManager`** → Local/LRCLIB/NetEase/QQ。

## 每层状态日志（`/tmp/spotifylyrics-e2e.log`）

```
PlaybackState init providers=Local LRC,LRCLIB,NetEase Experimental,QQ Music Experimental
Playback trackChange ... title=水曜日の約束 artist=Kawasaki.Rio duration=171.177
SESSION begin rev=1 ...
MANAGER start ... variants=2 providers=[Local LRC, LRCLIB, NetEase Experimental, QQ Music Experimental]
QQ best mid-candidate title=水曜日の約束 artist=Kawasaki.Rio conf=1.0 lines=32 sync=false
QQ MATCH lines=32 conf=1.0 first=「これでおわり」って言われた夜
MANAGER AUTO_ADOPT provider=QQ Music Experimental strategy=primaryOriginal tier=autoHigh score≈0.98 lines=32 sync=false
SESSION search finished result=match(qqExperimental,lines=32,sync=false)
  DIAG Local LRC@primaryOriginal noMatch
  DIAG LRCLIB@primaryOriginal noMatch
  DIAG NetEase Experimental@primaryOriginal candidates(3)   # 错误艺人候选，未自动采用
  DIAG QQ Music Experimental@primaryOriginal match
SESSION apply alignmentQueued source=qqExperimental lines=32 first=「これでおわり」って言われた夜
```

## UI 验收（辅助功能树 + 截图）

截图: `ui-alignment-queued-lyrics.jpeg`

可见：
- 标题/艺人：`水曜日の約束，Kawasaki.Rio`
- 歌词列表含：`「これでおわり」って言われた夜` + 罗马音等
- 底部：`待对齐时间轴`（无可靠时间轴，不伪造同步高亮）
- 播放进度约 `01:11 / 02:51`（自然播放，非歌词 seek 重置）

## 播放位置
- 自动补全链路 **无 seek 调用**
- Spotify 进度随播放自然前进（验收时约 25s→32s→71s），**未跳回 0**

## 结论

| 检查项 | 结果 |
|--------|------|
| Spotify 实际播放该曲 | YES |
| 正确 DerivedData App | YES |
| QQ 32 行经 Manager→Session→SwiftUI | **YES** |
| 无轴：全文 + 待对齐时间轴 | **YES** |
| 不伪造同步滚动 | YES（isSynchronized=false） |
| 不改播放位置 | YES |
| Orchestrator 假接线 | **已删除**，主路径为 LyricsSearchManager |
