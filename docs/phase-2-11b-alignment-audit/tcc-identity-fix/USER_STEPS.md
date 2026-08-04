# TCC Identity Fix — 用户操作步骤

## 当前状态（2026-08-04）

| 项 | 状态 |
|---|---|
| 只读审计 | 完成 → `AUDIT.md` |
| Debug 签名配置骨架 | 已写入项目（Automatic + `ENABLE_DEBUG_DYLIB=NO`） |
| 本机 `Apple Development` 证书 | **无（0 identities）** |
| 稳定签名构建 | **暂停** — 需要你先登录 Apple Account |

**禁止**用 ad-hoc（`CODE_SIGN_IDENTITY = "-"`）冒充本阶段修复。

---

## A. 在 Xcode 中登录并创建开发证书

1. 打开 **Xcode 26**
2. **Xcode → Settings…（设置）→ Accounts**
3. 点 **+** → **Apple ID** → 登录你的 Apple 账号  
   - 免费 Apple ID 即可（Personal Team）
4. 选中账号 → 右侧应出现 **Personal Team**（或付费开发者 Team）
5. 若提示创建证书：允许 Xcode **Manage Certificates… → + → Apple Development**
6. 在终端验证：

```bash
security find-identity -v -p codesigning
```

至少应看到一行类似：

```text
1) … "Apple Development: your@email (XXXXXXXX)"
```

若仍是 `0 valid identities found`，**不要继续构建**，先解决账号/证书。

---

## B. 配置本机 Team ID（不提交仓库）

1. 查 Team ID：  
   Xcode → Settings → Accounts → 选 Team → **Team ID**（10 位字母数字）
2. 在项目中复制：

```bash
cd /Users/apple/backup/sptifylyrics
cp SpotifyLyrics/Config/DebugSigning.local.xcconfig.example \
   SpotifyLyrics/Config/DebugSigning.local.xcconfig
```

3. 编辑 `DebugSigning.local.xcconfig`：

```text
DEVELOPMENT_TEAM = 你的10位TeamID
```

该文件已在 `.gitignore` 中，**不会也不应提交**。

---

## C. 完成 B 后由代理继续（你回复「账号已就绪」）

代理将：

1. Debug `xcodebuild` **一次**
2. 证明签名 **非 adhoc**、有 **TeamIdentifier**、无 **`.debug.dylib`**
3. 给出重新授权 TCC 的精确步骤
4. 你确认授权后跑 **最小 STREAM started 探针**
5. **不**自动跑样本 A/B 全量验收

---

## D. 授权后（构建冻结后才做）— 预告

1. 完全退出 Lyric Island / SpotifyLyrics  
2. 系统设置 → 隐私与安全性 → **屏幕与系统音频录制**  
3. 删除旧的 `SpotifyLyrics` / `com.spotifylyrics.app` 条目（若有）  
4. 启动**新签名**的 Debug App（路径会在构建报告中给出）  
5. 允许屏幕与系统音频  
6. 退出并再启动一次  
7. 再跑捕获探针  

---

## SwiftUI Preview 影响（`ENABLE_DEBUG_DYLIB=NO`）

- 仅 **SpotifyLyrics App Target · Debug** 关闭 debug dylib  
- 主程序变为**单 executable**，利于 TCC  
- **SwiftUI Previews** 可能变慢或需用 Canvas 的独立进程；不影响真机/本机 App 运行  
- **不**全局关闭 workspace 其它 target 的 dylib  

---

## Release

**未改** Release 的 `CODE_SIGN_IDENTITY = "-"` 与策略。
