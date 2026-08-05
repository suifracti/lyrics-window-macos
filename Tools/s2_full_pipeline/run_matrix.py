#!/usr/bin/env python3
"""S2 orchestrator: Apple / Whisper small / Whisper medium full pipeline matrix.

Never opens formal SQLite. TEMP outputs under s2-whisper-full-pipeline/runs/.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
S2 = ROOT / "docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline"
# S3 after-matrix writes here when SPOTIFYLYRICS_S3_OUT=1 or --s3 flag.
S3 = ROOT / "docs/phase-2-11c-zero-operation-alignment/s3-transcript-alignment"
MODEL_DIR = ROOT / "docs/phase-2-11c-zero-operation-alignment/s0-5-engine-viability/whisper-models"
BIN = ROOT / "Tools/s2_full_pipeline/.build/s2_full_pipeline"
WHISPER_CLI = os.environ.get("SPOTIFYLYRICS_WHISPER_CLI", "/opt/homebrew/bin/whisper-cli")
FORMAL_DB = Path.home() / "Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3"
OUT_ROOT = S3 if os.environ.get("SPOTIFYLYRICS_S3_OUT") == "1" else S2


def sha256(path: Path) -> str:
    return subprocess.check_output(["shasum", "-a", "256", str(path)], text=True).split()[0]


def formal_sha() -> str | None:
    if not FORMAL_DB.exists():
        return None
    return sha256(FORMAL_DB)


def ensure_bin() -> None:
    if not BIN.exists():
        subprocess.check_call(["bash", str(ROOT / "Tools/s2_full_pipeline/build.sh")])


def load_manifest() -> list[dict]:
    return json.loads((S2 / "fixtures/samples_manifest.json").read_text())


def peak_rss_from_time_l(stderr: str) -> int | None:
    # macOS /usr/bin/time -l: "   878297088  maximum resident set size"
    m = re.search(r"(\d+)\s+maximum resident set size", stderr)
    if m:
        return int(m.group(1))
    m = re.search(r"maximum resident set size\s*[:=]?\s*(\d+)", stderr)
    if m:
        return int(m.group(1))
    return None


def run_one(sample: dict, engine: str, model_path: Path | None) -> dict:
    sid = sample["id"]
    out = OUT_ROOT / "runs" / sid / engine
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    wav = (S2 / sample["wav"]).resolve()
    lyrics = (S2 / sample["lyrics"]).resolve()
    lang = sample["language"]

    env = os.environ.copy()
    env["SPOTIFYLYRICS_FORMAL_DB"] = "NEVER"  # harness marker only
    # Ensure engines do not touch formal DB paths via app defaults — harness has no SQLite.
    if engine.startswith("whisper"):
        env["SPOTIFYLYRICS_WHISPER_CLI"] = WHISPER_CLI
        assert model_path and model_path.exists(), f"missing model {model_path}"
        env["SPOTIFYLYRICS_WHISPER_MODEL"] = str(model_path)
        env["SPOTIFYLYRICS_WHISPER_LANGUAGE"] = lang
        env["SPOTIFYLYRICS_WHISPER_TIMEOUT_SECONDS"] = "600"

    cmd = [
        str(BIN),
        "--wav", str(wav),
        "--lyrics", str(lyrics),
        "--out", str(out),
        "--engine", engine if engine != "whisper_medium" else "whisper_medium",
        "--lang", lang,
        "--title", sample["title"],
        "--artist", sample["artist"],
    ]
    # Map engine names accepted by main.swift
    if engine == "whisper_small":
        cmd[cmd.index("--engine") + 1] = "whisper_small"
    elif engine == "whisper_medium":
        cmd[cmd.index("--engine") + 1] = "whisper_medium"

    # Use /usr/bin/time -l for peak RSS
    time_cmd = ["/usr/bin/time", "-l"] + cmd
    t0 = time.time()
    proc = subprocess.run(
        time_cmd,
        env=env,
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    wall = time.time() - t0
    (out / "stdout.txt").write_text(proc.stdout)
    (out / "stderr.txt").write_text(proc.stderr)
    (out / "exit_code.txt").write_text(str(proc.returncode))

    peak = peak_rss_from_time_l(proc.stderr)
    result = {
        "sample": sid,
        "engine": engine,
        "exit_code": proc.returncode,
        "wall_seconds": wall,
        "peak_rss_bytes": peak,
        "model_path": str(model_path) if model_path else None,
        "ok": proc.returncode == 0 and (out / "metrics.json").exists(),
    }
    if (out / "metrics.json").exists():
        result["metrics"] = json.loads((out / "metrics.json").read_text())
    else:
        result["error_tail"] = proc.stderr[-800:]
    (out / "run_meta.json").write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(f"[{sid}/{engine}] exit={proc.returncode} wall={wall:.1f}s peak={peak} ok={result['ok']}", flush=True)
    return result


def char_normalize(s: str) -> str:
    s = s.lower()
    s = re.sub(r"\s+", "", s)
    s = re.sub(r"[^\w\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+", "", s, flags=re.UNICODE)
    return s


def token_hit_rate(lyrics_path: Path, speech_json: Path) -> dict:
    lines = [l.strip() for l in lyrics_path.read_text().splitlines() if l.strip()]
    if not speech_json.exists():
        return {"token_hit_rate": None}
    sp = json.loads(speech_json.read_text())
    segs = sp.get("segments") or []
    joined = char_normalize("".join(s.get("text", "") for s in segs))
    if not joined:
        return {"token_hit_rate": 0.0, "hit_lines": 0, "total_lines": len(lines)}
    hits = 0
    for line in lines:
        n = char_normalize(line)
        if len(n) < 2:
            continue
        # sliding window / substring
        if n in joined or any(n[i:i+4] in joined for i in range(0, max(1, len(n)-3)) if len(n) >= 4):
            hits += 1
        elif len(n) >= 2 and n[:2] in joined and n[-2:] in joined:
            hits += 1
    return {
        "token_hit_rate": hits / len(lines) if lines else 0.0,
        "hit_lines": hits,
        "total_lines": len(lines),
    }


def heuristic_wrong_suggestions(run_dir: Path) -> dict:
    """Without GT: count non-monotonic, out-of-audio, and low-overlap suggestions."""
    draft_p = run_dir / "merger_draft.json"
    speech_p = run_dir / "speech.json"
    if not draft_p.exists():
        return {"wrong_suggestions": None}
    draft = json.loads(draft_p.read_text())
    lines = draft.get("lines") or []
    suggested = [l for l in lines if l.get("status") == "suggested" and l.get("suggestedStartTime") is not None]
    speech = json.loads(speech_p.read_text()) if speech_p.exists() else {}
    segs = speech.get("segments") or []
    audio_dur = float(speech.get("audio_duration") or 0)

    wrong = 0
    reasons = []
    last_t = -1.0
    for s in suggested:
        t = float(s["suggestedStartTime"])
        if audio_dur and (t < -0.25 or t > audio_dur + 0.5):
            wrong += 1
            reasons.append("out_of_audio")
            continue
        if t + 0.05 < last_t:
            wrong += 1
            reasons.append("non_monotonic")
        last_t = max(last_t, t)
        # local transcript overlap
        win = " ".join(
            seg.get("text", "")
            for seg in segs
            if abs(float(seg.get("start", 0)) - t) < 2.5
        )
        lyric = char_normalize(s.get("text") or "")
        win_n = char_normalize(win)
        if lyric and win_n and len(lyric) >= 4:
            # crude: no 2-char ngram shared
            grams = {lyric[i:i+2] for i in range(len(lyric)-1)}
            if not any(g in win_n for g in grams):
                wrong += 1
                reasons.append("low_local_overlap")
    return {
        "wrong_suggestions": wrong,
        "suggested_count": len(suggested),
        "wrong_reasons": reasons[:20],
    }


def hallucination_stats(speech_json: Path) -> dict:
    if not speech_json.exists():
        return {}
    sp = json.loads(speech_json.read_text())
    segs = sp.get("segments") or []
    texts = [s.get("text", "").strip() for s in segs]
    empty = sum(1 for t in texts if not t)
    # repeats: consecutive identical
    repeats = 0
    for a, b in zip(texts, texts[1:]):
        if a and a == b:
            repeats += 1
    # obvious hallucination: very long latin-only on ja job handled elsewhere
    return {
        "empty_segments": empty,
        "repeat_segments": repeats,
        "piece_count": len(texts),
        "non_empty_chars": len(re.sub(r"\s+", "", "".join(texts))),
    }


def main() -> int:
    ensure_bin()
    formal_before = formal_sha()
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "metrics").mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "formal_db_before.sha").write_text((formal_before or "MISSING") + "\n")

    samples = load_manifest()
    small = MODEL_DIR / "ggml-small.bin"
    medium = MODEL_DIR / "ggml-medium.bin"
    engines = [
        ("apple", None),
        ("whisper_small", small),
        ("whisper_medium", medium if medium.exists() else None),
    ]

    all_results = []
    for sample in samples:
        for engine, model in engines:
            if engine.startswith("whisper") and (model is None or not model.exists()):
                print(f"SKIP {sample['id']}/{engine} model missing", flush=True)
                all_results.append({"sample": sample["id"], "engine": engine, "ok": False, "skip": "model_missing"})
                continue
            try:
                r = run_one(sample, engine, model)
            except Exception as e:
                r = {"sample": sample["id"], "engine": engine, "ok": False, "error": str(e)}
                print(f"ERR {sample['id']}/{engine}: {e}", flush=True)
            # enrich
            run_dir = OUT_ROOT / "runs" / sample["id"] / engine
            if run_dir.exists():
                hit = token_hit_rate(S2 / sample["lyrics"], run_dir / "speech.json")
                wrong = heuristic_wrong_suggestions(run_dir)
                hall = hallucination_stats(run_dir / "speech.json")
                r["token_hit"] = hit
                r["wrong"] = wrong
                r["hallucination"] = hall
                if model and model.exists():
                    r["model_bytes"] = model.stat().st_size
                    r["model_sha256"] = sha256(model)
                # transcript prep counts
                prep_p = run_dir / "transcript_prep.json"
                if prep_p.exists():
                    prep = json.loads(prep_p.read_text())
                    r["raw_pieces"] = prep.get("raw_pieces")
                    r["prepared_pieces"] = prep.get("prepared_pieces")
            all_results.append(r)

    formal_after = formal_sha()
    (OUT_ROOT / "formal_db_after.sha").write_text((formal_after or "MISSING") + "\n")
    summary = {
        "formal_before": formal_before,
        "formal_after": formal_after,
        "formal_unchanged": formal_before == formal_after,
        "formal_opened": False,
        "out_root": str(OUT_ROOT),
        "results": all_results,
    }
    (OUT_ROOT / "metrics/raw_results.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))
    print("formal_unchanged=", formal_before == formal_after, "out=", OUT_ROOT, flush=True)
    return 0 if any(r.get("ok") for r in all_results) else 1


if __name__ == "__main__":
    sys.exit(main())
