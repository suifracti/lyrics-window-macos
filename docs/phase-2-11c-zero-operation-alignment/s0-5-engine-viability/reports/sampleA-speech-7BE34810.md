# S3B Anchor-Constrained Partial Alignment Report

- session: `7BE34810-D568-48E0-B1E6-B7FA4CE4734C`
- identity: `spotify-id:0662h3g9lgdt2vipzypzxm|metadata:夜の合図|`
- locale: `ja-JP` fallback: none
- capturedDuration: 44.988 s
- transcriptSegments: 30
- judgment: **B_coverage_up_but_errors_remain**
- usedConstrainedAlignment: true
- s3bFallbackReason: none
- acceptedAnchors: 2
- rejectedAnchors: 14

## A/B comparison (same capture + plain lyrics)

| metric | S3A | S3B |
|---|---:|---:|
| resolved | 0 | 2 |
| lowConfidence | 2 | 1 |
| unresolved | 30 | 29 |
| outsideCapturedRange | 0 | 0 |
| coverageRatio | 0.062 | 0.094 |
| overallConfidence | 0.628 | 0.793 |
| acceptedAnchors | 0 (n/a) | 2 |
| rejectedAnchors | 0 (n/a) | 14 |

## Held-out errors (S3B primary)

- compared: 0
- medianAbsErr: n/a
- p90: n/a
- p95: n/a
- mean: n/a
- ≤0.5s: 0
- ≤1s: 0
- ≤2s: 0
- obviousMismatch(>3s): 0
- note: no_held_out_synced_lyrics

## Held-out errors (S3A baseline)

- compared: 0
- medianAbsErr: n/a
- p90: n/a
- p95: n/a
- mean: n/a
- ≤0.5s: 0
- ≤1s: 0
- ≤2s: 0
- obviousMismatch(>3s): 0
- note: no_held_out_synced_lyrics

## Accepted anchors
- line=13 t=76.857-79.017 conf=0.958 textSim=1.000 lyric=時計の針を戻してる speech=時計の針を戻してる evidence=textSim=1.000;speech=0.792;window=5-10
- line=14 t=79.467-81.957 conf=0.824 textSim=1.000 lyric=愛してた　それだけじゃ speech=愛してたそれだけじゃ evidence=textSim=1.000;speech=0.118;window=11-12

## Rejected anchors (first 30)
- line=13 reason=text_similarity_below_threshold conf=0.758 textSim=0.768 lyric=時計の針を戻してる speech=した時計の針を戻し
- line=14 reason=text_similarity_below_threshold conf=0.721 textSim=0.762 lyric=愛してた　それだけじゃ speech=針を戻してる愛してたそれだけじゃ
- line=14 reason=text_similarity_below_threshold conf=0.688 textSim=0.733 lyric=愛してた　それだけじゃ speech=を戻してる愛してたそれだけじゃだめ
- line=14 reason=text_similarity_below_threshold conf=0.699 textSim=0.762 lyric=愛してた　それだけじゃ speech=戻してる愛してたそれだけじゃだめ
- line=14 reason=text_similarity_below_threshold conf=0.611 textSim=0.738 lyric=愛してた　それだけじゃ speech=それだけじゃ
- line=15 reason=text_similarity_below_threshold conf=0.665 textSim=0.768 lyric=ダメだったんだね speech=だめだったんだなそれ
- line=13 reason=duplicate_lyric_line conf=0.854 textSim=0.869 lyric=時計の針を戻してる speech=時計の針を戻し
- line=13 reason=duplicate_lyric_line conf=0.853 textSim=0.869 lyric=時計の針を戻してる speech=の針を戻してる
- line=14 reason=duplicate_lyric_line conf=0.792 textSim=0.906 lyric=愛してた　それだけじゃ speech=てる愛してたそれだけじゃ
- line=13 reason=duplicate_lyric_line conf=0.787 textSim=0.789 lyric=時計の針を戻してる speech=針を戻してる
- line=14 reason=duplicate_lyric_line conf=0.772 textSim=0.906 lyric=愛してた　それだけじゃ speech=愛してたそれだけじゃだめ
- line=14 reason=duplicate_lyric_line conf=0.749 textSim=0.828 lyric=愛してた　それだけじゃ speech=戻してる愛してたそれだけじゃ
- line=14 reason=duplicate_lyric_line conf=0.737 textSim=0.794 lyric=愛してた　それだけじゃ speech=を戻してる愛してたそれだけじゃ
- line=14 reason=duplicate_lyric_line conf=0.737 textSim=0.828 lyric=愛してた　それだけじゃ speech=てる愛してたそれだけじゃだめ

## S3B lines (first 40)
- [0] unresolved t=- conf=0.000 kind=s3b-region-unresolved ねえ　忘れたいのに　また君を探す
- [1] unresolved t=- conf=0.000 kind=s3b-region-unresolved 深夜0時の通知にまだ　期待してる
- [2] unresolved t=- conf=0.000 kind=s3b-region-unresolved 「平気だよ」って言葉の裏
- [3] unresolved t=- conf=0.000 kind=s3b-region-unresolved 崩れそうな強がりで塗った夜
- [4] unresolved t=- conf=0.000 kind=s3b-region-unresolved 歩道橋から見下ろす街
- [5] unresolved t=- conf=0.000 kind=s3b-region-unresolved 終わらせたのは私だったのに
- [6] unresolved t=- conf=0.000 kind=s3b-region-unresolved 流れるラジオ　雨音混じり
- [7] unresolved t=- conf=0.000 kind=s3b-region-unresolved まだあの時に縛られてるみたい
- [8] unresolved t=- conf=0.000 kind=s3b-region-unresolved 心に走る夜の合図
- [9] unresolved t=- conf=0.000 kind=s3b-region-unresolved 君の名前がまだ痛い
- [10] unresolved t=- conf=0.000 kind=s3b-region-unresolved 通り過ぎたはずの未来が
- [11] unresolved t=- conf=0.000 kind=s3b-region-unresolved まだ私を呼び止める
- [12] unresolved t=- conf=0.000 kind=s3b-region-unresolved 何度でも踏み出すふりして
- [13] resolved t=76.857 conf=0.958 kind=anchor 時計の針を戻してる
- [14] resolved t=79.467 conf=0.824 kind=anchor 愛してた　それだけじゃ
- [15] lowConfidence t=82.737 conf=0.598 kind=s3b-region-directSpeech ダメだったんだね
- [16] unresolved t=- conf=0.000 kind=s3b-region-unresolved すれ違った言葉たちが
- [17] unresolved t=- conf=0.000 kind=s3b-region-unresolved 今さら意味を持ち始めてる
- [18] unresolved t=- conf=0.000 kind=s3b-region-unresolved 君の癖　君の声
- [19] unresolved t=- conf=0.000 kind=s3b-region-unresolved 消えないまま今日も続いてる
- [20] unresolved t=- conf=0.000 kind=s3b-region-unresolved 記憶の奥で鳴るアラーム
- [21] unresolved t=- conf=0.000 kind=s3b-region-unresolved 止めたはずの感情がまだ
- [22] unresolved t=- conf=0.000 kind=s3b-region-unresolved 夜に混ざってしまいそうで
- [23] unresolved t=- conf=0.000 kind=s3b-region-unresolved また逃げ出してしまいそうで
- [24] unresolved t=- conf=0.000 kind=s3b-region-unresolved 心に響く　夜の合図
- [25] unresolved t=- conf=0.000 kind=s3b-region-unresolved 君を知らない私になりたい
- [26] unresolved t=- conf=0.000 kind=s3b-region-unresolved なのにふとした仕草ひとつ
- [27] unresolved t=- conf=0.000 kind=s3b-region-unresolved 思い出が勝手に疼く
- [28] unresolved t=- conf=0.000 kind=s3b-region-unresolved 何度でも上書きしようとして
- [29] unresolved t=- conf=0.000 kind=s3b-region-unresolved あの日のまま動けない
- [30] unresolved t=- conf=0.000 kind=s3b-region-unresolved さよならは　きっとそう
- [31] unresolved t=- conf=0.000 kind=s3b-region-unresolved 優しさじゃなかった

## S3A lines (first 40)
- [0] unresolved t=- conf=0.000 kind=noEvidence ねえ　忘れたいのに　また君を探す
- [1] unresolved t=- conf=0.000 kind=noEvidence 深夜0時の通知にまだ　期待してる
- [2] unresolved t=- conf=0.000 kind=noEvidence 「平気だよ」って言葉の裏
- [3] unresolved t=- conf=0.000 kind=noEvidence 崩れそうな強がりで塗った夜
- [4] unresolved t=- conf=0.000 kind=noEvidence 歩道橋から見下ろす街
- [5] unresolved t=- conf=0.000 kind=noEvidence 終わらせたのは私だったのに
- [6] unresolved t=- conf=0.000 kind=noEvidence 流れるラジオ　雨音混じり
- [7] unresolved t=- conf=0.000 kind=noEvidence まだあの時に縛られてるみたい
- [8] unresolved t=- conf=0.000 kind=noEvidence 心に走る夜の合図
- [9] unresolved t=- conf=0.000 kind=noEvidence 君の名前がまだ痛い
- [10] unresolved t=- conf=0.000 kind=noEvidence 通り過ぎたはずの未来が
- [11] unresolved t=- conf=0.000 kind=noEvidence まだ私を呼び止める
- [12] unresolved t=- conf=0.000 kind=noEvidence 何度でも踏み出すふりして
- [13] unresolved t=- conf=0.000 kind=noEvidence 時計の針を戻してる
- [14] lowConfidence t=78.597 conf=0.657 kind=directSpeech 愛してた　それだけじゃ
- [15] lowConfidence t=82.737 conf=0.598 kind=directSpeech ダメだったんだね
- [16] unresolved t=- conf=0.000 kind=noEvidence すれ違った言葉たちが
- [17] unresolved t=- conf=0.000 kind=noEvidence 今さら意味を持ち始めてる
- [18] unresolved t=- conf=0.000 kind=noEvidence 君の癖　君の声
- [19] unresolved t=- conf=0.000 kind=noEvidence 消えないまま今日も続いてる
- [20] unresolved t=- conf=0.000 kind=noEvidence 記憶の奥で鳴るアラーム
- [21] unresolved t=- conf=0.000 kind=noEvidence 止めたはずの感情がまだ
- [22] unresolved t=- conf=0.000 kind=noEvidence 夜に混ざってしまいそうで
- [23] unresolved t=- conf=0.000 kind=noEvidence また逃げ出してしまいそうで
- [24] unresolved t=- conf=0.000 kind=noEvidence 心に響く　夜の合図
- [25] unresolved t=- conf=0.000 kind=noEvidence 君を知らない私になりたい
- [26] unresolved t=- conf=0.000 kind=noEvidence なのにふとした仕草ひとつ
- [27] unresolved t=- conf=0.000 kind=noEvidence 思い出が勝手に疼く
- [28] unresolved t=- conf=0.000 kind=noEvidence 何度でも上書きしようとして
- [29] unresolved t=- conf=0.000 kind=noEvidence あの日のまま動けない
- [30] unresolved t=- conf=0.000 kind=noEvidence さよならは　きっとそう
- [31] unresolved t=- conf=0.000 kind=noEvidence 優しさじゃなかった