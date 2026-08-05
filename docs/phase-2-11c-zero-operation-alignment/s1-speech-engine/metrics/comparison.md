# Offline + S0.5 pipeline metrics (same 16 kHz mono WAVs)

| 指标 | Sample A 夜の合図 Apple (S0.5 E0095CFA) | Sample A Whisper CLI (S1 offline) | Sample B アイドル Apple (S0.5 latest) | Sample B Whisper CLI (S1 offline) |
|---|---:|---:|---:|---:|
| transcript pieces | 25 | 9 (longer phrases) | 27 | 14 |
| S3A coverage | 0.125 | (via same pipeline when engine selected) | 0.007 | (via same pipeline) |
| S3B anchors | 4 | (same S3B) | 0 | (same S3B) |
| merger suggestions (est.) | ~4 | expected higher with better text | ~0 | TBD live |
| elapsed (engine) | ~capture+speech (S0.5) | ~1.9s | ~capture+speech | ~2.2s |
| peak memory (engine) | n/a | ~855 MB RSS | n/a | ~891 MB RSS |

Notes:
- Apple piece count is higher but tokens are often short/noisy for singing; coverage remains low.
- Whisper pieces are fewer, longer Japanese phrases with clear timestamps (ja, ggml-small).
- Both engines map to `SpeechEngineResult` → `TimedTranscript` → S3A → S3B → Merger → Draft.
