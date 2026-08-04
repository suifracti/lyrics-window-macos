# 酷狗（KuGou）实验源审计结论

**日期：** 2026-08-04  
**范围：** `/Users/apple/backup/sptifylyrics/SpotifyLyrics` 应用源码（不含 `其他仓库参考/`）

## 结论

**不实现酷狗 Provider。**

## 证据

1. 在 `SpotifyLyrics/**/*.swift` 中搜索 `Kugou` / `KuGou` / `kugou`：**无匹配**。
2. `LyricsProviderID` 仅包含：`localFiles`、`sqliteDatabase`、`lrclib`、`netEaseExperimental`、`qqExperimental`。
3. 仓库文档（`SOURCE_PROVIDER_RESEARCH.md`）与第三方参考项目（LyricsX 等）提到酷狗，但本应用**未复制**其实现，也未持有密钥或私有凭证。
4. 合同测试 `Tests/lyrics_source_mode_contract.sh` 明确拒绝应用源中出现酷狗符号。

## 风险说明

酷狗公开歌词接口在常见开源实现中依赖非官方/易变端点，且往往涉及第三方密钥或逆向会话。在未满足「无需付费、无私有凭证、无复制第三方密钥、风险明确」四条件时，不得作为实验 Provider 上线。

## 产品状态

- 方案 A / 方案 B 均**不**包含酷狗。
- 扩展免费实验模式仅额外开放已有的 **网易实验源** 与 **QQ 实验源**。
