# S3B Anchor-Constrained Partial Alignment Report

- session: `404F9F32-7C7A-4B2C-B43E-E254CFEBD2FE`
- identity: `spotify-id:7ovucf5uhtbrzupb6zomvt|metadata:アイドル|`
- locale: `ja-JP` fallback: none
- capturedDuration: 75.396 s
- transcriptSegments: 83
- judgment: **C_insufficient_reliable_anchors**
- usedConstrainedAlignment: true
- s3bFallbackReason: none
- acceptedAnchors: 8
- rejectedAnchors: 39

## A/B comparison (same capture + plain lyrics)

| metric | S3A | S3B |
|---|---:|---:|
| resolved | 45 | 16 |
| lowConfidence | 5 | 4 |
| unresolved | 13 | 44 |
| outsideCapturedRange | 88 | 87 |
| coverageRatio | 0.331 | 0.132 |
| overallConfidence | 0.067 | 0.422 |
| acceptedAnchors | 0 (n/a) | 8 |
| rejectedAnchors | 0 (n/a) | 39 |

## Held-out errors (S3B primary)

- compared: 20
- medianAbsErr: 0.784
- p90: 4.459
- p95: 5.449
- mean: 1.749
- ≤0.5s: 5
- ≤1s: 12
- ≤2s: 14
- obviousMismatch(>3s): 5
- note: held_out_start_time_abs_error_seconds

## Held-out errors (S3A baseline)

- compared: 50
- medianAbsErr: 1.622
- p90: 4.516
- p95: 4.855
- mean: 1.904
- ≤0.5s: 8
- ≤1s: 20
- ≤2s: 30
- obviousMismatch(>3s): 11
- note: held_out_start_time_abs_error_seconds

## Accepted anchors
- line=7 t=10.111-11.551 conf=0.759 textSim=0.789 lyric=完璧で嘘つきな君は speech=嘘つきな君は evidence=textSim=0.789;speech=0.636;window=0-3
- line=13 t=13.231-17.401 conf=0.800 textSim=1.000 lyric=今日何食べた？ speech=今日何食べた evidence=textSim=1.000;speech=0.000;window=8-10
- line=14 t=17.401-18.061 conf=0.800 textSim=1.000 lyric=好きな本は？ speech=好きな本は evidence=textSim=1.000;speech=0.000;window=11-13
- line=19 t=19.561-20.341 conf=0.800 textSim=1.000 lyric=何も食べてない speech=何も食べてない evidence=textSim=1.000;speech=0.000;window=21-23
- line=21 t=20.341-20.821 conf=0.800 textSim=1.000 lyric=それは内緒 speech=それは内緒 evidence=textSim=1.000;speech=0.000;window=24-25
- line=22 t=20.821-21.901 conf=0.800 textSim=1.000 lyric=何を聞かれても speech=何を聞かれても evidence=textSim=1.000;speech=0.000;window=26-29
- line=24 t=21.901-22.471 conf=0.800 textSim=1.000 lyric=のらりくらり speech=のらりくらり evidence=textSim=1.000;speech=0.000;window=30-30
- line=50 t=54.631-57.271 conf=0.754 textSim=0.794 lyric=誰もが目を奪われていく speech=誰も目を奪われて evidence=textSim=0.794;speech=0.594;window=55-59

## Rejected anchors (first 30)
- line=13 reason=overall_confidence_below_threshold conf=0.688 textSim=0.789 lyric=今日何食べた？ speech=な愛様今日何食べた
- line=13 reason=overall_confidence_below_threshold conf=0.717 textSim=0.849 lyric=今日何食べた？ speech=愛様今日何食べた
- line=13 reason=text_similarity_below_threshold conf=0.615 textSim=0.738 lyric=今日何食べた？ speech=様今日何食べた好きな
- line=13 reason=overall_confidence_below_threshold conf=0.631 textSim=0.789 lyric=今日何食べた？ speech=今日何食べた好きな
- line=13 reason=text_similarity_below_threshold conf=0.590 textSim=0.738 lyric=今日何食べた？ speech=今日何食べた好きな本
- line=13 reason=overall_confidence_below_threshold conf=0.626 textSim=0.782 lyric=今日何食べた？ speech=何食べた
- line=14 reason=text_similarity_below_threshold conf=0.604 textSim=0.755 lyric=好きな本は？ speech=食べた好きな本は
- line=14 reason=overall_confidence_below_threshold conf=0.702 textSim=0.878 lyric=好きな本は？ speech=好きな本
- line=14 reason=overall_confidence_below_threshold conf=0.657 textSim=0.822 lyric=好きな本は？ speech=好きな本は遊び
- line=14 reason=text_similarity_below_threshold conf=0.604 textSim=0.755 lyric=好きな本は？ speech=好きな本は遊びに
- line=17 reason=text_similarity_below_threshold conf=0.594 textSim=0.742 lyric=遊びに行くならどこに行くの？ speech=遊びに行くとこに行く
- line=19 reason=text_similarity_below_threshold conf=0.614 textSim=0.768 lyric=何も食べてない speech=に行くの何も食べてない
- line=19 reason=overall_confidence_below_threshold conf=0.652 textSim=0.815 lyric=何も食べてない speech=行くの何も食べてない
- line=19 reason=text_similarity_below_threshold conf=0.604 textSim=0.755 lyric=何も食べてない speech=の何も食べて
- line=19 reason=text_similarity_below_threshold conf=0.614 textSim=0.768 lyric=何も食べてない speech=の何も食べてないそれは
- line=19 reason=overall_confidence_below_threshold conf=0.657 textSim=0.822 lyric=何も食べてない speech=何も食べて
- line=19 reason=overall_confidence_below_threshold conf=0.652 textSim=0.815 lyric=何も食べてない speech=何も食べてないそれは
- line=19 reason=overall_confidence_below_threshold conf=0.657 textSim=0.822 lyric=何も食べてない speech=食べてない
- line=21 reason=overall_confidence_below_threshold conf=0.657 textSim=0.822 lyric=それは内緒 speech=ないそれは内緒
- line=21 reason=text_similarity_below_threshold conf=0.604 textSim=0.755 lyric=それは内緒 speech=ないそれは内緒何
- line=21 reason=overall_confidence_below_threshold conf=0.657 textSim=0.822 lyric=それは内緒 speech=それは内緒何を
- line=22 reason=overall_confidence_below_threshold conf=0.631 textSim=0.789 lyric=何を聞かれても speech=内緒何を聞かれて
- line=22 reason=overall_confidence_below_threshold conf=0.695 textSim=0.869 lyric=何を聞かれても speech=内緒何を聞かれても
- line=22 reason=overall_confidence_below_threshold conf=0.657 textSim=0.822 lyric=何を聞かれても speech=を聞かれて
- line=22 reason=overall_confidence_below_threshold conf=0.657 textSim=0.822 lyric=何を聞かれても speech=聞かれても
- line=24 reason=text_similarity_below_threshold conf=0.624 textSim=0.738 lyric=のらりくらり speech=のらりくらり見えない
- line=32 reason=overall_confidence_below_threshold conf=0.669 textSim=0.789 lyric=あれもないないない speech=ないないない
- line=34 reason=text_similarity_below_threshold conf=0.630 textSim=0.740 lyric=これもないないない speech=ないないないこれも
- line=34 reason=text_similarity_below_threshold conf=0.626 textSim=0.740 lyric=これもないないない speech=ないないこれもない
- line=50 reason=text_similarity_below_threshold conf=0.734 textSim=0.778 lyric=誰もが目を奪われていく speech=誰も目を奪われてくる

## S3B lines (first 40)
- [0] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange 無敵の笑顔で荒らすメディア
- [1] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Muteki no egao de arasu media
- [2] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Shiritai sono himitsu misuteriasu
- [3] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange 知りたいその秘密ミステリアス
- [4] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Nuketeru toko sae kanojo no eria
- [5] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange 抜けてるとこさえ彼女のエリア
- [6] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Kanpeki de usotsuki na kimi wa
- [7] resolved t=10.111 conf=0.759 kind=anchor 完璧で嘘つきな君は
- [8] unresolved t=- conf=0.000 kind=s3b-region-unresolved Tensaitekina aidoru sama
- [9] unresolved t=- conf=0.000 kind=s3b-region-unresolved 天才的なアイドル様
- [10] unresolved t=- conf=0.000 kind=s3b-region-unresolved (You're my savior, you're my saving 
- [11] unresolved t=- conf=0.000 kind=s3b-region-unresolved (You're my savior, you're my saving 
- [12] unresolved t=- conf=0.000 kind=s3b-region-unresolved Kyou nani tabeta?
- [13] resolved t=13.231 conf=0.800 kind=anchor 今日何食べた？
- [14] resolved t=17.401 conf=0.800 kind=anchor 好きな本は？
- [15] unresolved t=- conf=0.000 kind=s3b-region-unresolved Suki na hon wa?
- [16] unresolved t=- conf=0.000 kind=s3b-region-unresolved Asobi ni iku nara doko ni iku no?
- [17] unresolved t=- conf=0.000 kind=s3b-region-unresolved 遊びに行くならどこに行くの？
- [18] unresolved t=- conf=0.000 kind=s3b-region-unresolved Nanimo tabetenai,
- [19] resolved t=19.561 conf=0.800 kind=anchor 何も食べてない
- [20] unresolved t=- conf=0.000 kind=s3b-noEvidence sore wa naisho
- [21] resolved t=20.341 conf=0.800 kind=anchor それは内緒
- [22] resolved t=20.821 conf=0.800 kind=anchor 何を聞かれても
- [23] unresolved t=- conf=0.000 kind=s3b-noEvidence Nani wo kikaretemo
- [24] resolved t=21.901 conf=0.800 kind=anchor のらりくらり
- [25] unresolved t=- conf=0.000 kind=s3b-region-unresolved norari kurari
- [26] unresolved t=- conf=0.000 kind=s3b-region-unresolved Sou tantan to
- [27] unresolved t=- conf=0.000 kind=s3b-region-unresolved そう淡々と
- [28] unresolved t=- conf=0.000 kind=s3b-region-unresolved だけど燦々と
- [29] unresolved t=- conf=0.000 kind=s3b-region-unresolved dakedo sansan to
- [30] unresolved t=- conf=0.000 kind=s3b-region-unresolved Miesou de mienai himitsu wa mitsu no
- [31] unresolved t=- conf=0.000 kind=s3b-region-unresolved 見えそうで見えない秘密は蜜の味
- [32] lowConfidence t=32.401 conf=0.563 kind=s3b-region-directSpeech あれもないないない
- [33] interpolated t=34.006 conf=0.000 kind=s3b-region-boundedInterpolation Are mo nai, nai, nai
- [34] lowConfidence t=35.611 conf=0.464 kind=s3b-region-directSpeech これもないないない
- [35] interpolated t=36.253 conf=0.000 kind=s3b-region-boundedInterpolation kore mo nai, nai, nai
- [36] interpolated t=36.894 conf=0.000 kind=s3b-region-boundedInterpolation 好きなタイプは？
- [37] interpolated t=37.535 conf=0.000 kind=s3b-region-boundedInterpolation Suki na taipu wa?
- [38] interpolated t=38.176 conf=0.000 kind=s3b-region-boundedInterpolation Aite wa?
- [39] interpolated t=38.818 conf=0.000 kind=s3b-region-boundedInterpolation 相手は？

## S3A lines (first 40)
- [0] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange 無敵の笑顔で荒らすメディア
- [1] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Muteki no egao de arasu media
- [2] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Shiritai sono himitsu misuteriasu
- [3] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange 知りたいその秘密ミステリアス
- [4] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Nuketeru toko sae kanojo no eria
- [5] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange 抜けてるとこさえ彼女のエリア
- [6] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange Kanpeki de usotsuki na kimi wa
- [7] outsideCapturedRange t=- conf=0.000 kind=outsideCapturedRange 完璧で嘘つきな君は
- [8] unresolved t=- conf=0.000 kind=noEvidence Tensaitekina aidoru sama
- [9] unresolved t=- conf=0.000 kind=noEvidence 天才的なアイドル様
- [10] unresolved t=- conf=0.000 kind=noEvidence (You're my savior, you're my saving 
- [11] unresolved t=- conf=0.000 kind=noEvidence (You're my savior, you're my saving 
- [12] unresolved t=- conf=0.000 kind=noEvidence Kyou nani tabeta?
- [13] unresolved t=- conf=0.000 kind=noEvidence 今日何食べた？
- [14] unresolved t=- conf=0.000 kind=noEvidence 好きな本は？
- [15] unresolved t=- conf=0.000 kind=noEvidence Suki na hon wa?
- [16] unresolved t=- conf=0.000 kind=noEvidence Asobi ni iku nara doko ni iku no?
- [17] unresolved t=- conf=0.000 kind=noEvidence 遊びに行くならどこに行くの？
- [18] unresolved t=- conf=0.000 kind=noEvidence Nanimo tabetenai,
- [19] lowConfidence t=19.471 conf=0.442 kind=directSpeech 何も食べてない
- [20] interpolated t=19.957 conf=0.000 kind=boundedInterpolation sore wa naisho
- [21] interpolated t=20.443 conf=0.000 kind=boundedInterpolation それは内緒
- [22] interpolated t=20.929 conf=0.000 kind=boundedInterpolation 何を聞かれても
- [23] interpolated t=21.415 conf=0.000 kind=boundedInterpolation Nani wo kikaretemo
- [24] resolved t=21.901 conf=0.780 kind=directSpeech のらりくらり
- [25] interpolated t=23.214 conf=0.000 kind=boundedInterpolation norari kurari
- [26] interpolated t=24.526 conf=0.000 kind=boundedInterpolation Sou tantan to
- [27] interpolated t=25.839 conf=0.000 kind=boundedInterpolation そう淡々と
- [28] interpolated t=27.151 conf=0.000 kind=boundedInterpolation だけど燦々と
- [29] interpolated t=28.464 conf=0.000 kind=boundedInterpolation dakedo sansan to
- [30] interpolated t=29.776 conf=0.000 kind=boundedInterpolation Miesou de mienai himitsu wa mitsu no
- [31] interpolated t=31.089 conf=0.000 kind=boundedInterpolation 見えそうで見えない秘密は蜜の味
- [32] lowConfidence t=32.401 conf=0.563 kind=directSpeech あれもないないない
- [33] interpolated t=34.006 conf=0.000 kind=boundedInterpolation Are mo nai, nai, nai
- [34] lowConfidence t=35.611 conf=0.464 kind=directSpeech これもないないない
- [35] interpolated t=36.253 conf=0.000 kind=boundedInterpolation kore mo nai, nai, nai
- [36] interpolated t=36.894 conf=0.000 kind=boundedInterpolation 好きなタイプは？
- [37] interpolated t=37.535 conf=0.000 kind=boundedInterpolation Suki na taipu wa?
- [38] interpolated t=38.176 conf=0.000 kind=boundedInterpolation Aite wa?
- [39] interpolated t=38.818 conf=0.000 kind=boundedInterpolation 相手は？