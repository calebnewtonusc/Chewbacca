"""Wistia caption and asset access.

Thinkific hosts its video on Wistia, and a Wistia hashed id is a public
handle: given the id, captions and media metadata need no course session.
That is what makes the expensive half of this pipeline runnable outside the
browser.
"""
from __future__ import annotations

import json
import re
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/153.0 Safari/537.36"

CAPTION_URL = "https://fast.wistia.com/embed/captions/{id}.json"
MEDIA_URL = "https://fast.wistia.net/embed/medias/{id}.json"


def _get(url: str, timeout: int = 30) -> bytes | None:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
        return None


def captions(video_id: str) -> str | None:
    """Return caption text for a video, or None when it has none.

    Wistia serves captions as one JSON array per language, each carrying a
    WebVTT-ish blob under `text`. English wins when several exist; otherwise
    the first track does, because a non-English track beats no transcript.
    """
    raw = _get(CAPTION_URL.format(id=video_id))
    if not raw:
        return None
    try:
        tracks = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(tracks, list) or not tracks:
        return None

    track = next(
        (t for t in tracks if str(t.get("language", "")).lower() in ("eng", "en", "english")),
        tracks[0],
    )
    text = track.get("text") or track.get("hash", {}).get("text")
    return text or None


def media(video_id: str) -> dict | None:
    raw = _get(MEDIA_URL.format(id=video_id))
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def best_audio_asset(video_id: str) -> str | None:
    """Smallest playable asset URL, for the whisper fallback.

    Transcription only needs audio, so the cheapest mp4 beats the largest:
    downloading a 1080p original to throw away every pixel wastes bandwidth
    and whisper downsamples to 16 kHz regardless.
    """
    payload = media(video_id)
    if not payload:
        return None
    assets = (payload.get("media") or {}).get("assets") or []
    playable = [
        a for a in assets
        if a.get("url") and a.get("type") in ("original", "iphone_video", "mp4_video", "md_mp4_video", "sd_mp4_video")
    ]
    if not playable:
        playable = [a for a in assets if a.get("url")]
    if not playable:
        return None
    playable.sort(key=lambda a: a.get("size") or 1 << 62)
    # Wistia's `.bin` suffix is the raw asset; swapping it for .mp4 is what
    # their own player does and is what makes ffmpeg willing to open it.
    return re.sub(r"\.bin$", ".mp4", playable[0]["url"])


_TIMECODE = re.compile(r"^\d\d:\d\d:\d\d[.,]\d\d\d\s*-->")
_CUE_NUM = re.compile(r"^\d+$")
_TAGS = re.compile(r"<[^>]+>")


def vtt_to_text(vtt: str) -> str:
    """Flatten WebVTT or SRT into prose, dropping cues, tags and duplicates.

    Wistia repeats a caption line across consecutive cues when a phrase spans
    them, so de-duplicating against the previous line is what keeps the output
    readable rather than stuttering.
    """
    out: list[str] = []
    for line in vtt.splitlines():
        line = line.strip()
        if not line or line in ("WEBVTT", "NOTE"):
            continue
        if _TIMECODE.match(line) or _CUE_NUM.match(line) or line.startswith("WEBVTT"):
            continue
        line = _TAGS.sub("", line).strip()
        if line and (not out or out[-1] != line):
            out.append(line)
    return " ".join(out)
