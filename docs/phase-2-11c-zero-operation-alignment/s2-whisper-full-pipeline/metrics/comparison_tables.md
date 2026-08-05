## sampleA

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 25 | 9 | 10 |
| token 命中率 | 0.188 | 0.406 | 0.406 |
| S3A coverage | 0.188 | 0.312 | 0.312 |
| S3A resolved | 4 | 9 | 10 |
| S3B anchors | 4 | 7 | 9 |
| S3B coverage | 0.188 | 0.281 | 0.312 |
| median error | n/a | n/a | n/a |
| >3s mismatch | 0 | 0 | 0 |
| merger suggestions | 4 | 8 | 10 |
| wrong suggestions | 0 | 0 | 0 |
| elapsed (speech) | 1.13s | 1.73s | 5.01s |
| peak RSS | 27MB | 859MB | 2217MB |
| model size | 0 | 488MB | 1534MB |

## sampleB

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 27 | 14 | 15 |
| token 命中率 | 0.026 | 0.146 | 0.152 |
| S3A coverage | 0.252 | 0.185 | 0.185 |
| S3A resolved | 35 | 23 | 25 |
| S3B anchors | 0 | 5 | 9 |
| S3B coverage | 0.252 | 0.106 | 0.093 |
| median error | n/a | n/a | n/a |
| >3s mismatch | 0 | 0 | 0 |
| merger suggestions | 0 | 7 | 10 |
| wrong suggestions | 0 | 0 | 0 |
| elapsed (speech) | 2.30s | 2.13s | 5.23s |
| peak RSS | 30MB | 891MB | 2253MB |
| model size | 0 | 488MB | 1534MB |

## sampleC

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 161 | 16 | 16 |
| token 命中率 | 1.000 | 1.000 | 1.000 |
| S3A coverage | 1 | 0.969 | 0.938 |
| S3A resolved | 28 | 15 | 14 |
| S3B anchors | 29 | 0 | 0 |
| S3B coverage | 1 | 0.969 | 0.938 |
| median error | n/a | n/a | n/a |
| >3s mismatch | 0 | 0 | 0 |
| merger suggestions | 29 | 0 | 0 |
| wrong suggestions | 0 | 0 | 0 |
| elapsed (speech) | 2.10s | 3.89s | 8.98s |
| peak RSS | 31MB | 917MB | 2239MB |
| model size | 0 | 488MB | 1534MB |

## sampleD

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| transcript pieces | 21 | 1 | 1 |
| token 命中率 | 1.000 | 1.000 | 1.000 |
| S3A coverage | 0.833 | 0.167 | 0.167 |
| S3A resolved | 3 | 0 | 0 |
| S3B anchors | 3 | 0 | 0 |
| S3B coverage | 0.500 | 0.167 | 0.167 |
| median error | n/a | n/a | n/a |
| >3s mismatch | 0 | 0 | 0 |
| merger suggestions | 3 | 0 | 0 |
| wrong suggestions | 0 | 0 | 0 |
| elapsed (speech) | 0.68s | 0.71s | 1.79s |
| peak RSS | 27MB | 858MB | 2252MB |
| model size | 0 | 488MB | 1534MB |

## 汇总

| 指标 | Apple | Whisper small | Whisper medium |
|---|---:|---:|---:|
| 平均 suggestions | 9 | 3.750 | 5 |
| 平均建议覆盖率 | 0.383 | 0.074 | 0.095 |
| 平均错误建议数 | 0 | 0 | 0 |
| 平均 token 命中率 | 0.553 | 0.638 | 0.640 |
| 平均 S3A coverage | 0.568 | 0.408 | 0.401 |
| 平均 S3B anchors | 9 | 3 | 4.500 |
| 平均 speech elapsed | 1.55s | 2.12s | 5.25s |
| 峰值内存(最大) | 31MB | 917MB | 2253MB |
| 非零建议歌曲数/apple | 3/4 | | |
| 非零建议 (whisper_small) | 2/4 zero=2 |
| 非零建议 (whisper_medium) | 2/4 zero=2 |
