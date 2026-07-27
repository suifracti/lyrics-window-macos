# 运行二进制来源与功能接线验收报告

日期：2026-07-27 22:05–22:13 Asia/Shanghai  
验收人：Codex 运行时验收（非仅合同测试）

## 一、代码与分支

```
pwd: /Users/apple/backup/sptifylyrics
branch: ui-redesign-phase-1
HEAD: 69f41951f0cf4fdd8cb767f0ede600f73a4e9cc8
```

`git log -5 --oneline`：

```
69f4195 Audit Suiyoubi single-track sources; add QQ and ASR paths
58d6372 Wire one-button multi-alias lyrics and NetEase experiment
f11f27a Implement one-button lyrics autocomplete foundations
77c66ec Document JP web lyrics discovery audit for AWA Uta-Net UtaTime
6bad7e7 Design Japanese alias lyrics query and recovery contracts
```

`58d6372` **是 HEAD 祖先**（`git merge-base --is-ancestor 58d6372 HEAD` → YES）。

工作区在验收时干净/仅验收产物（以当时 `git status` 为准）。

## 二、构建与二进制

1. 已结束 SpotifyLyrics 进程。  
2. 原 `DerivedData` 已移走为 `DerivedData.bak.20260727220515`（环境禁止 `rm -rf`）。  
3. 使用：

```bash
xcodebuild -project SpotifyLyrics.xcodeproj -scheme SpotifyLyrics -configuration Debug \
  -derivedDataPath /Users/apple/backup/sptifylyrics/DerivedData \
  build CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES
```

结果：**BUILD SUCCEEDED**

4. 目标 App：

`/Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app`

| 项 | 值 |
|----|-----|
| 主可执行 mtime | 2026-07-27 22:05:55 |
| 主可执行 size | 58832（stub） |
| 实际代码 dylib | `Contents/MacOS/SpotifyLyrics.debug.dylib` **4699360** bytes，mtime 22:05:54 |
| codesign | adhoc（Sign to Run Locally） |
| bundle id | com.spotifylyrics.app |

5. 运行进程确认：

```
PID ... /Users/apple/backup/sptifylyrics/DerivedData/Build/Products/Debug/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics
```

6. **重要干扰项（已处理）**：同 bundle id 曾存在多份 App：

- `~/Library/Developer/Xcode/DerivedData/SpotifyLyrics-.../Debug/SpotifyLyrics.app`（旧 Xcode 路径）
- `backup/sptifylyrics/build/SpotifyLyrics.app`（2026-07-26，**无** QQ/NetEase 字符串）
- 验收前曾观察到 UI 显示 **MockData「夜に駆ける」** 样本歌词 → 极可能是 Mock Preview / 旧会话，**不能**当作 Provider 成功。

已将 `build/` 与 Xcode DerivedData 旧 `.app` 改名为 `.OLD.*`，仅保留用户指定路径。

## 三、App target 编译接线（project.pbxproj Sources）

| 符号/文件 | 在 Sources Build Phase |
|-----------|------------------------|
| LyricsRecoveryOrchestrator.swift | YES |
| NetEaseExperimentalLyricsProvider.swift | YES |
| QQExperimentalLyricsProvider.swift | YES |
| JapaneseKanaGenerator.swift | YES |
| JapaneseRomanizer.swift | YES |
| LocalAudioASRService.swift | YES |
| PlaybackState.autoCompleteLyrics | YES（源码 + dylib 符号） |
| LyricsSessionController.autoComplete | YES |
| UI「自动补全歌词」 | YES（dylib 含 UTF-8 文案；Canvas/菜单） |

dylib 英文字符串确认：`NetEase Experimental`、`QQ Music Experimental`。  
中文 UI 文案 UTF-8 存在于 dylib：`自动补全歌词`、`正在自动补全`、`导入本地音频`、`待对齐时间轴`、`自动补全未找到`、`暂无可用曲库来源`。

### 运行时路径诚实说明

**已写源码且编入 App：**

- `PlaybackState.makeDefaultLyricsProviders` → Local + LRCLIB + NetEase + QQ  
- 切歌/`begin`/`autoCompleteLyrics` → `LyricsSessionController` → `CompositeLyricsProvider` → **`LyricsSearchManager`（多别名）**

**编入但未作为主 UI 路径调用：**

- `LyricsRecoveryOrchestrator`：**在 target 中，但当前 PlaybackState 主路径未调用该类**。主路径是 `LyricsSearchManager`，不是 Orchestrator。

## 四、真实 UI 验证

### 4.1 当前 Spotify 歌曲：あやふや / みさき

运行 App 后无障碍树显示：

- `播放来源：Spotify Desktop 已连接`
- 曲目：`あやふや，みさき`
- 加载中：`正在自动补全歌词…` / `Local → LRCLIB 多别名查询中`（文案未列出网易/QQ，但 provider 链仍包含）
- 结束后：`自动补全未找到歌词` + `noTextSource` + 次级动作：`自动补全歌词`、`导入本地音频 · ASR 草稿`

截图：`acceptance-2026-07-27/ayafuya-notextsource.jpeg`

**结论（あやふや）**：一键流程**有在真实 UI 跑完**，结果 noTextSource **正确**（与网络探针一致：LRCLIB 无、网易空 lrc、QQ retcode -1901）。

### 4.2 「自动补全歌词」是否可见

- **noMatch/noLyrics/failed** 时 Canvas 显示按钮「自动补全歌词」：**是**（あやふや 已见）
- 顶部「播放来源」菜单内也有「自动补全歌词」：**是**（菜单打开后可见）
- **loaded 成功显示歌词时** 主画布不常驻该按钮（合理）
- **没有**「Local / LRCLIB / 网易 / QQ 各自状态列表」的 UI：**未实现**。仅有总状态文案。

### 4.3 水曜日の約束 / Kawasaki.Rio

**同进程 Swift harness（与 App 同源 Provider+Manager+Session）结果**（`runtime-harness-out.txt`）：

| 步骤 | 结果 |
|------|------|
| LRCLIB direct | noMatch |
| NetEase direct | candidates（**错误艺人** Gero 等，conf≈0.45，**不应自动采用**） |
| QQ direct | **match** `qqExperimental` lines=**32** sync=false conf=**0.90** first=`「これでおわり」って言われた夜` song 逻辑 mid 对应审计 `004YkjHH0g5pRt` |
| LyricsSearchManager | **match** QQ，diag：Local noMatch → LRCLIB noMatch → NetEase candidates → **QQ match 0.91s** |
| LyricsSessionController | **alignmentQueued**，lines=32，first 同上 |

**真实 Spotify 播放该曲并点 UI 的截图验收**：本次验收窗口 Spotify 当前曲为 **あやふや**，未切换到 Kawasaki.Rio，故 **不能** 声称「已在真实 Spotify 曲目 UI 上显示该词」。

但：**同源代码链已证明 Provider→Manager→Session 可对 Kawasaki.Rio 产出 32 行正文**。若 UI 仍空白，优先查：是否播了 HoneyWorks 同名曲、是否旧 `.app`、是否仍在 Mock Preview。

### 4.4 对照曲 Lemon / 米津玄師（网络+harness）

- LRCLIB：**match** synced conf 0.85  
- NetEase：有正文 candidates  
- QQ：**match** synced conf 1.00  

未在本轮强制 Spotify 切到 Lemon 做 UI 截图。

### 4.5 播放位置

自动补全过程不调用 seek；验收中 slider 保持用户位置（あやふや 约 00:10）。无证据表明补全会改 Spotify 进度。

## 五、搜索能力实际是什么

搜索弹层真实文案：

> 「搜索仅通过 Spotify 当前歌曲、本地歌词目录和 LRCLIB 返回统一结果」

（文案仍偏旧；架构上 track search 是 **Local + CurrentTrack**，LRCLIB 不在 track search manager。）

| 能力 | 当前 App |
|------|----------|
| 当前 Spotify 歌曲重新搜词 | **有**（切歌自动 begin / 自动补全） |
| 本地歌词/曲目搜索 | **有**（Local index） |
| 在线歌曲目录搜索（任意关键词曲库） | **无**（无 Spotify Web OAuth / 无在线 catalog provider） |
| 在线歌词 Provider 搜索 | **有**（LRCLIB + 网易实验 + QQ 实验，挂在**歌词**链路，不是曲库搜索） |

**不得**声称支持任意关键词在线歌曲搜索。

截图：`acceptance-2026-07-27/search-popover.jpeg`

## 六、最终结论矩阵

| 项 | 自动补全整体 | QQ 对 Kawasaki.Rio | あやふや |
|----|--------------|--------------------|---------|
| 已写源码 | YES | YES | YES |
| 已进入 App target | YES | YES | YES |
| 已在真实运行界面出现（按钮/状态） | **部分 YES**（noMatch 态可见；无 per-provider 面板） | **未在该曲 Spotify UI 截到成功页** | YES（noTextSource） |
| 已对真实歌曲成功请求 | harness YES / UI あやふや YES | harness YES | YES（各源无正文） |
| **已把歌词显示出来** | **未完成总声称** | **harness Session 有 32 行；直播 Spotify 曲 UI 未验收成功显示** | **正确不显示**（无正文） |

### 总判定

1. 你看到的「两首都没词 / 没有一键功能」**很可能混入了 Mock Preview 或旧 `build/SpotifyLyrics.app`**。  
2. **新二进制确实包含** QQ/NetEase/自动补全文案与符号。  
3. **あやふや**：真实 UI 一键流程跑通 → noTextSource（符合数据现实）。  
4. **水曜日の約束/Kawasaki.Rio**：同源 harness **已成功** QQ 32 行并 `alignmentQueued`；**不能**在未切换 Spotify 到该曲时说 UI 已显示。  
5. **不能**根据合同测试 alone 宣称“最终 App 一键补全完成”。  
6. **可以**说：代码已进 target；あやふや UI 行为正确；Kawasaki 管道在运行时 harness 级通过；**最终 UI 对 Kawasaki 的显示仍欠一次真机切曲验收**。  
7. 搜索：**不是**任意在线曲库搜索。

## 七、阻塞/产品缺口（验收发现）

1. 同 bundle id 多副本 → 用户易开错 App。  
2. Mock Preview 与真曲 UI 易混淆（Mock 也用夜に駆ける）。  
3. 加载文案只写 `Local → LRCLIB`，**未展示网易/QQ 执行状态**。  
4. `LyricsRecoveryOrchestrator` 未接线到主 UI。  
5. 搜索文案仍提 LRCLIB 统一结果，与 track/lyrics 拆分不完全一致。  
6. 多别名 × 多 Provider 首次加载较慢（あやふや有明显 loading）。

## 八、建议下一步（仅验收后续，非本报告范围）

1. 在 Spotify 手动切到 **水曜日の約束 / Kawasaki.Rio**，只开本报告路径 App，点「自动补全歌词」，截图是否出现 32 行 / 待对齐。  
2. 启动时检测 Mock 并显著角标「Mock Preview」。  
3. 加载态改为 per-provider 状态条。  
4. 删除/停用 `build/SpotifyLyrics.app` 与多余 DerivedData 副本。  
