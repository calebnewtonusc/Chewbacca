"""Decode the attributedBody blob in Messages' chat.db.

On Ventura and later, most message bodies are NULL in `text` and live in
`attributedBody` instead: an NSArchiver "typedstream", not a plist and not
NSKeyedArchiver, so plistlib cannot touch it.

Measured on a real library 2026-09-04: 431 of the last 500 messages had NULL
text and 498 had a blob. A reader that ignores this loses ~86% of the corpus,
and nearly everything the user themselves sent.

Layout, from the bytes:
    \\x04\\x0bstreamtyped ... NSString\\x01\\x94\\x84\\x01+ <len> <utf-8 bytes> \\x86
`+` (0x2B) is the typedstream code for a C string. The length is one byte, or
0x81 followed by uint16 LE, or 0x82 followed by uint32 LE.
"""

# The byte after NSString\x01 is a typedstream back-reference and varies:
# 0x94 for NSAttributedString, 0x95 when the payload is an
# NSMutableAttributedString. Hardcoding 0x94 silently drops every edited or
# mutable message, which on a real library is a few percent of the corpus.
import re
MARKER_RE = re.compile(rb"NSString\x01[\x94-\x9f]\x84\x01\+")


def _read_length(blob, i):
    """Return (length, next_index) for typedstream's variable-width length."""
    n = blob[i]
    if n == 0x81:
        return int.from_bytes(blob[i + 1:i + 3], "little"), i + 3
    if n == 0x82:
        return int.from_bytes(blob[i + 1:i + 5], "little"), i + 5
    if n == 0x83:
        return int.from_bytes(blob[i + 1:i + 9], "little"), i + 9
    return n, i + 1


def decode(blob):
    """Extract the message text, or None if there is none to extract."""
    if not blob:
        return None
    if isinstance(blob, str):
        blob = blob.encode("utf-8", "surrogateescape")

    m = MARKER_RE.search(blob)
    if m is None:
        # Fall back to the raw type code after the class name.
        idx = blob.find(b"NSString")
        if idx == -1:
            return None
        plus = blob.find(b"\x01+", idx)
        if plus == -1:
            return None
        i = plus + 2
    else:
        i = m.end()

    if i >= len(blob):
        return None

    length, i = _read_length(blob, i)
    if length <= 0 or i + length > len(blob):
        return None

    text = blob[i:i + length].decode("utf-8", "replace")
    # U+FFFC OBJECT REPLACEMENT CHARACTER stands in for an inline attachment.
    text = text.replace("￼", "").strip()
    return text or None


def message_text(row_text, blob):
    """Prefer the plain column when it is populated, else decode the blob."""
    if row_text:
        return row_text
    return decode(blob)


if __name__ == "__main__":
    import os, sqlite3, sys
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    db = sqlite3.connect(
        f"file:{os.path.expanduser('~')}/Library/Messages/chat.db?mode=ro", uri=True)
    rows = db.execute(
        "SELECT text, attributedBody FROM message ORDER BY date DESC LIMIT ?",
        (limit,)).fetchall()
    plain = sum(1 for t, _ in rows if t)
    recovered = sum(1 for t, b in rows if not t and decode(b))
    lost = len(rows) - plain - recovered
    print(f"sampled       {len(rows)}")
    print(f"plain text    {plain}")
    print(f"recovered     {recovered}")
    print(f"still empty   {lost}  (attachments, reactions, empty sends)")
    print(f"coverage      {100*(plain+recovered)/len(rows):.1f}%")
