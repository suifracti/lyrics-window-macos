#!/usr/bin/env python3
"""Exhaustive single-track source audit: 水曜日の約束 / Kawasaki.Rio"""
from __future__ import annotations
import json, re, subprocess, urllib.parse, time
from pathlib import Path

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) SpotifyLyricsProbe/1.0"
TITLE = "水曜日の約束"
ARTIST = "Kawasaki.Rio"
ROOT = Path(__file__).resolve().parents[1]
OUT_JSON = ROOT / "docs/superpowers/specs/2026-07-27-suiyoubi-single-track-source-audit.json"
OUT_MD = ROOT / "docs/superpowers/specs/2026-07-27-suiyoubi-single-track-source-audit.md"

QUERIES = [
    "水曜日の約束",
    "水曜日の約束 Kawasaki.Rio",
    "水曜日の約束 Kawasaki Rio",
    "すいようびのやくそく",
    "すいようびのやくそく Kawasaki.Rio",
    "suiyoubi no yakusoku",
    "suiyoubi no yakusoku Kawasaki Rio",
    "suiyobi no yakusoku",
    "Wednesday Promise",
    "Wednesday Promise Kawasaki Rio",
    "Kawasaki.Rio 水曜日の約束",
    "kawasaki.rio",
    "Kawasaki Rio",
    "カワサキリオ",
    "かわさき りお",
]

def curl(url: str, headers: dict | None = None, timeout: int = 10) -> tuple[int, str, str]:
    cmd = ["curl", "-sS", "-L", "--max-time", str(timeout), "-A", UA, "-w", "\n__HTTP__:%{http_code}"]
    for k, v in (headers or {}).items():
        cmd += ["-H", f"{k}: {v}"]
    cmd.append(url)
    p = subprocess.run(cmd, capture_output=True, text=True)
    body = p.stdout or ""
    if "__HTTP__:" in body:
        raw, _, st = body.rpartition("__HTTP__:")
        code = int(st.strip() or 0)
    else:
        raw, code = body, 0
    return code, raw, (p.stderr or "").strip()

def curl_json(url: str, headers: dict | None = None, timeout: int = 10):
    code, raw, err = curl(url, headers, timeout)
    try:
        return code, json.loads(raw), err
    except Exception as e:
        return code, {"_raw": raw[:400], "_parse_error": str(e)}, err

def looks_title(name: str) -> bool:
    n = name or ""
    nl = n.lower()
    return ("約束" in n) or ("水曜日" in n) or ("suiyoubi" in nl) or ("yakusoku" in nl) or ("wednesday" in nl and "promise" in nl)

def looks_artist(arts) -> bool:
    if isinstance(arts, str):
        arts = [arts]
    joined = " ".join(arts or [])
    jl = joined.lower().replace(" ", "")
    return ("kawasaki" in jl) or ("rio" in jl) or ("カワサキ" in joined) or ("かわさき" in joined)

def main():
    R = {
        "track": {"title": TITLE, "artist": ARTIST},
        "queries": QUERIES,
        "sources": {},
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }

    # LOCAL
    local_dirs = [
        Path.home() / "Music/SpotifyLyrics/Lyrics",
        Path.home() / "Library/Application Support/SpotifyLyrics/Lyrics",
        ROOT / "Lyrics",
    ]
    local_hits = []
    for d in local_dirs:
        if not d.exists():
            continue
        for f in d.rglob("*"):
            if f.suffix.lower() not in {".lrc", ".txt", ".ttml"}:
                continue
            blob = f.name + " " + str(f)
            if any(k in blob for k in ["約束", "suiyoubi", "yakusoku", "wednesday", "Kawasaki", "kawasaki", "Rio"]):
                local_hits.append(str(f))
    R["sources"]["local"] = {
        "found_correct_track": bool(local_hits),
        "has_lyric_body": bool(local_hits),
        "has_kanji_original": bool(local_hits),
        "has_kana": None,
        "has_romaji": None,
        "has_line_timing": None,
        "programmatic_read_ok": True,
        "hits": local_hits,
        "dirs_checked": [str(d) for d in local_dirs],
    }

    # LRCLIB - limited unique URLs
    lrclib_urls = []
    for q in QUERIES:
        lrclib_urls.append(("q", q, f"https://lrclib.net/api/search?{urllib.parse.urlencode({'q': q})}"))
    for tn, an in [
        (TITLE, ARTIST),
        (TITLE, "Kawasaki Rio"),
        ("suiyoubi no yakusoku", ARTIST),
        ("suiyoubi no yakusoku", "Kawasaki Rio"),
        ("Wednesday Promise", ARTIST),
        ("Wednesday Promise", "Kawasaki Rio"),
        ("すいようびのやくそく", ARTIST),
    ]:
        lrclib_urls.append(("structured", f"{tn}|{an}", f"https://lrclib.net/api/search?{urllib.parse.urlencode({'track_name': tn, 'artist_name': an})}"))
        lrclib_urls.append(("get", f"{tn}|{an}", f"https://lrclib.net/api/get?{urllib.parse.urlencode({'track_name': tn, 'artist_name': an})}"))

    hits = []
    gets = []
    seen_ids = set()
    for kind, q, url in lrclib_urls:
        print("lrclib", kind, q, flush=True)
        code, data, err = curl_json(url)
        if kind == "get":
            gets.append({
                "query": q, "http": code,
                "has_plain": bool(isinstance(data, dict) and data.get("plainLyrics")),
                "has_synced": bool(isinstance(data, dict) and data.get("syncedLyrics")),
                "trackName": (data or {}).get("trackName") if isinstance(data, dict) else None,
                "artistName": (data or {}).get("artistName") if isinstance(data, dict) else None,
                "status": (data or {}).get("statusCode") if isinstance(data, dict) else None,
                "error": err or (data if not isinstance(data, dict) else None),
            })
            continue
        if code == 200 and isinstance(data, list):
            for r in data[:8]:
                rid = r.get("id")
                if rid in seen_ids:
                    continue
                seen_ids.add(rid)
                hits.append({
                    "id": rid,
                    "trackName": r.get("trackName"),
                    "artistName": r.get("artistName"),
                    "duration": r.get("duration"),
                    "has_plain": bool(r.get("plainLyrics")),
                    "has_synced": bool(r.get("syncedLyrics")),
                    "preview": (r.get("plainLyrics") or r.get("syncedLyrics") or "")[:100],
                    "via": q,
                })
    correct = [h for h in hits if looks_title(h.get("trackName") or "") and looks_artist(h.get("artistName") or "")]
    body = [h for h in correct if h.get("has_plain") or h.get("has_synced")]
    R["sources"]["lrclib"] = {
        "found_correct_track": bool(correct),
        "has_lyric_body": bool(body),
        "has_kanji_original": bool(body),  # if body exists likely includes original script
        "has_kana": False,
        "has_romaji": False,
        "has_line_timing": any(h.get("has_synced") for h in body),
        "programmatic_read_ok": True,
        "correct_hits": correct,
        "other_hits_sample": hits[:10],
        "get_attempts": gets,
    }

    # NetEase
    ne_songs = []
    seen = set()
    for q in QUERIES:
        print("netease search", q, flush=True)
        url = f"https://music.163.com/api/search/get/web?{urllib.parse.urlencode({'s': q, 'type': 1, 'limit': 8})}"
        code, data, err = curl_json(url, {"Referer": "https://music.163.com/"})
        for s in (((data or {}).get("result") or {}).get("songs") or [] if isinstance(data, dict) else []):
            sid = s.get("id")
            if sid in seen:
                continue
            seen.add(sid)
            ne_songs.append({
                "id": sid,
                "name": s.get("name"),
                "artists": [a.get("name") for a in (s.get("artists") or [])],
                "album": (s.get("album") or {}).get("name"),
                "duration_ms": s.get("duration"),
                "via": q,
            })
    ne_correct = [s for s in ne_songs if looks_title(s["name"] or "") and looks_artist(s["artists"])]
    # always include top title matches even if artist fuzzy
    ne_title_only = [s for s in ne_songs if looks_title(s["name"] or "")]
    targets = ne_correct or ne_title_only[:5]
    ne_lyrics = []
    for s in targets[:8]:
        print("netease lyric", s["id"], s["name"], flush=True)
        url = f"https://music.163.com/api/song/lyric?id={s['id']}&lv=1&tv=-1&kv=1"
        code, data, err = curl_json(url, {"Referer": "https://music.163.com/"})
        lrc = (((data or {}).get("lrc") or {}).get("lyric") or "").strip() if isinstance(data, dict) else ""
        tlrc = (((data or {}).get("tlyric") or {}).get("lyric") or "").strip() if isinstance(data, dict) else ""
        yrc = (((data or {}).get("yrc") or {}).get("lyric") or "").strip() if isinstance(data, dict) else ""
        ne_lyrics.append({
            **s,
            "http": code,
            "has_text": bool(lrc),
            "has_tlyric": bool(tlrc),
            "has_yrc": bool(yrc),
            "timed": "[" in lrc,
            "preview": lrc[:160],
        })
    ne_body = [x for x in ne_lyrics if x["has_text"] and looks_title(x["name"] or "") and looks_artist(x["artists"])]
    R["sources"]["netease"] = {
        "found_correct_track": bool(ne_correct),
        "has_lyric_body": bool(ne_body),
        "has_kanji_original": bool(ne_body),
        "has_kana": False,
        "has_romaji": False,
        "has_line_timing": any(x.get("timed") for x in ne_body),
        "has_translation": any(x.get("has_tlyric") for x in ne_body),
        "programmatic_read_ok": True,
        "correct_candidates": ne_correct[:5],
        "title_matches": ne_title_only[:8],
        "lyrics": ne_lyrics,
        "notes": "catalog hit may still have empty lrc",
    }

    # QQ
    qq_songs = []
    seen = set()
    for q in QUERIES:
        print("qq search", q, flush=True)
        url = "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?" + urllib.parse.urlencode({
            "w": q, "format": "json", "p": 1, "n": 8, "cr": 1, "g_tk": 5381
        })
        code, data, err = curl_json(url, {"Referer": "https://y.qq.com/"})
        for s in ((((data or {}).get("data") or {}).get("song") or {}).get("list") or [] if isinstance(data, dict) else []):
            mid = s.get("songmid")
            if not mid or mid in seen:
                continue
            seen.add(mid)
            qq_songs.append({
                "songmid": mid,
                "songname": s.get("songname"),
                "artists": [a.get("name") for a in (s.get("singer") or [])],
                "interval": s.get("interval"),
                "albumname": s.get("albumname"),
                "via": q,
            })
    qq_correct = [s for s in qq_songs if looks_title(s["songname"] or "") and looks_artist(s["artists"])]
    qq_title = [s for s in qq_songs if looks_title(s["songname"] or "")]
    qq_lyrics = []
    for s in (qq_correct or qq_title)[:8]:
        print("qq lyric", s["songmid"], s["songname"], flush=True)
        url = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?" + urllib.parse.urlencode({
            "songmid": s["songmid"], "format": "json", "nobase64": 1, "g_tk": 5381
        })
        code, data, err = curl_json(url, {"Referer": "https://y.qq.com/"})
        ret = data.get("retcode", data.get("code")) if isinstance(data, dict) else None
        lyric = ""
        if isinstance(data, dict):
            lyric = (data.get("lyric") or "")
            if lyric and "[" not in lyric[:20]:
                import base64
                try:
                    lyric = base64.b64decode(lyric).decode("utf-8", "replace")
                except Exception:
                    pass
        lyric = (lyric or "").strip()
        qq_lyrics.append({
            **s, "http": code, "retcode": ret, "has_text": bool(lyric),
            "timed": "[" in lyric, "preview": lyric[:160],
            "blocked": (ret not in (0, "0", None)) and not lyric,
        })
    qq_body = [x for x in qq_lyrics if x["has_text"] and looks_title(x["songname"] or "") and looks_artist(x["artists"])]
    R["sources"]["qq"] = {
        "found_correct_track": bool(qq_correct),
        "has_lyric_body": bool(qq_body),
        "has_kanji_original": bool(qq_body),
        "has_kana": False,
        "has_romaji": False,
        "has_line_timing": any(x.get("timed") for x in qq_body),
        "programmatic_read_ok": bool(qq_body),
        "correct_candidates": qq_correct[:5],
        "lyrics": qq_lyrics,
        "notes": "retcode -1310/-1901 common without cookie",
    }

    # Kugou
    kg_songs = []
    seen = set()
    for q in QUERIES[:10]:
        print("kugou search", q, flush=True)
        for url in [
            "https://mobilecdn.kugou.com/api/v3/search/song?" + urllib.parse.urlencode({"format": "json", "keyword": q, "page": 1, "pagesize": 8}),
            "https://songsearch.kugou.com/song_search_v2?" + urllib.parse.urlencode({"keyword": q, "page": 1, "pagesize": 8, "userid": -1, "platform": "WebFilter"}),
        ]:
            code, data, err = curl_json(url)
            info = []
            if isinstance(data, dict):
                info = ((data.get("data") or {}).get("info")) or ((data.get("data") or {}).get("lists")) or []
            for s in info:
                h = s.get("FileHash") or s.get("hash") or s.get("HQFileHash")
                name = s.get("SongName") or s.get("songname") or s.get("FileName") or s.get("filename")
                singer = s.get("SingerName") or s.get("singername")
                key = h or f"{name}|{singer}"
                if not key or key in seen:
                    continue
                seen.add(key)
                kg_songs.append({
                    "hash": h, "name": name, "singer": singer,
                    "duration": s.get("Duration") or s.get("duration"),
                    "via": q, "http": code,
                })
    kg_correct = [s for s in kg_songs if looks_title(s.get("name") or "") and looks_artist(s.get("singer") or "")]
    kg_lyrics = []
    for s in (kg_correct or kg_songs)[:6]:
        if not s.get("hash"):
            continue
        print("kugou lyric cand", s.get("name"), flush=True)
        url = "https://krcs.kugou.com/search?" + urllib.parse.urlencode({
            "ver": 1, "man": "yes", "client": "mobi",
            "keyword": f"{s.get('name')} {s.get('singer')}",
            "duration": s.get("duration") or "",
            "hash": s["hash"],
        })
        code, data, err = curl_json(url)
        cands = (data or {}).get("candidates") if isinstance(data, dict) else None
        # try download first candidate if id/accesskey present - may fail
        body = None
        if cands:
            c0 = cands[0]
            did, ak = c0.get("id"), c0.get("accesskey")
            if did and ak:
                durl = "https://lyrics.kugou.com/download?" + urllib.parse.urlencode({
                    "ver": 1, "client": "pc", "id": did, "accesskey": ak, "fmt": "lrc", "charset": "utf8"
                })
                dcode, ddata, derr = curl_json(durl)
                content = (ddata or {}).get("content") if isinstance(ddata, dict) else None
                if content:
                    import base64
                    try:
                        body = base64.b64decode(content).decode("utf-8", "replace")
                    except Exception:
                        body = content if isinstance(content, str) else None
        kg_lyrics.append({
            **s, "cand_http": code, "candidates": len(cands or []),
            "has_text": bool(body), "preview": (body or "")[:160],
            "programmatic_body": bool(body),
        })
    kg_body = [x for x in kg_lyrics if x.get("has_text") and looks_title(x.get("name") or "") and looks_artist(x.get("singer") or "")]
    R["sources"]["kugou"] = {
        "found_correct_track": bool(kg_correct),
        "has_lyric_body": bool(kg_body),
        "has_kanji_original": bool(kg_body),
        "has_kana": False,
        "has_romaji": False,
        "has_line_timing": any("[" in (x.get("preview") or "") for x in kg_body),
        "programmatic_read_ok": bool(kg_body),
        "songs": kg_songs[:10],
        "correct_candidates": kg_correct[:5],
        "lyrics": kg_lyrics,
    }

    # WEB sites (no bypass)
    def page(url: str, timeout=12):
        code, raw, err = curl(url, timeout=timeout)
        title = ""
        m = re.search(r"<title[^>]*>(.*?)</title>", raw or "", re.I | re.S)
        if m:
            title = re.sub(r"\s+", " ", m.group(1)).strip()
        cf = any(x in (raw or "") for x in ["Just a moment", "cf-browser-verification", "challenge-platform", "Checking your browser"])
        # crude body presence: long japanese lyric-like block without claiming scrape success under CF
        has_lyric_word = any(x in (raw or "") for x in ["歌詞", "Lyrics", "lyric"])
        return {
            "url": url, "http": code, "title": title[:180], "cloudflare": cf,
            "mentions_lyrics": has_lyric_word, "bytes": len(raw or ""),
            "programmatic_read_ok": (not cf) and code == 200 and not cf,
            "error": err[:160] if err else None,
        }

    web = {}
    web_targets = {
        "uta_net_search": f"https://www.uta-net.com/search/?Keyword={urllib.parse.quote(TITLE)}",
        "uta_net_search_artist": f"https://www.uta-net.com/search/?Keyword={urllib.parse.quote(TITLE + ' Kawasaki')}",
        "utatime_search": f"https://www.lyrical-nonsense.com/?s={urllib.parse.quote(TITLE)}",
        "utatime_global": f"https://www.lyrical-nonsense.com/global/?s={urllib.parse.quote('suiyoubi yakusoku Kawasaki')}",
        "utaten_title": f"https://utaten.com/search?sort=popular_sort_asc&title={urllib.parse.quote(TITLE)}",
        "utaten_both": f"https://utaten.com/search?artist_name={urllib.parse.quote('Kawasaki')}&title={urllib.parse.quote(TITLE)}",
        "jlyric": f"https://search.j-lyric.net/index.php?kt={urllib.parse.quote(TITLE)}&ct=2&ka={urllib.parse.quote('Kawasaki')}&ca=2",
        "jlyric_title": f"https://search.j-lyric.net/index.php?kt={urllib.parse.quote(TITLE)}&ct=2",
        "awa_search": f"https://awa.fm/search?q={urllib.parse.quote(TITLE)}",
        "youtube_search": f"https://www.youtube.com/results?search_query={urllib.parse.quote(TITLE + ' ' + ARTIST)}",
        "ddg_jp": f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(TITLE + ' ' + ARTIST + ' 歌詞')}",
        "ddg_en": f"https://html.duckduckgo.com/html/?q={urllib.parse.quote('suiyoubi no yakusoku Kawasaki.Rio lyrics')}",
    }
    for k, u in web_targets.items():
        print("web", k, flush=True)
        web[k] = page(u)

    # extract promising links from DDG
    for key in ["ddg_jp", "ddg_en"]:
        code, raw, err = curl(web[key]["url"], timeout=12)
        links = []
        for u in re.findall(r"uddg=([^&\"]+)", raw or ""):
            links.append(urllib.parse.unquote(u))
        for u in re.findall(r'href=\"(https?://[^\"]+)\"', raw or ""):
            if "duckduckgo" not in u:
                links.append(u)
        keep = []
        for u in links:
            lu = u.lower()
            if any(x in lu for x in ["uta-net", "utaten", "utatime", "lyrical-nonsense", "j-lyric", "youtube.com/watch", "genius.com", "music.apple", "spotify.com"]):
                keep.append(u)
        web[key]["links"] = list(dict.fromkeys(keep))[:15]

    # Genius API
    print("genius", flush=True)
    code, raw, err = curl(
        f"https://genius.com/api/search/song?q={urllib.parse.quote(TITLE + ' ' + ARTIST)}",
        {"Accept": "application/json"},
    )
    genius_hits = []
    try:
        g = json.loads(raw)
        for h in (((g.get("response") or {}).get("sections") or [{}])[0].get("hits") or [])[:8]:
            res = h.get("result") or {}
            genius_hits.append({
                "title": res.get("title"),
                "artist": (res.get("primary_artist") or {}).get("name"),
                "url": res.get("url"),
            })
    except Exception as e:
        genius_hits = [{"error": str(e), "raw": raw[:200]}]
    web["genius_api"] = {"http": code, "hits": genius_hits, "programmatic_body_read": False, "notes": "page may exist; body scrape not authorized here"}

    # Follow a few non-CF lyric site links if present
    followed = []
    for key in ["ddg_jp", "ddg_en"]:
        for u in web[key].get("links") or []:
            if any(x in u for x in ["uta-net.com/song", "utaten.com/lyric", "lyrical-nonsense.com/lyrics", "j-lyric.net/artist", "j-lyric.net/song"]):
                print("follow", u, flush=True)
                info = page(u)
                info["from"] = key
                # if not CF, check for substantial JP text lines
                if not info["cloudflare"] and info["http"] == 200:
                    code2, raw2, _ = curl(u)
                    # count lines of japanese without claiming full lyric rights compliance for auto use
                    jp_lines = [ln for ln in re.split(r"<br\s*/?>|\n", raw2) if re.search(r"[\u3040-\u30ff\u4e00-\u9fff]{4,}", ln or "")]
                    info["jp_line_like_count"] = len(jp_lines)
                    info["has_possible_body_in_html"] = len(jp_lines) >= 5
                    # STILL mark programmatic_read_ok False for uta-net due to terms even if HTML visible
                    if "uta-net.com" in u:
                        info["programmatic_read_ok"] = False
                        info["rights"] = "termsRestrictCopy"
                    elif info.get("cloudflare"):
                        info["programmatic_read_ok"] = False
                    else:
                        # UtaTen/J-Lyric/UtaTime: discovery only this round unless clearly public domain - keep false for auto body
                        info["programmatic_read_ok"] = False
                        info["rights"] = "discovery_only_this_round"
                followed.append(info)
    web["followed_lyric_pages"] = followed

    R["sources"]["web"] = web
    for name, key in [
        ("uta_net", "uta_net_search"),
        ("utatime", "utatime_search"),
        ("utaten", "utaten_title"),
        ("jlyric", "jlyric"),
        ("awa", "awa_search"),
        ("youtube", "youtube_search"),
    ]:
        p = web.get(key) or {}
        R["sources"][name] = {
            "found_correct_track": None,  # unknown without body parse
            "has_lyric_body": False,
            "has_kanji_original": False,
            "has_kana": False,
            "has_romaji": False,
            "has_line_timing": False,
            "programmatic_read_ok": False,
            "page": p,
            "notes": "no auto body; CF/terms/no public API",
        }

    # artist/label/youtube description - from ddg youtube links only description not fetched via Innertube
    yt_links = [u for u in (web.get("ddg_jp", {}).get("links") or []) + (web.get("ddg_en", {}).get("links") or []) if "youtube.com/watch" in u]
    R["sources"]["official_or_youtube"] = {
        "youtube_links": list(dict.fromkeys(yt_links))[:8],
        "has_lyric_body": False,
        "programmatic_read_ok": False,
        "notes": "description not programmatically fetched without YouTube API; manual check needed",
    }

    # DECISION
    programmable_bodies = []
    for src in ["local", "lrclib", "netease", "qq", "kugou"]:
        s = R["sources"][src]
        if s.get("has_lyric_body") and s.get("programmatic_read_ok", True):
            programmable_bodies.append(src)

    decision = {
        "programmable_body_sources": programmable_bodies,
        "outcome": "hasTextSource" if programmable_bodies else "noTextSource",
        "next_step": "import_best_body" if programmable_bodies else "asr_fallback",
        "do_not_add_more_blind_queries": not bool(programmable_bodies),
    }
    R["decision"] = decision

    OUT_JSON.write_text(json.dumps(R, ensure_ascii=False, indent=2))

    # markdown
    lines = []
    lines.append("# 单曲来源穷尽：水曜日の約束 / Kawasaki.Rio\n\n")
    lines.append(f"生成：{R['generated_at']}\n\n")
    lines.append("## 查询变体\n\n")
    for q in QUERIES:
        lines.append(f"- `{q}`\n")
    lines.append("\n## 结果矩阵\n\n")
    lines.append("| 来源 | 正确歌曲 | 歌词正文 | 汉字原文 | 假名 | 罗马音 | 逐行轴 | 程序可读 |\n")
    lines.append("|------|----------|----------|----------|------|--------|--------|----------|\n")
    def yn(v):
        if v is True: return "Y"
        if v is False: return "N"
        return "?"
    order = ["local","lrclib","netease","qq","kugou","uta_net","utatime","utaten","jlyric","awa","youtube","official_or_youtube"]
    labels = {
        "local":"Local","lrclib":"LRCLIB","netease":"网易云","qq":"QQ音乐","kugou":"酷狗",
        "uta_net":"Uta-Net","utatime":"UtaTime","utaten":"UtaTen","jlyric":"J-Lyric","awa":"AWA",
        "youtube":"YouTube搜索","official_or_youtube":"官网/YT说明",
    }
    for k in order:
        s = R["sources"].get(k) or {}
        lines.append(
            f"| {labels[k]} | {yn(s.get('found_correct_track'))} | {yn(s.get('has_lyric_body'))} | "
            f"{yn(s.get('has_kanji_original'))} | {yn(s.get('has_kana'))} | {yn(s.get('has_romaji'))} | "
            f"{yn(s.get('has_line_timing'))} | {yn(s.get('programmatic_read_ok'))} |\n"
        )
    lines.append("\n## 决策\n\n")
    lines.append(f"- **outcome**: `{decision['outcome']}`\n")
    lines.append(f"- **programmable_body_sources**: {decision['programmable_body_sources'] or '[]'}\n")
    lines.append(f"- **next_step**: `{decision['next_step']}`\n")
    lines.append("\n### 关键细节\n\n")
    # netease detail
    ne = R["sources"]["netease"]
    lines.append("**网易云**\n")
    for s in ne.get("correct_candidates") or []:
        lines.append(f"- track id={s['id']} name={s['name']} artists={s['artists']} duration_ms={s['duration_ms']}\n")
    for s in ne.get("lyrics") or []:
        lines.append(f"- lyric id={s['id']} has_text={s['has_text']} timed={s['timed']} preview={s.get('preview')!r}\n")
    lines.append("\n**QQ**\n")
    for s in (R["sources"]["qq"].get("lyrics") or []):
        lines.append(f"- {s.get('songmid')} {s.get('songname')} retcode={s.get('retcode')} has_text={s.get('has_text')} blocked={s.get('blocked')}\n")
    lines.append("\n**LRCLIB** correct_hits=" + str(len(R["sources"]["lrclib"].get("correct_hits") or [])) + "\n")
    lines.append("\n**Web followed**\n")
    for f in web.get("followed_lyric_pages") or []:
        lines.append(f"- {f.get('url')} cf={f.get('cloudflare')} http={f.get('http')} jp_lines={f.get('jp_line_like_count')} rights={f.get('rights')}\n")
    lines.append("\n## 规则\n\n")
    lines.append("- 「有歌曲页面」≠「有歌词正文」。\n")
    lines.append("- 不绕过登录/验证码/反爬。\n")
    lines.append("- Uta-Net 等即使 HTML 可见，本轮仍不作为程序读取正文来源。\n")
    if decision["outcome"] == "noTextSource":
        lines.append("\n**结论：noTextSource → 进入 ASR fallback（本地音频导入）。**\n")
    else:
        lines.append("\n**结论：存在可程序读取正文 → 采用最高匹配正文并补假名/罗马音。**\n")
    OUT_MD.write_text("".join(lines))
    print(json.dumps(decision, ensure_ascii=False))
    print("wrote", OUT_JSON)
    print("wrote", OUT_MD)

if __name__ == "__main__":
    main()
