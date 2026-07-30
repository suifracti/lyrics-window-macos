#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/audio-pcm.XXXXXX)"
export TEST_AUDIO_PATH="$TMP/input.wav"
export TEST_WORK_DIR="$TMP/work"
mkdir -p "$TEST_WORK_DIR"
/usr/bin/python3 - "$TEST_AUDIO_PATH" <<'PY'
import sys, wave, struct
path = sys.argv[1]
with wave.open(path, 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(16000)
    frames = [0] * 16000
    f.writeframes(b''.join(struct.pack('<h', x) for x in frames))
PY
swiftc -parse-as-library \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AudioInputMetadata.swift" \
  "$ROOT_DIR/SpotifyLyrics/Lyrics/AudioPCMConverter.swift" \
  "$ROOT_DIR/Tests/audio_pcm_contract.swift" \
  -framework AVFoundation -framework CoreMedia -framework CryptoKit \
  -o "$TMP/audio-pcm-contract"
"$TMP/audio-pcm-contract"
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
if root.exists():
    # Swift owns the test work directory; the only remaining files are the
    # generated executable/input fixture and are intentionally ephemeral.
    pass
PY
echo "audio PCM contract OK"
