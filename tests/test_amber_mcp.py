"""Tests for mcp/amber/amber-mcp, driven over stdio the way a client drives it.

The acceptance test is Caleb's own from the 2026-09-23 call: a file of 10,000
contacts goes in and comes out deduplicated in one user's Amber. Everything
else here pins the three rules in the server's header: preview writes nothing,
every write is undoable, and one process only ever sees one person.

    python3 tests/test_amber_mcp.py
"""

import json
import os
import pathlib
import random
import stat
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
SERVER = ROOT / "mcp" / "amber" / "amber-mcp"
PASSED = FAILED = 0


def check(name, condition, detail=""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def call(home, user, *calls):
    """Run one server process, send initialize plus each tool call, return texts."""
    msgs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {}}]
    for i, (tool, args) in enumerate(calls, 1):
        msgs.append({"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": {"name": tool, "arguments": args}})
    env = dict(os.environ, AMBER_HOME=str(home), AMBER_USER=user, AMBER_IMPORT_DIRS=str(home.parent))
    p = subprocess.run(
        ["node", str(SERVER)],
        input="\n".join(json.dumps(m) for m in msgs) + "\n",
        capture_output=True, text=True, env=env, timeout=120,
    )
    out = {}
    for line in p.stdout.splitlines():
        r = json.loads(line)
        if r.get("id"):
            res = r.get("result", {})
            out[r["id"]] = ("ERR " if res.get("isError") else "") + res.get("content", [{}])[0].get("text", "")
    return [out.get(i, f"no reply ({p.stderr.strip()[:300]})") for i in range(1, len(calls) + 1)]


def import_id(text):
    for tok in text.split():
        t = tok.strip('".,:')
        if len(t) == 12 and all(c in "0123456789abcdef" for c in t):
            return t
    return None


def count(text):
    return int(text.split(" holds ")[1].split()[0])


def main():
    tmp = pathlib.Path(tempfile.mkdtemp())
    home = tmp / "amber"
    rnd = random.Random(7)

    # 8,500 real people, 1,500 duplicates written the ways real exports differ,
    # and 50 rows nobody can be reached through.
    people = []
    for i in range(8500):
        people.append({
            "name": f"Person {i:05d} Lastname",
            "email": f"person{i}@firm{i % 900}.com",
            "phone": f"512555{i:04d}",
            "company": f"Firm {i % 900} Capital",
            "title": rnd.choice(["Partner", "Principal", "Founder", ""]),
        })
    rows = [dict(p) for p in people]
    for j in range(1500):
        p = dict(people[rnd.randrange(8500)])
        style = j % 3
        if style == 0:
            p["email"] = p["email"].upper()                       # same email, shouted
        elif style == 1:
            p["email"] = ""                                        # matched by phone
            d = p["phone"]
            p["phone"] = f"+1 ({d[:3]}) {d[3:6]}-{d[6:]}"
        else:
            # Only name plus company links this one: its email and phone are
            # gone, the firm carries a legal suffix, and its one reachable
            # field is a LinkedIn the original never had.
            p["email"], p["phone"] = "", ""
            p["company"] = p["company"] + ", LLC"
            p["linkedin"] = f"https://www.linkedin.com/in/dupe-{j}"
        rows.append(p)
    for k in range(50):
        rows.append({"name": f"Nobody {k}", "email": "", "phone": "", "company": "X"})
    rnd.shuffle(rows)

    csv = tmp / "contacts.csv"
    cols = ["name", "email", "phone", "company", "title", "linkedin"]
    with csv.open("w") as f:
        f.write(",".join(cols) + "\n")
        for r in rows:
            f.write(",".join('"' + str(r.get(c, "")).replace('"', '""') + '"' for c in cols) + "\n")

    print("10,000 rows through preview and apply")
    t0 = time.time()
    prev, summ = call(home, "gavin", ("preview_import", {"file": str(csv), "source": "test"}), ("amber_summary", {}))
    t_prev = time.time() - t0
    check("preview counts 8,500 new", "8500 new people to add" in prev, prev[:400])
    check("preview collapses the 1,500 duplicates", "1500 duplicates inside the file" in prev, prev[:400])
    check("preview rejects the 50 unreachable rows", "50 rows rejected" in prev, prev[:400])
    check("preview wrote no contacts", count(summ) == 0, summ)
    bid = import_id(prev)

    t0 = time.time()
    (applied,) = call(home, "gavin", ("apply_import", {"import_id": bid}))
    t_apply = time.time() - t0
    check("apply saves exactly the previewed 8,500", "8500 added" in applied and "8500 people in total" in applied, applied)
    print(f"        preview {t_prev:.1f}s, apply {t_apply:.1f}s")

    db = home / "gavin" / "contacts.db"
    check("store is readable by its owner only", stat.S_IMODE(db.stat().st_mode) == 0o600, oct(db.stat().st_mode))
    check("store directory is private", stat.S_IMODE(db.parent.stat().st_mode) == 0o700)

    print("re-importing the same file")
    (again,) = call(home, "gavin", ("preview_import", {"file": str(csv)}))
    check("a second import of the same file adds nobody", "0 new people to add" in again, again[:300])

    print("isolation")
    (other,) = call(home, "sagar", ("amber_summary", {}))
    check("another user's Amber is empty", count(other) == 0, other)
    (found,) = call(home, "sagar", ("search_contacts", {"query": "Person 00001"}))
    check("another user cannot search this user's people", "No one" in found, found)

    print("two people who share a name")
    (p2,) = call(home, "gavin", ("preview_import", {"contacts": [
        {"name": "John Smith", "email": "john@alpha.com", "company": "Alpha"},
        {"name": "John Smith", "email": "john@beta.com", "company": "Beta"},
    ]}))
    check("same name at different firms stays two people", "2 new people to add" in p2, p2[:300])

    print("a stale preview is refused")
    (stale,) = call(home, "gavin", ("preview_import", {"contacts": [{"name": "Ada One", "email": "ada@one.com"}]}))
    (fresh,) = call(home, "gavin", ("preview_import", {"contacts": [{"name": "Bo Two", "email": "bo@two.com"}]}))
    call(home, "gavin", ("apply_import", {"import_id": import_id(fresh)}))
    (refused,) = call(home, "gavin", ("apply_import", {"import_id": import_id(stale)}))
    check("apply refuses a preview older than the store", refused.startswith("ERR") and "changed since" in refused, refused)

    print("undo touches only its own import")
    (fill,) = call(home, "gavin", ("preview_import", {"contacts": [
        {"name": "Bo Two", "email": "bo@two.com", "title": "Partner"},
        {"name": "Cy Three", "email": "cy@three.com"},
    ]}))
    fid = import_id(fill)
    check("a known person with a new field is a fill, not an add", "1 new people to add" in fill and "1 already in Amber, with blank fields" in fill, fill[:400])
    call(home, "gavin", ("apply_import", {"import_id": fid}))
    (u,) = call(home, "gavin", ("undo_import", {"import_id": fid}))
    check("undo removes the one it added and clears the one field it filled", "removed 1" in u and "cleared 1" in u, u)
    (bo,) = call(home, "gavin", ("search_contacts", {"query": "Bo Two"}))
    check("the person the undone import filled is still there", "Bo Two" in bo and "Partner" not in bo, bo)
    (s,) = call(home, "gavin", ("amber_summary", {}))
    check("the big import survives an unrelated undo", count(s) == 8501, s[:200])

    print("vCard and PDF readers")
    vcf = tmp / "c.vcf"
    vcf.write_text("BEGIN:VCARD\nFN:Dee Four\nEMAIL;TYPE=work:dee@four.com\nORG:Four Co;\nEND:VCARD\n")
    (v,) = call(home, "gavin", ("preview_import", {"file": str(vcf)}))
    check("a vCard reads", "1 new people to add" in v and "Dee Four" in v, v[:300])

    # Needs pdftotext to read and macOS cupsfilter to build the fixture, so it
    # skips cleanly on a CI runner that has neither.
    import shutil
    if shutil.which("pdftotext") and shutil.which("cupsfilter"):
        txt = tmp / "c.txt"
        txt.write_text(
            "Name              Company             Title        Email                   Phone\n"
            "Maya Chen         Northstar Ventures  Partner      maya@northstar.vc       (512) 555-0101\n"
            "Leo Park          Acme Capital        Principal    leo@acme.com            512-555-0102\n"
            "Maya Chen         Northstar Ventures  Partner      MAYA@northstar.vc\n"
        )
        pdf = tmp / "c.pdf"
        with pdf.open("wb") as f:
            subprocess.run(["cupsfilter", "-m", "application/pdf", str(txt)], stdout=f, stderr=subprocess.DEVNULL)
        (pp,) = call(home, "pdfuser", ("preview_import", {"file": str(pdf)}))
        check("a table in a PDF reads, with its duplicate collapsed",
              "2 new people to add" in pp and "1 duplicates inside the file" in pp
              and "Maya Chen, Partner at Northstar Ventures" in pp, pp[:500])
    else:
        print("  skip  PDF reader (needs pdftotext and cupsfilter)")

    print("file reads are confined")
    outside = pathlib.Path(tempfile.mkdtemp()) / "c.csv"
    outside.write_text("name,email\nEve,eve@x.com\n")
    (o,) = call(home, "gavin", ("preview_import", {"file": str(outside)}))
    check("a file outside the import folders is refused", o.startswith("ERR") and "only reads" in o, o)
    hidden = tmp / ".ssh" / "keys.csv"
    hidden.parent.mkdir()
    hidden.write_text("name,email\nEve,eve@x.com\n")
    (h,) = call(home, "gavin", ("preview_import", {"file": str(hidden)}))
    check("a file inside a hidden folder is refused", h.startswith("ERR") and "hidden" in h, h)
    key = tmp / "id_ed25519"
    key.write_text("-----BEGIN OPENSSH PRIVATE KEY-----\nabc@def.gh\n")
    (k,) = call(home, "gavin", ("preview_import", {"file": str(key)}))
    check("a file without a contacts extension is refused", k.startswith("ERR") and "BEGIN" not in k, k)

    print("the HTTP transport")
    import http.client
    import socket
    s_ = socket.socket(); s_.bind(("127.0.0.1", 0)); port = s_.getsockname()[1]; s_.close()
    env = dict(os.environ, AMBER_HOME=str(home), AMBER_USER="gavin", AMBER_IMPORT_DIRS=str(tmp))
    srv = subprocess.Popen(["node", str(SERVER), "--http", str(port)], env=env, stderr=subprocess.PIPE, text=True)
    try:
        srv.stderr.readline()
        secret = (home / "gavin" / "token").read_text().strip()
        tok = home / "gavin" / "token"
        check("the token file is owner-only", stat.S_IMODE(tok.stat().st_mode) == 0o600)
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})

        def post(headers):
            c = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
            c.request("POST", "/", body, headers)
            r = c.getresponse()
            return r.status, r.read().decode()

        good = {"content-type": "application/json", "authorization": f"Bearer {secret}"}
        st, out = post(good)
        check("a local client with the token gets the tools", st == 200 and "preview_import" in out, f"{st} {out[:100]}")
        st, _ = post({"content-type": "application/json"})
        check("no token is refused", st == 401, st)
        st, _ = post({**good, "origin": "https://evil.example"})
        check("a web page's cross-origin request is refused", st == 403, st)
        st, _ = post({**good, "host": "evil.example"})
        check("a rebinding Host header is refused", st == 403, st)
    finally:
        srv.terminate()

    print(f"\n{PASSED} passed, {FAILED} failed.")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
