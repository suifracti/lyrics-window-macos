#!/usr/bin/env python3
"""Run Whisper-small full pipeline on local-real-songs with available audio; score vs GT.

Does not modify alignment algorithms. formal DB is not opened.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / "docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/local-real-songs"
OUT_ROOT = ROOT / "docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/runs"
BIN = ROOT / "Tools/s2_full_pipeline/.build/s2_full_pipeline"
MODEL = ROOT / "docs/phase-2-11c-zero-operation-alignment/s0-5-engine-viability/whisper-models/ggml-small.bin"
MEDIUM = ROOT / "docs/phase-2-11c-zero-operation-alignment/s0-5-engine-viability/whisper-models/ggml-medium.bin"
WHISPER = os.environ.get("SPOTIFYLYRICS_WHISPER_CLI", "/opt/homebrew/bin/whisper-cli")
SCORE = ROOT / "Tools/s45_real_song_gate/score_against_gt.py"
FORMAL = Path.home() / "Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3"


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def formal_sha() -> str | None:
    if not FORMAL.exists():
        return None
    return sha256_file(FORMAL)


def ensure_bin() -> None:
    if not BIN.exists():
        subprocess.check_call(["bash", str(ROOT / "Tools/s2_full_pipeline/build.sh")])


def run_sample(meta: dict, engine: str = "whisper_small") -> dict:
    rid = meta["id"]
    sample_dir = LOCAL / rid
    plain = sample_dir / "plain.txt"
    gt = sample_dir / "gt.tsv"
    audio = meta.get("audio_path")
    out = OUT_ROOT / rid / engine
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    if not audio or not Path(audio).exists():
        return {
            "id": rid,
            "engine": engine,
            "ok": False,
            "skip": "audio_missing",
            "audio_status": meta.get("audio_status"),
        }

    env = os.environ.copy()
    env["SPOTIFYLYRICS_WHISPER_CLI"] = WHISPER
    if engine == "whisper_medium":
        env["SPOTIFYLYRICS_WHISPER_MODEL"] = str(MEDIUM)
    else:
        env["SPOTIFYLYRICS_WHISPER_MODEL"] = str(MODEL)
    env["SPOTIFYLYRICS_WHISPER_LANGUAGE"] = meta.get("script_lang") or "ja"
    env["SPOTIFYLYRICS_WHISPER_TIMEOUT_SECONDS"] = "600"

    cap = meta.get("capture") or {}
    cmd = [
        str(BIN),
        "--wav",
        str(audio),
        "--lyrics",
        str(plain),
        "--gt",
        str(gt),
        "--out",
        str(out),
        "--engine",
        engine,
        "--lang",
        meta.get("script_lang") or "ja",
        "--title",
        rid,
        "--artist",
        "anon",
        "--position-start",
        str(cap.get("position_start", 0)),
        "--position-end",
        str(cap.get("position_end", 50)),
        "--track-duration",
        str(cap.get("track_duration", 200)),
    ]
    t0 = time.time()
    time_cmd = ["/usr/bin/time", "-l"] + cmd
    proc = subprocess.run(time_cmd, env=env, capture_output=True, text=True, cwd=str(ROOT))
    wall = time.time() - t0
    (out / "stdout.txt").write_text(proc.stdout)
    (out / "stderr.txt").write_text(proc.stderr)
    (out / "exit_code.txt").write_text(str(proc.returncode))

    if proc.returncode != 0 or not (out / "merger_draft.json").exists():
        return {
            "id": rid,
            "engine": engine,
            "ok": False,
            "exit": proc.returncode,
            "wall": wall,
            "error_tail": proc.stderr[-500:],
        }

    # score
    score = json.loads(
        subprocess.check_output(
            [sys.executable, str(SCORE), str(out), str(plain), str(gt), str(sample_dir / "meta.json")],
            text=True,
        )
    )
    metrics = {}
    if (out / "metrics.json").exists():
        metrics = json.loads((out / "metrics.json").read_text())

    peak = None
    import re

    m = re.search(r"(\d+)\s+maximum resident set size", proc.stderr)
    if m:
        peak = int(m.group(1))

    return {
        "id": rid,
        "engine": engine,
        "ok": True,
        "wall": wall,
        "peak_rss": peak,
        "script_lang": meta.get("script_lang"),
        "structure_tag": meta.get("structure_tag"),
        "audio_status": meta.get("audio_status"),
        "audio_sha256": meta.get("audio_sha256"),
        "capture": cap,
        "pipeline_metrics": {
            "suggestions": metrics.get("merger", {}).get("final_suggestions"),
            "s3a_coverage": (metrics.get("s3a") or {}).get("coverage"),
            "s3b_anchors": metrics.get("s3b_anchors_accepted"),
            "repeated": metrics.get("repeated"),
        },
        "score": score,
    }


def main() -> int:
    ensure_bin()
    manifest_path = LOCAL / "manifest.json"
    if not manifest_path.exists():
        subprocess.check_call([sys.executable, str(ROOT / "Tools/s45_real_song_gate/select_candidates.py")])
    manifest = json.loads(manifest_path.read_text())
    before = formal_sha()
    OUT_ROOT.mkdir(parents=True, exist_ok=True)

    results = []
    for meta in manifest["selected"]:
        # reload meta from disk (may have audio updates)
        disk = json.loads((LOCAL / meta["id"] / "meta.json").read_text())
        print(f"== {disk['id']} audio={disk.get('audio_status')} ==", flush=True)
        r = run_sample(disk, "whisper_small")
        results.append(r)
        print(
            f"  ok={r.get('ok')} sug={((r.get('score') or {}).get('suggestions'))} "
            f"wrong={((r.get('score') or {}).get('wrong'))} wocc={((r.get('score') or {}).get('wrong_occurrence'))}",
            flush=True,
        )
        # medium only for failures
        if r.get("ok") and r.get("score", {}).get("suggestions", 0) == 0 and MEDIUM.exists():
            print("  medium supplement...", flush=True)
            rm = run_sample(disk, "whisper_medium")
            results.append(rm)

    after = formal_sha()
    summary = {
        "formal_before": before,
        "formal_after": after,
        "formal_unchanged": before == after,
        "formal_opened": False,
        "results": results,
    }
    out_json = ROOT / "docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/metrics_raw.json"
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(summary, indent=2, ensure_ascii=False))
    print("formal_unchanged", before == after)
    print("wrote", out_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
