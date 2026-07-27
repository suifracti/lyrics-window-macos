# 一键兜底：ASR 歌词草稿（设计）

> 状态：设计保留接口；本轮不实现最终 ASR/排轴。  
> 原则：全部 Provider 无词后才进入；**不是**网页复制主流程。

## 触发

```
autoComplete exhausted (Local + LRCLIB + experimental + licensed)
→ 检查合法可分析音频
   → 无音频：显示「当前没有可自动获取的歌词或音频」
   → 有音频：ASR 草稿管线
```

## 音频来源（候选，需合法）

1. 用户导入的本地音轨（用户拥有/授权）  
2. 未来：系统已购内容导出（若 API 允许）  
3. **不做**：破解 Spotify DRM / 盗录受保护流  

## 管线

```
AudioAsset
→ ASR (ja preferred; whisper/local or on-device)
→ 日语文本清洗与分行
→ 官方/Provider 假名优先，否则词典读音
→ 罗马音 Hepburn ASCII
→ 自动逐行对齐（alignment engine）
→ 保存 LyricsDocument
   source: machineGenerated
   flags: needsReview=true
   locks: all unlocked
```

## 状态

`LyricsRecoveryState` / `LyricsAutoCompletePhase` 增加：

- `asrQueued`
- `asrRunning`
- `asrDraftReady`
- `asrFailedNoAudio`
- `asrFailedEngine`

## UI

- 一键自动补全失败后展示次级按钮「用本地音频生成草稿」  
- 草稿水印：机器生成、待校正  
- 不自动覆盖已锁定人工歌词  

## 非目标（本轮）

- 不接具体 ASR SDK  
- 不实现强制对齐算法  
- 不静默上传音频到第三方  
