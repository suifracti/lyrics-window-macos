# Real-song evaluation protocol (S4)

## Fixture rules

- Commercial WAV / full lyric text: **local only**, under  
  `docs/phase-2-11c-zero-operation-alignment/s4-repeated-sections/local-real-songs/` (gitignored).
- Repo stores only: anonymous IDs, WAV SHA-256, duration, capture window, metric JSON, short notes.
- Do **not** commit full copyrighted lyrics or audio.

## Required layout (local)

```
local-real-songs/
  RS01/
    audio.wav          # 16 kHz mono preferred
    plain.txt          # line-per-row plain lyrics (local)
    gt.tsv             # optional index\tstart_seconds
    meta.json          # language, genre tags, capture position-start/end, track-duration
  RS02/ ...
```

## Run

```bash
export SPOTIFYLYRICS_WHISPER_CLI=/opt/homebrew/bin/whisper-cli
export SPOTIFYLYRICS_WHISPER_MODEL=.../ggml-small.bin
Tools/s2_full_pipeline/.build/s2_full_pipeline \
  --wav local-real-songs/RS01/audio.wav \
  --lyrics local-real-songs/RS01/plain.txt \
  --gt local-real-songs/RS01/gt.tsv \
  --out /tmp/s4-rs01-small \
  --engine whisper_small --lang ja \
  --position-start 120 --position-end 170 --track-duration 240
```

## Human review checklist (per song)

1. Sample ≥10 suggested lines  
2. All wrong suggestions  
3. All repeated-section suggestions  
4. All >3s errors vs GT  

Labels: `correct` · `wrong_line` · `wrong_occurrence` · `too_early` · `too_late` · `ambiguous` · `unsupported_interpolation`

## Gate (experimental, not product)

- ≥6/8 real songs non-zero suggestions  
- wrong occurrence ≈ 0  
- error rate controlled  
- fail → unresolved preferred over wrong  
