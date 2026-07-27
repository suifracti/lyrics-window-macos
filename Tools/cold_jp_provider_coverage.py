#!/usr/bin/env python3
"""Minimal read-only coverage probe: NetEase / QQ / KuGou for cold JP tracks.

Does not bypass captchas. Prints a coverage table JSON + markdown.
Experimental plugin selection input only.
"""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Tests/fixtures/cold_jp_tracks_20.json"
OUT_JSON = ROOT / "docs/superpowers/specs/2026-07-27-cold-jp-provider-coverage.json"
OUT_MD = ROOT / "docs/superpowers/specs/2026-07-27-cold-jp-provider-coverage.md"

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) SpotifyLyricsCoverage/1.0"


def http_json(url: str, headers: dict | None = None, timeout: float = 10.0):
    """Use curl to avoid broken Python SSL trust stores in some sandboxes."""
    import subprocess
    cmd = [
        "curl", "-sS", "-L", "--max-time", str(int(timeout)),
        "-A", UA,
        "-w", "\n__HTTP_STATUS__:%{http_code}",
    ]
    for k, v in (headers or {}).items():
        cmd.extend(["-H", f"{k}: {v}"])
    cmd.append(url)
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        body = proc.stdout or ""
        if "__HTTP_STATUS__:" in body:
            raw, _, status_part = body.rpartition("__HTTP_STATUS__:")
            code = int(status_part.strip() or "0")
        else:
            raw, code = body, 0
        if proc.returncode != 0 and not raw.strip():
            return None, {"error": proc.stderr.strip() or f"curl exit {proc.returncode}"}
        try:
            return code, json.loads(raw)
        except Exception as e:
            return code, {"error": f"json:{e}", "raw": raw[:300]}
    except Exception as e:
        return None, {"error": str(e)}


def lrclib_has(title: str, artist: str) -> dict:
    q = urllib.parse.urlencode({"track_name": title, "artist_name": artist})
    code, data = http_json(f"https://lrclib.net/api/search?{q}")
    if code != 200 or not isinstance(data, list):
        q2 = urllib.parse.urlencode({"q": f"{title} {artist}"})
        code, data = http_json(f"https://lrclib.net/api/search?{q2}")
    if code != 200 or not isinstance(data, list):
        return {"ok": False, "count": 0, "synced": False}
    # naive filter
    def norm(s):
        return re.sub(r"\s+", "", (s or "").lower())
    hits = []
    for r in data:
        tn = norm(r.get("trackName"))
        an = norm(r.get("artistName"))
        if norm(title) in tn or tn in norm(title):
            if not artist or norm(artist) in an or an in norm(artist) or not an:
                hits.append(r)
    if not hits:
        hits = data[:1] if data else []
    synced = any(bool(h.get("syncedLyrics")) for h in hits)
    plain = any(bool(h.get("plainLyrics")) for h in hits)
    return {"ok": bool(hits) and (synced or plain), "count": len(data), "synced": synced, "plain": plain}


def netease_search(title: str, artist: str) -> dict:
    q = urllib.parse.quote(f"{title} {artist}")
    url = f"https://music.163.com/api/search/get/web?s={q}&type=1&offset=0&limit=8"
    code, data = http_json(url, headers={"Referer": "https://music.163.com/"})
    out = {
        "search_ok": code == 200,
        "track_hit": False,
        "song_id": None,
        "lyric_ok": False,
        "has_lrc": False,
        "has_tlyric": False,
        "has_yrc": False,
        "needs_cookie": False,
        "error": None,
        "candidates": [],
    }
    if code != 200 or not isinstance(data, dict):
        out["error"] = str(data)
        return out
    songs = (data.get("result") or {}).get("songs") or []
    def score(s):
        name = s.get("name") or ""
        arts = ",".join(a.get("name","") for a in s.get("artists") or [])
        sc = 0
        if title in name or name in title: sc += 2
        if artist and (artist in arts or arts in artist): sc += 2
        if "live" in name.lower() or "（live" in name.lower(): sc -= 1
        return sc
    ranked = sorted(songs, key=score, reverse=True)
    out["candidates"] = [
        {"id": s.get("id"), "name": s.get("name"), "artists": [a.get("name") for a in s.get("artists") or []], "duration_ms": s.get("duration")}
        for s in ranked[:5]
    ]
    if not ranked or score(ranked[0]) < 2:
        return out
    best = ranked[0]
    out["track_hit"] = score(best) >= 2
    out["song_id"] = best.get("id")
    if not out["song_id"]:
        return out
    lurl = f"https://music.163.com/api/song/lyric?id={out['song_id']}&lv=1&kv=1&tv=-1&yv=1&yv=1"
    lcode, ldata = http_json(lurl, headers={"Referer": "https://music.163.com/"})
    if lcode != 200 or not isinstance(ldata, dict):
        out["error"] = f"lyric:{ldata}"
        return out
    lrc = ((ldata.get("lrc") or {}).get("lyric") or "").strip()
    tlrc = ((ldata.get("tlyric") or {}).get("lyric") or "").strip()
    yrc = ((ldata.get("yrc") or {}).get("lyric") or "").strip()
    out["lyric_ok"] = bool(lrc)
    out["has_lrc"] = bool(lrc) and ("[" in lrc)
    out["has_tlyric"] = bool(tlrc)
    out["has_yrc"] = bool(yrc)
    out["has_kana"] = False
    out["has_romaji"] = False
    return out


def qq_search(title: str, artist: str) -> dict:
    # public search endpoint often works; lyric often needs session
    w = urllib.parse.quote(f"{title} {artist}")
    url = (
        "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?"
        f"w={w}&format=json&p=1&n=8&cr=1&g_tk=5381"
    )
    code, data = http_json(url, headers={"Referer": "https://y.qq.com/"})
    out = {
        "search_ok": code == 200,
        "track_hit": False,
        "songmid": None,
        "lyric_ok": False,
        "has_lrc": False,
        "has_tlyric": False,
        "has_yrc": False,
        "needs_cookie": False,
        "error": None,
        "candidates": [],
    }
    if code != 200 or not isinstance(data, dict):
        out["error"] = str(data)
        return out
    lst = (((data.get("data") or {}).get("song") or {}).get("list")) or []
    out["candidates"] = [
        {
            "songmid": s.get("songmid"),
            "name": s.get("songname"),
            "artists": [a.get("name") for a in s.get("singer") or []],
            "interval": s.get("interval"),
        }
        for s in lst[:5]
    ]
    if not lst:
        return out
    best = lst[0]
    out["track_hit"] = True
    out["songmid"] = best.get("songmid")
    if not out["songmid"]:
        return out
    # lyric endpoint frequently returns retcode -1310 without cookie
    lurl = (
        "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?"
        f"songmid={out['songmid']}&format=json&nobase64=1&g_tk=5381"
    )
    lcode, ldata = http_json(lurl, headers={"Referer": "https://y.qq.com/"})
    if lcode != 200 or not isinstance(ldata, dict):
        out["error"] = str(ldata)
        out["needs_cookie"] = True
        return out
    if ldata.get("retcode") not in (0, "0", None) and ldata.get("code") not in (0, "0", None):
        out["needs_cookie"] = True
        out["error"] = f"retcode={ldata.get('retcode') or ldata.get('code')}"
        return out
    lyric = (ldata.get("lyric") or "").strip()
    tlyric = (ldata.get("trans") or ldata.get("tlyric") or "").strip()
    out["lyric_ok"] = bool(lyric)
    out["has_lrc"] = "[" in lyric
    out["has_tlyric"] = bool(tlyric)
    return out


def kugou_search(title: str, artist: str) -> dict:
    keyword = urllib.parse.quote(f"{title} {artist}")
    url = (
        "https://mobilecdn.kugou.com/api/v3/search/song?"
        f"format=json&keyword={keyword}&page=1&pagesize=8"
    )
    code, data = http_json(url)
    out = {
        "search_ok": code == 200,
        "track_hit": False,
        "hash": None,
        "lyric_ok": False,
        "has_lrc": False,
        "has_tlyric": False,
        "has_yrc": False,
        "needs_cookie": False,
        "error": None,
        "candidates": [],
    }
    if code != 200 or not isinstance(data, dict):
        out["error"] = str(data)
        return out
    info = ((data.get("data") or {}).get("info")) or []
    out["candidates"] = [
        {
            "hash": s.get("hash") or s.get("hqhash") or s.get("sqhash"),
            "name": s.get("songname") or s.get("filename"),
            "artists": s.get("singername"),
            "duration": s.get("duration"),
        }
        for s in info[:5]
    ]
    if not info:
        return out
    best = info[0]
    out["track_hit"] = True
    h = best.get("hash") or best.get("hqhash")
    out["hash"] = h
    if not h:
        return out
    # lyric search often needs keyword+hash and may 404
    lurl = f"https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword={keyword}&duration={best.get('duration') or ''}&hash={h}"
    lcode, ldata = http_json(lurl)
    if lcode != 200 or not isinstance(ldata, dict):
        out["error"] = str(ldata)
        return out
    cands = ldata.get("candidates") or []
    if not cands:
        out["error"] = "no lyric candidates"
        return out
    # do not download full krc content heavily; mark availability if candidates exist
    out["lyric_ok"] = True
    out["has_lrc"] = True  # kugou often timed
    out["has_yrc"] = any("yrc" in json.dumps(c, ensure_ascii=False).lower() for c in cands[:3])
    return out


def main():
    tracks = json.loads(FIXTURE.read_text())
    rows = []
    for t in tracks:
        title, artist = t["title"], t["artist"]
        print(f"probe {title} / {artist}", file=sys.stderr)
        row = {
            "id": t["id"],
            "title": title,
            "artist": artist,
            "title_script": t.get("title_script"),
            "notes": t.get("notes"),
            "lrclib": lrclib_has(title, artist),
            "netease": netease_search(title, artist),
            "qq": qq_search(title, artist),
            "kugou": kugou_search(title, artist),
        }
        rows.append(row)
        time.sleep(0.35)

    def rate(key, pred):
        vals = [pred(r[key]) for r in rows]
        return sum(1 for v in vals if v), len(vals)

    summary = {
        "lrclib_lyric": rate("lrclib", lambda x: x.get("ok")),
        "netease_track": rate("netease", lambda x: x.get("track_hit")),
        "netease_lyric": rate("netease", lambda x: x.get("lyric_ok")),
        "netease_lrc": rate("netease", lambda x: x.get("has_lrc")),
        "netease_tlyric": rate("netease", lambda x: x.get("has_tlyric")),
        "qq_track": rate("qq", lambda x: x.get("track_hit")),
        "qq_lyric": rate("qq", lambda x: x.get("lyric_ok")),
        "qq_needs_cookie": rate("qq", lambda x: x.get("needs_cookie")),
        "kugou_track": rate("kugou", lambda x: x.get("track_hit")),
        "kugou_lyric": rate("kugou", lambda x: x.get("lyric_ok")),
    }

    # cold subset: lrclib miss
    cold = [r for r in rows if not r["lrclib"].get("ok")]
    cold_summary = {
        "count": len(cold),
        "netease_lyric": sum(1 for r in cold if r["netease"].get("lyric_ok")),
        "qq_lyric": sum(1 for r in cold if r["qq"].get("lyric_ok")),
        "kugou_lyric": sum(1 for r in cold if r["kugou"].get("lyric_ok")),
    }

    # choose first experimental provider by cold lyric hits then total lyric, prefer fewer cookie needs
    scores = {
        "netease": cold_summary["netease_lyric"] * 10 + summary["netease_lyric"][0] * 2 + summary["netease_tlyric"][0],
        "qq": cold_summary["qq_lyric"] * 10 + summary["qq_lyric"][0] * 2 - summary["qq_needs_cookie"][0] * 3,
        "kugou": cold_summary["kugou_lyric"] * 10 + summary["kugou_lyric"][0] * 2,
    }
    winner = max(scores, key=scores.get)

    payload = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "tracks": rows,
        "summary": summary,
        "cold_summary": cold_summary,
        "scores": scores,
        "recommended_first_experimental_provider": winner,
        "caveats": [
            "Undocumented endpoints; experimental plugin only",
            "No captcha bypass attempted",
            "Match quality is heuristic title/artist containment",
            "Aliases improve match rate only; empty sources stay empty",
        ],
    }
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2))

    def frac(pair):
        return f"{pair[0]}/{pair[1]}"

    md = []
    md.append("# 冷门日语曲 Provider 覆盖测试（最小只读）\n")
    md.append(f"生成时间：{payload['generated_at']}\n")
    md.append("样本：`Tests/fixtures/cold_jp_tracks_20.json`（20 首）\n")
    md.append("\n## 总览\n")
    md.append("| 指标 | 命中 |\n|------|------|\n")
    for k, v in summary.items():
        md.append(f"| {k} | {frac(v)} |\n")
    md.append("\n## LRCLIB 失败子集（cold）\n")
    md.append(f"- cold 数：{cold_summary['count']}\n")
    md.append(f"- 网易云 lyric：{cold_summary['netease_lyric']}\n")
    md.append(f"- QQ lyric：{cold_summary['qq_lyric']}\n")
    md.append(f"- 酷狗 lyric：{cold_summary['kugou_lyric']}\n")
    md.append("\n## 评分与推荐\n")
    md.append(f"```json\n{json.dumps(scores, ensure_ascii=False, indent=2)}\n```\n")
    md.append(f"\n**推荐第一家实验 Provider：`{winner}`**\n")
    md.append("\n## 逐曲摘要\n")
    md.append("| id | title | artist | LRCLIB | 网易云词 | QQ词 | 酷狗词 |\n|----|-------|--------|--------|----------|------|--------|\n")
    for r in rows:
        md.append(
            f"| {r['id']} | {r['title']} | {r['artist']} | "
            f"{'Y' if r['lrclib'].get('ok') else 'N'} | "
            f"{'Y' if r['netease'].get('lyric_ok') else 'N'} | "
            f"{'Y' if r['qq'].get('lyric_ok') else 'N'} | "
            f"{'Y' if r['kugou'].get('lyric_ok') else 'N'} |\n"
        )
    md.append("\n## 能力备注\n")
    md.append("- 网易云：公开网页 lyric 常含 LRC + tlyric；yrc 视曲目；无需登录的只读样例较多。\n")
    md.append("- QQ：搜索较易；歌词接口常 `retcode -1310`/需 Cookie。\n")
    md.append("- 酷狗：搜索可用；歌词 candidates 有时有，下载/签名不稳定。\n")
    md.append("- 假名/罗马音：三家均不保证独立假名轨；本地词典层补全。\n")
    md.append("- **多别名不能解决来源无词。**\n")
    md.append("\n## 下一步\n")
    md.append(f"只实现 `{winner}` 实验插件，隔离于核心默认路径之外。\n")
    OUT_MD.write_text("".join(md))
    print(json.dumps({"winner": winner, "scores": scores, "cold": cold_summary, "out": str(OUT_MD)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
