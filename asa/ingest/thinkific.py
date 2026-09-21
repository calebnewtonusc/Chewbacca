"""Thinkific course-player helpers.

The course player is a JSON API sitting behind the same session cookie the
browser uses. Nothing here opens a network connection: the authenticated
fetch happens inside the signed-in browser tab (see fetch_in_browser.js) and
lands on disk as raw JSON. This module only parses what came back, so it is
testable without an account.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field


@dataclass
class Lesson:
    content_id: int
    slug: str
    name: str
    kind: str
    position: int
    chapter_name: str
    chapter_position: int
    video_id: str | None = None
    duration: float | None = None

    @property
    def module_dir(self) -> str:
        return f"{self.chapter_position:02d}-{slugify(self.chapter_name)}"

    @property
    def file_stem(self) -> str:
        return f"{self.position:02d}-{slugify(self.name)}"


def slugify(text: str) -> str:
    text = re.sub(r"[^\w\s-]", "", text.lower()).strip()
    return re.sub(r"[\s_-]+", "-", text)[:60].strip("-") or "untitled"


def parse_course(payload: dict) -> list[Lesson]:
    """Flatten a course payload into an ordered lesson list.

    Thinkific returns chapters and contents as sibling arrays joined by id
    rather than as a nested tree, and chapter order lives in a separate
    chapter_ids array on the course. Both have to be stitched back together.
    """
    chapters = {c["id"]: c for c in payload.get("chapters", [])}
    course = payload.get("course", {})
    order = {cid: i for i, cid in enumerate(course.get("chapter_ids", []))}
    lessons: list[Lesson] = []

    for content in payload.get("contents", []):
        chapter = chapters.get(content.get("chapter_id"), {})
        lessons.append(
            Lesson(
                content_id=content["id"],
                slug=content.get("slug", ""),
                name=content.get("name", "Untitled"),
                kind=content.get("contentable_type", "Unknown"),
                position=content.get("position", 0),
                chapter_name=chapter.get("name", "Uncategorized"),
                chapter_position=order.get(chapter.get("id"), 98) + 1,
            )
        )

    lessons.sort(key=lambda l: (l.chapter_position, l.position))
    return lessons


# A Wistia hashed id is 10 lowercase alphanumerics. Anchoring on the known
# key names first and only then on a bare URL keeps this from matching the
# analytics and account ids that also appear in the same payload.
_ID_KEYS = re.compile(
    r'"(?:wistia_identifier|video_identifier|identifier)"\s*:\s*"([a-z0-9]{8,12})"'
)
_ID_URL = re.compile(r"wistia(?:\.net|\.com)/(?:embed/)?(?:medias/)?([a-z0-9]{8,12})")


def find_video(content_payload: dict) -> tuple[str | None, float | None]:
    """Pull the Wistia hashed id and duration out of a course_contents payload."""
    for lesson in content_payload.get("lessons", []) or []:
        vid = lesson.get("wistia_identifier") or lesson.get("video_identifier")
        if vid:
            return vid, lesson.get("duration")

    blob = json.dumps(content_payload)
    match = _ID_KEYS.search(blob) or _ID_URL.search(blob)
    duration = None
    dur_match = re.search(r'"duration"\s*:\s*([0-9.]+)', blob)
    if dur_match:
        duration = float(dur_match.group(1))
    return (match.group(1) if match else None), duration
