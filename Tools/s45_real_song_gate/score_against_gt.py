#!/usr/bin/env python3
"""Score Merger draft against ground-truth timeline (algorithm does not self-score)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def norm(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"\s+", "", s)
    s = re.sub(r"[^\w\u3040-\u30ff\u3400-\u9fff]+", "", s, flags=re.UNICODE)
    return s


def load_gt(path: Path) -> dict[int, float]:
    out: dict[int, float] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 2:
            out[int(parts[0])] = float(parts[1])
    return out


def load_plain(path: Path) -> list[str]:
    return [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()]


def build_groups(plain: list[str]) -> dict[int, list[int]]:
    buckets: dict[str, list[int]] = {}
    for i, t in enumerate(plain):
        k = norm(t)
        if len(k) < 4:
            continue
        buckets.setdefault(k, []).append(i)
    gmap: dict[int, list[int]] = {}
    for idxs in buckets.values():
        if len(idxs) >= 2:
            for i in idxs:
                gmap[i] = idxs
    return gmap


def score_one(run_dir: Path, plain_path: Path, gt_path: Path, capture: dict) -> dict:
    draft = json.loads((run_dir / "merger_draft.json").read_text())
    plain = load_plain(plain_path)
    gt = load_gt(gt_path)
    groups = build_groups(plain)
    cap0 = float(capture.get("position_start") or 0)
    cap1 = float(capture.get("position_end") or 1e9)

    suggestions = [
        ln
        for ln in draft.get("lines") or []
        if ln.get("status") == "suggested" and ln.get("suggestedStartTime") is not None
    ]

    # Estimate global offset between capture-local times and GT absolute times.
    # offset ≈ median(gt[idx] - t_sug) over lines with both suggestion and GT.
    deltas = []
    for s in suggestions:
        idx = int(s["lyricLineIndex"])
        if idx in gt:
            deltas.append(gt[idx] - float(s["suggestedStartTime"]))
    offset = 0.0
    if deltas:
        ds = sorted(deltas)
        offset = ds[len(ds) // 2]

    results = []
    abs_errors = []
    wrong = 0
    wrong_occ = 0
    correct = 0
    timing_err = 0
    unsupported = 0
    capture_viol = 0
    non_mono = 0
    last_t = -1.0

    for s in suggestions:
        idx = int(s["lyricLineIndex"])
        t_raw = float(s["suggestedStartTime"])
        t = t_raw + offset  # align capture window to GT absolute domain
        evidence = (s.get("evidenceSummary") or "").lower()
        label = "correct"
        note = f"offset={offset:.3f}"

        # Capture violation uses raw absolute domain from pipeline (already position-start mapped)
        if t_raw < cap0 - 0.75 or t_raw > cap1 + 0.75:
            capture_viol += 1
            label = "capture_violation"
            wrong += 1
        elif "weakinterpolated" in evidence:
            unsupported += 1
            label = "unsupported_interpolation"
            wrong += 1
        elif idx not in gt:
            label = "no_gt"
        else:
            ref = gt[idx]
            best_err = abs(t - ref)
            abs_errors.append(best_err)

            # Wrong occurrence: same text group, closer to another occurrence's GT
            g = groups.get(idx)
            if g and len(g) >= 2:
                errs = [(j, abs(t - gt[j])) for j in g if j in gt]
                if errs:
                    best_j, best_e = min(errs, key=lambda x: x[1])
                    if best_j != idx and best_e + 0.75 < best_err:
                        wrong_occ += 1
                        label = "wrong_occurrence"
                        wrong += 1
                        note += f";closer_to_line={best_j}"
            if label == "correct":
                if best_err > 3.0:
                    timing_err += 1
                    label = "timing_error_gt3s"
                    wrong += 1
                elif best_err > 1.5:
                    label = "timing_soft"
                    correct += 1
                else:
                    correct += 1

        if last_t >= 0 and t_raw + 0.001 < last_t:
            non_mono += 1
            if label in ("correct", "timing_soft", "no_gt"):
                if label == "correct" or label == "timing_soft":
                    correct = max(0, correct - 1)
                label = "non_monotonic"
                wrong += 1
        last_t = max(last_t, t_raw)
        results.append(
            {
                "line_index": idx,
                "t_raw": t_raw,
                "t_aligned": t,
                "label": label,
                "note": note,
                "gt": gt.get(idx),
                "err": abs(t - gt[idx]) if idx in gt else None,
            }
        )

    abs_errors_sorted = sorted(abs_errors)
    def pct(p):
        if not abs_errors_sorted:
            return None
        i = min(len(abs_errors_sorted) - 1, int(round((len(abs_errors_sorted) - 1) * p)))
        return abs_errors_sorted[i]

    n_plain = len(plain)
    return {
        "suggestions": len(suggestions),
        "suggestion_coverage": len(suggestions) / n_plain if n_plain else 0,
        "correct": correct,
        "wrong": wrong,
        "wrong_occurrence": wrong_occ,
        "timing_error_gt3s": timing_err,
        "unsupported_interpolation": unsupported,
        "capture_violations": capture_viol,
        "non_monotonic": non_mono,
        "median_abs_error": pct(0.5),
        "p90_abs_error": pct(0.9),
        "gt3_mismatch": sum(1 for e in abs_errors if e > 3),
        "unresolved": sum(1 for ln in draft.get("lines") or [] if ln.get("status") == "unresolved"),
        "gt_offset_estimate": offset,
        "gt_pairs_for_offset": len(deltas),
        "details": results,
    }


def main() -> int:
    if len(sys.argv) < 5:
        print("usage: score_against_gt.py RUN_DIR PLAIN GT_TSV CAPTURE_JSON_OR_-")
        return 2
    run_dir = Path(sys.argv[1])
    plain = Path(sys.argv[2])
    gt = Path(sys.argv[3])
    cap = {}
    if sys.argv[4] != "-" and Path(sys.argv[4]).exists():
        cap = json.loads(Path(sys.argv[4]).read_text())
        if "capture" in cap:
            cap = cap["capture"]
    out = score_one(run_dir, plain, gt, cap)
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
