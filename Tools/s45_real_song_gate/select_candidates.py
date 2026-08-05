#!/usr/bin/env python3
"""Select up to 8 real-song evaluation candidates from local SQLite (read-only).

Writes gitignored local-real-songs/* GT extracts and a local manifest.
Never writes commercial full lyrics into the tracked repo.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = Path.home() / "Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3"
LOCAL = ROOT / "docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate/local-real-songs"
PUBLIC = ROOT / "docs/phase-2-11c-zero-operation-alignment/s4-5-real-song-gate"


def script_lang(texts: list[str]) -> str:
    if not texts:
        return "und"
    n = len(texts)
    han = sum(1 for t in texts if re.search(r"[\u4e00-\u9fff]", t))
    kana = sum(1 for t in texts if re.search(r"[\u3040-\u30ff]", t))
    lat = sum(
        1
        for t in texts
        if re.search(r"[A-Za-z]{3,}", t) and not re.search(r"[\u3040-\u30ff\u4e00-\u9fff]", t)
    )
    if kana / n >= 0.35:
        return "ja"
    if han / n >= 0.5 and kana / n < 0.15:
        return "zh"
    if lat / n >= 0.4:
        return "en"
    if han / n >= 0.4:
        return "zh"
    return "ja"


def structure_tag(duration: float, texts: list[str], rep: int) -> str:
    avg = sum(len(t) for t in texts) / max(1, len(texts))
    if rep >= 4:
        return "repeated"
    if avg < 10:
        return "short_lines"
    if duration and duration < 175:
        return "fast"
    if duration and duration > 240:
        return "slow"
    return "medium"


def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def main() -> int:
    if not DB.exists():
        print("DB missing", DB, file=sys.stderr)
        return 1
    LOCAL.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        """
        SELECT t.title, t.artist_display, t.duration, t.spotify_id, t.stable_key,
               v.id AS vid, v.source, v.language, v.content_hash, v.confidence
        FROM lyrics_versions v
        JOIN tracks t ON t.stable_key = v.track_stable_key
        WHERE v.is_synced = 1
          AND (SELECT COUNT(*) FROM lyric_lines l
               WHERE l.lyrics_version_id = v.id
                 AND l.start_time IS NOT NULL AND l.start_time >= 0) >= 15
        ORDER BY t.updated_at DESC
        """
    ).fetchall()

    seen: set[str] = set()
    pool: list[dict] = []
    for r in rows:
        sid = (r["spotify_id"] or r["stable_key"] or "").lower().replace("spotify:track:", "")
        if not sid or sid in seen:
            continue
        lines = conn.execute(
            """
            SELECT line_index, start_time, end_time, original_text
            FROM lyric_lines WHERE lyrics_version_id=? ORDER BY line_index
            """,
            (r["vid"],),
        ).fetchall()
        texts = [x["original_text"] for x in lines]
        timed = [x for x in lines if x["start_time"] is not None and x["start_time"] >= 0]
        if len(timed) < 15:
            continue
        # Reject instrumental-ish empty
        if sum(1 for t in texts if t.strip()) < 12:
            continue
        lang = script_lang(texts)
        norms = [re.sub(r"\s+", "", t.lower()) for t in texts if len(t.strip()) >= 4]
        rep = sum(1 for _, c in Counter(norms).items() if c >= 2)
        tag = structure_tag(r["duration"] or 0, texts, rep)
        seen.add(sid)
        pool.append(
            {
                "spotify_id": r["spotify_id"],
                "stable_key_prefix": (r["stable_key"] or "")[:40],
                "title": r["title"],
                "artist": r["artist_display"],
                "duration": r["duration"],
                "version_id": r["vid"],
                "source": r["source"],
                "db_language": r["language"],
                "script_lang": lang,
                "structure_tag": tag,
                "line_count": len(lines),
                "timed_count": len(timed),
                "rep_groups": rep,
                "content_hash": r["content_hash"],
                "confidence": r["confidence"],
                "lines": [dict(x) for x in lines],
            }
        )

    # Desired coverage slots
    slots = [
        ("RS01", "ja", "slow"),
        ("RS02", "ja", "fast"),
        ("RS03", "ja", "repeated"),
        ("RS04", "ja", "short_lines"),
        ("RS05", "zh", "slow"),
        ("RS06", "zh", "repeated"),
        ("RS07", "en", "slow"),
        ("RS08", "en", "repeated"),
    ]

    def pick(lang: str, tag: str, used: set[str]) -> dict | None:
        # exact tag
        for p in pool:
            key = (p["spotify_id"] or p["stable_key_prefix"]).lower()
            if key in used or p["script_lang"] != lang:
                continue
            if p["structure_tag"] == tag:
                return p
        # soft fallbacks
        soft = {
            "slow": ["slow", "medium"],
            "fast": ["fast", "medium", "short_lines"],
            "repeated": ["repeated", "repeated_short", "medium"],
            "short_lines": ["short_lines", "fast", "medium"],
        }
        for t in soft.get(tag, [tag]):
            for p in pool:
                key = (p["spotify_id"] or p["stable_key_prefix"]).lower()
                if key in used or p["script_lang"] != lang:
                    continue
                if p["structure_tag"] == t:
                    return p
        # any of language
        for p in pool:
            key = (p["spotify_id"] or p["stable_key_prefix"]).lower()
            if key in used or p["script_lang"] != lang:
                continue
            return p
        return None

    used: set[str] = set()
    selected: list[dict] = []
    gaps: list[dict] = []
    for rid, lang, tag in slots:
        p = pick(lang, tag, used)
        if not p:
            gaps.append({"id": rid, "want_lang": lang, "want_tag": tag, "status": "no_candidate"})
            continue
        key = (p["spotify_id"] or p["stable_key_prefix"]).lower()
        used.add(key)
        # Capture window: middle 50s preferred
        dur = float(p["duration"] or 200)
        cap_start = max(0.0, min(dur * 0.25, max(0.0, dur - 55)))
        cap_end = min(dur, cap_start + 50)
        # Prefer GT dense region
        times = [ln["start_time"] for ln in p["lines"] if ln["start_time"] is not None]
        if times:
            mid = sorted(times)[len(times) // 2]
            cap_start = max(0.0, mid - 20)
            cap_end = min(dur, cap_start + 50)

        sample_dir = LOCAL / rid
        sample_dir.mkdir(parents=True, exist_ok=True)
        # Write plain + gt locally only
        plain_lines = [ln["original_text"] for ln in p["lines"]]
        plain_text = "\n".join(plain_lines) + "\n"
        gt_lines = [
            f"{ln['line_index']}\t{ln['start_time']}"
            for ln in p["lines"]
            if ln["start_time"] is not None and ln["start_time"] >= 0
        ]
        (sample_dir / "plain.txt").write_text(plain_text, encoding="utf-8")
        (sample_dir / "gt.tsv").write_text("\n".join(gt_lines) + "\n", encoding="utf-8")
        # meta without full lyric dump
        meta = {
            "id": rid,
            "spotify_id": p["spotify_id"],
            "stable_key_prefix": p["stable_key_prefix"],
            "title_hash": sha256_text(p["title"])[:16],
            "artist_hash": sha256_text(p["artist"])[:16],
            "title_len": len(p["title"]),
            "artist_len": len(p["artist"]),
            "duration": p["duration"],
            "version_id": p["version_id"],
            "source": p["source"],
            "script_lang": p["script_lang"],
            "structure_tag": p["structure_tag"],
            "wanted_tag": tag,
            "line_count": p["line_count"],
            "timed_count": p["timed_count"],
            "rep_groups": p["rep_groups"],
            "content_hash": p["content_hash"],
            "lyrics_sha256": sha256_text(plain_text),
            "gt_sha256": sha256_text("\n".join(gt_lines)),
            "capture": {
                "position_start": round(cap_start, 3),
                "position_end": round(cap_end, 3),
                "track_duration": round(dur, 3),
            },
            "audio_status": "pending_capture",
            "audio_path": None,
            "audio_sha256": None,
        }
        # Attach known existing real captures when identity matches known fixtures
        known = {
            "0662h3g9lgdt2vipzypzxm": ROOT
            / "docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/audio/sampleA.wav",
            "7ovucf5uhtbrzupb6zomvt": ROOT
            / "docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/audio/sampleB.wav",
        }
        sid_norm = (p["spotify_id"] or "").lower().replace("spotify:track:", "")
        if sid_norm in known and known[sid_norm].exists():
            ap = known[sid_norm]
            data = ap.read_bytes()
            meta["audio_status"] = "local_existing_capture"
            meta["audio_path"] = str(ap)
            meta["audio_sha256"] = hashlib.sha256(data).hexdigest()
            # existing A/B captures are ~40s from early/mid song — set window from GT densest early band
            if sid_norm.startswith("0662"):
                meta["capture"] = {"position_start": 0.0, "position_end": 40.14, "track_duration": dur}
            if sid_norm.startswith("7ovu"):
                meta["capture"] = {"position_start": 0.0, "position_end": 40.2, "track_duration": dur}
        (sample_dir / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
        selected.append({k: v for k, v in meta.items()})

    # Force-include existing real mixed captures A/B when present (even if GT timed=0 in DB).
    forced_audio = [
        {
            "id": "RS-EXIST-A",
            "spotify_id": "spotify:track:0662h3g9lgdt2vipzypzxm",
            "title": "夜の合図",
            "artist": "Kawasaki.Rio",
            "script_lang": "ja",
            "structure_tag": "medium",
            "wanted_tag": "ja_existing_capture",
            "wav": ROOT
            / "docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/audio/sampleA.wav",
            "plain": ROOT
            / "docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/sampleA_plain.txt",
            "capture": {"position_start": 0.0, "position_end": 40.14, "track_duration": 170.72},
        },
        {
            "id": "RS-EXIST-B",
            "spotify_id": "spotify:track:7ovUcF5uHTBRzUpB6ZOmvt",
            "title": "アイドル",
            "artist": "YOASOBI",
            "script_lang": "ja",
            "structure_tag": "repeated",
            "wanted_tag": "ja_existing_capture",
            "wav": ROOT
            / "docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/audio/sampleB.wav",
            "plain": ROOT
            / "docs/phase-2-11c-zero-operation-alignment/s2-whisper-full-pipeline/fixtures/sampleB_plain.txt",
            "capture": {"position_start": 0.0, "position_end": 40.2, "track_duration": 213.0},
        },
    ]
    existing_ids = {s["id"] for s in selected}
    for f in forced_audio:
        if f["id"] in existing_ids:
            continue
        if not f["wav"].exists() or not f["plain"].exists():
            gaps.append({"id": f["id"], "status": "forced_audio_missing_files"})
            continue
        sd = LOCAL / f["id"]
        sd.mkdir(parents=True, exist_ok=True)
        plain_text = f["plain"].read_text(encoding="utf-8")
        (sd / "plain.txt").write_text(plain_text, encoding="utf-8")
        # Build pseudo-GT from plain only if no timed GT: leave empty gt for timing-less text match skip
        # Prefer DB timed for same track if any
        gt_body = ""
        # optional: map from LRCLIB-less local; keep empty → score uses no_gt for timing
        (sd / "gt.tsv").write_text(gt_body, encoding="utf-8")
        audio_bytes = f["wav"].read_bytes()
        meta = {
            "id": f["id"],
            "spotify_id": f["spotify_id"],
            "stable_key_prefix": f["spotify_id"][:40],
            "title_hash": sha256_text(f["title"])[:16],
            "artist_hash": sha256_text(f["artist"])[:16],
            "title_len": len(f["title"]),
            "artist_len": len(f["artist"]),
            "duration": f["capture"]["track_duration"],
            "version_id": None,
            "source": "existing_capture_fixture",
            "script_lang": f["script_lang"],
            "structure_tag": f["structure_tag"],
            "wanted_tag": f["wanted_tag"],
            "line_count": len([ln for ln in plain_text.splitlines() if ln.strip()]),
            "timed_count": 0,
            "rep_groups": 0,
            "content_hash": sha256_text(plain_text)[:32],
            "lyrics_sha256": sha256_text(plain_text),
            "gt_sha256": sha256_text(gt_body),
            "capture": f["capture"],
            "audio_status": "local_existing_capture",
            "audio_path": str(f["wav"]),
            "audio_sha256": hashlib.sha256(audio_bytes).hexdigest(),
            "gt_status": "missing_timed_gt",
        }
        (sd / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
        selected.append(meta)

    manifest = {
        "formal_db_read_only": True,
        "formal_db_path_note": "~/Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3",
        "selected": selected,
        "gaps": gaps,
        "pool_size": len(pool),
        "lang_counts": {
            lang: sum(1 for p in pool if p["script_lang"] == lang) for lang in ("ja", "zh", "en")
        },
    }
    (LOCAL / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    # Public anonymous summary only
    public = {
        "selected_count": len(selected),
        "gaps": gaps,
        "lang_counts_in_pool": manifest["lang_counts"],
        "samples": [
            {
                "id": s["id"],
                "script_lang": s["script_lang"],
                "structure_tag": s["structure_tag"],
                "wanted_tag": s["wanted_tag"],
                "duration": s["duration"],
                "line_count": s["line_count"],
                "timed_count": s["timed_count"],
                "audio_status": s["audio_status"],
                "audio_sha256_prefix": (s.get("audio_sha256") or "")[:16] or None,
                "lyrics_sha256_prefix": s["lyrics_sha256"][:16],
                "capture": s["capture"],
            }
            for s in selected
        ],
    }
    (PUBLIC / "anonymous_manifest.json").write_text(
        json.dumps(public, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(public, indent=2, ensure_ascii=False))
    print("local_manifest", LOCAL / "manifest.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
