# S3B Anchor-Constrained Partial Alignment Report

- session: `FCE4FF7E-802B-4758-AB41-4A47FE7DB6B1`
- identity: `spotify-id:0662h3g9lgdt2vipzypzxm|metadata:夜の合図|`
- locale: `ja-JP` fallback: none
- capturedDuration: 48.376 s
- transcriptSegments: 36
- judgment: **B_coverage_up_but_errors_remain**
- usedConstrainedAlignment: true
- s3bFallbackReason: none
- acceptedAnchors: 4
- rejectedAnchors: 26

## A/B comparison (same capture + plain lyrics)

| metric | S3A | S3B |
|---|---:|---:|
| resolved | 2 | 4 |
| lowConfidence | 2 | 1 |
| unresolved | 28 | 27 |
| outsideCapturedRange | 0 | 0 |
| coverageRatio | 0.125 | 0.156 |
| overallConfidence | 0.634 | 0.802 |
| acceptedAnchors | 0 (n/a) | 4 |
| rejectedAnchors | 0 (n/a) | 26 |

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
- line=13 t=76.939-79.129 conf=0.958 textSim=1.000 lyric=時計の針を戻してる speech=時計の針を戻してる evidence=textSim=1.000;speech=0.790;window=3-8
- line=14 t=79.609-82.069 conf=0.934 textSim=1.000 lyric=愛してた　それだけじゃ speech=愛してたそれだけじゃ evidence=textSim=1.000;speech=0.671;window=9-11
- line=15 t=82.789-84.589 conf=0.813 textSim=0.869 lyric=ダメだったんだね speech=だめだったんだな evidence=textSim=0.869;speech=0.591;window=12-14
- line=16 t=85.009-87.799 conf=0.859 textSim=0.896 lyric=すれ違った言葉たちが speech=それ違った言葉たちが evidence=textSim=0.896;speech=0.711;window=15-19

## Rejected anchors (first 30)
- line=12 reason=overall_confidence_below_threshold conf=0.672 textSim=0.792 lyric=何度でも踏み出すふりして speech=何度でも踏み出す
- line=12 reason=text_similarity_below_threshold conf=0.662 textSim=0.777 lyric=何度でも踏み出すふりして speech=何度でも踏み出す振り
- line=13 reason=text_similarity_below_threshold conf=0.753 textSim=0.768 lyric=時計の針を戻してる speech=振り時計の針を戻し
- line=14 reason=text_similarity_below_threshold conf=0.749 textSim=0.762 lyric=愛してた　それだけじゃ speech=戻してる愛してたそれだけじゃだめ
- line=14 reason=text_similarity_below_threshold conf=0.718 textSim=0.738 lyric=愛してた　それだけじゃ speech=愛してたそれ
- line=14 reason=text_similarity_below_threshold conf=0.733 textSim=0.762 lyric=愛してた　それだけじゃ speech=愛してたそれだけじゃだめだったん
- line=14 reason=text_similarity_below_threshold conf=0.737 textSim=0.738 lyric=愛してた　それだけじゃ speech=それだけじゃ
- line=15 reason=text_similarity_below_threshold conf=0.739 textSim=0.768 lyric=ダメだったんだね speech=だめだったんだなそれ
- line=16 reason=text_similarity_below_threshold conf=0.741 textSim=0.753 lyric=すれ違った言葉たちが speech=だなそれ違った言葉たち
- line=16 reason=text_similarity_below_threshold conf=0.750 textSim=0.753 lyric=すれ違った言葉たちが speech=違った言葉たちが今更に
- line=18 reason=text_similarity_below_threshold conf=0.756 textSim=0.752 lyric=君の癖　君の声 speech=君の声君の声
- line=14 reason=duplicate_lyric_line conf=0.866 textSim=0.906 lyric=愛してた　それだけじゃ speech=てる愛してたそれだけじゃ
- line=14 reason=duplicate_lyric_line conf=0.858 textSim=0.906 lyric=愛してた　それだけじゃ speech=愛してたそれだけじゃだめ
- line=13 reason=duplicate_lyric_line conf=0.853 textSim=0.869 lyric=時計の針を戻してる speech=の針を戻してる
- line=13 reason=duplicate_lyric_line conf=0.852 textSim=0.869 lyric=時計の針を戻してる speech=時計の針を戻し
- line=16 reason=duplicate_lyric_line conf=0.849 textSim=0.884 lyric=すれ違った言葉たちが speech=違った言葉たちが
- line=16 reason=duplicate_lyric_line conf=0.806 textSim=0.836 lyric=すれ違った言葉たちが speech=それ違った言葉たち
- line=14 reason=duplicate_lyric_line conf=0.804 textSim=0.828 lyric=愛してた　それだけじゃ speech=戻してる愛してたそれだけじゃ
- line=14 reason=duplicate_lyric_line conf=0.801 textSim=0.828 lyric=愛してた　それだけじゃ speech=てる愛してたそれだけじゃだめ
- line=16 reason=duplicate_lyric_line conf=0.794 textSim=0.812 lyric=すれ違った言葉たちが speech=それ違った言葉たちが今更
- line=16 reason=duplicate_lyric_line conf=0.792 textSim=0.812 lyric=すれ違った言葉たちが speech=だなそれ違った言葉たちが
- line=16 reason=duplicate_lyric_line conf=0.788 textSim=0.815 lyric=すれ違った言葉たちが speech=違った言葉たち
- line=13 reason=duplicate_lyric_line conf=0.788 textSim=0.789 lyric=時計の針を戻してる speech=針を戻してる
- line=15 reason=duplicate_lyric_line conf=0.785 textSim=0.849 lyric=ダメだったんだね speech=だめだったん
- line=14 reason=duplicate_lyric_line conf=0.780 textSim=0.794 lyric=愛してた　それだけじゃ speech=を戻してる愛してたそれだけじゃ
- line=16 reason=duplicate_lyric_line conf=0.779 textSim=0.792 lyric=すれ違った言葉たちが speech=違った言葉たちが今更

## S3B lines (first 40)
- [0] unresolved t=- conf=0.000 kind=s3b-region-unresolved ねえ　忘れたいのに　また君を探す
- [1] unresolved t=- conf=0.000 kind=s3b-region-unresolved 深夜0時の通知にまだ　期待してる
- [2] unresolved t=- conf=0.000 kind=s3b-region-unresolved 「平気だよ」って言葉の裏
- [3] unresolved t=- conf=0.000 kind=s3b-region-unresolved 崩れそうな強がりで塗った夜
- [4] unresolved t=- conf=0.000 kind=s3b-region-unresolved 歩道橋から見下ろす街
- [5] unresolved t=- conf=0.000 kind=s3b-region-unresolved 終わらせたのは私だったのに
- [6] unresolved t=- conf=0.000 kind=s3b-region-unresolved 流れるラジオ　雨音混じり
- [7] lowConfidence t=45.388 conf=0.445 kind=s3b-region-directSpeech まだあの時に縛られてるみたい
- [8] unresolved t=- conf=0.000 kind=s3b-region-unresolved 心に走る夜の合図
- [9] unresolved t=- conf=0.000 kind=s3b-region-unresolved 君の名前がまだ痛い
- [10] unresolved t=- conf=0.000 kind=s3b-region-unresolved 通り過ぎたはずの未来が
- [11] unresolved t=- conf=0.000 kind=s3b-region-unresolved まだ私を呼び止める
- [12] unresolved t=- conf=0.000 kind=s3b-region-unresolved 何度でも踏み出すふりして
- [13] resolved t=76.939 conf=0.958 kind=anchor 時計の針を戻してる
- [14] resolved t=79.609 conf=0.934 kind=anchor 愛してた　それだけじゃ
- [15] resolved t=82.789 conf=0.813 kind=anchor ダメだったんだね
- [16] resolved t=85.009 conf=0.859 kind=anchor すれ違った言葉たちが
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
- [7] lowConfidence t=45.388 conf=0.445 kind=directSpeech まだあの時に縛られてるみたい
- [8] unresolved t=- conf=0.000 kind=noEvidence 心に走る夜の合図
- [9] unresolved t=- conf=0.000 kind=noEvidence 君の名前がまだ痛い
- [10] unresolved t=- conf=0.000 kind=noEvidence 通り過ぎたはずの未来が
- [11] unresolved t=- conf=0.000 kind=noEvidence まだ私を呼び止める
- [12] unresolved t=- conf=0.000 kind=noEvidence 何度でも踏み出すふりして
- [13] unresolved t=- conf=0.000 kind=noEvidence 時計の針を戻してる
- [14] resolved t=79.609 conf=0.786 kind=directSpeech 愛してた　それだけじゃ
- [15] resolved t=82.789 conf=0.808 kind=directSpeech ダメだったんだね
- [16] lowConfidence t=85.009 conf=0.496 kind=directSpeech すれ違った言葉たちが
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