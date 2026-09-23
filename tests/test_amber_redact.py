"""Leakage test for bin/amber-redact, the first layer of the PAPILLON boundary.

A small PUPA-style set: synthetic requests with every private span marked, so
leakage is counted rather than eyeballed. Synthetic because this repo is
public; the real set, built from a person's own requests, stays in their root.

Three kinds of private span, scored separately because they have different
fixes:

  known     a value in the person's own stores (people, profile)
  pattern   an email, phone, card, SSN or address nobody stored
  unknown   a name the stores have never seen

The first two must not leak at all. The third is expected to leak: it is the
measured gap the local-model layer exists to close, and the number printed is
the case for building it. The control sends the same set through no redactor,
and must leak everything, or the counting is broken.

    python3 tests/test_amber_redact.py
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
REDACT = ROOT / "bin" / "amber-redact"
AMBER_USER = ROOT / "bin" / "amber-user"
PEOPLE = ROOT / "bin" / "people"
PASSED = FAILED = 0

PEOPLE_ROWS = [
    ("Sam Lee", ["--email", "sam.lee@northwind.test", "--phone", "512-555-0142"]),
    ("Maggie Chen", ["--email", "maggie@acme.test"]),
    ("Declan Ortiz", []),
]

CASES = [
    ("Draft a text to Sam Lee saying I'll be ten minutes late.",
     {"known": ["Sam Lee"]}),
    ("What did Sam say about the offer last week?",
     {"known": ["Sam"]}),
    ("Email maggie@acme.test the deck and cc sam.lee@northwind.test.",
     {"known": ["maggie@acme.test", "sam.lee@northwind.test"]}),
    ("Call (512) 555-0142 and ask if Friday works.",
     {"known": ["555-0142"]}),
    ("Remind me Declan's birthday is in March and Maggie owes me $40.",
     {"known": ["Declan", "Maggie"]}),
    ("I'm Alice Park, write my bio for the conference.",
     {"known": ["Alice Park"]}),
    ("Summarise what Chen and Ortiz disagreed about.",
     {"known": ["Chen", "Ortiz"]}),
    ("Send the invoice to billing@contoso.test by Friday.",
     {"pattern": ["billing@contoso.test"]}),
    ("My new number is 415-555-0199, update my signature.",
     {"pattern": ["415-555-0199"]}),
    ("Is card 4111 1111 1111 1111 the one on the Netflix account?",
     {"pattern": ["4111 1111 1111 1111"]}),
    ("Fill the form: SSN 078-05-1120, born 1990.",
     {"pattern": ["078-05-1120"]}),
    ("Ship it to 1600 Pennsylvania Ave and text me the tracking.",
     {"pattern": ["1600 Pennsylvania Ave"]}),
    ("Plan dinner with my friend Priya on Saturday.",
     {"unknown": ["Priya"]}),
    ("Tell Rafael his reference letter is done.",
     {"unknown": ["Rafael"]}),
    ("Ask Dr. Okafor whether the MRI results are in.",
     {"unknown": ["Okafor"]}),
    ("Write Sam a note, and loop in Ingrid Svensson from legal.",
     {"known": ["Sam"], "unknown": ["Ingrid Svensson"]}),
]

# Prose with no private span. Anything redacted here is damage to the request.
BENIGN = [
    "What is the capital of Australia?",
    "Summarise the Samsung earnings call for me.",
    "Write a haiku about Leeds in the rain.",
    "Convert 250 grams of flour to cups.",
    "Explain what a Luhn check is, with the number 1234 as an example.",
    "Book a table for 4 at 7pm on 12/10.",
]


def check(name, condition, detail=""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def leaked(text, secret):
    return secret.lower() in text.lower()


def score(transform):
    """Leaked and total span counts per kind, for one redactor."""
    tally = {}
    for text, spans in CASES:
        out = transform(text)
        for kind, secrets in spans.items():
            hit, total = tally.get(kind, (0, 0))
            tally[kind] = (hit + sum(leaked(out, s) for s in secrets), total + len(secrets))
    return tally


def main():
    with tempfile.TemporaryDirectory() as tmp:
        env = {k: v for k, v in os.environ.items()
               if k not in ("AMBER_USER", "AMBER_ROOT", "PEOPLE_DIR")}
        env.update(HOME=tmp, AMBER_HOME=f"{tmp}/users")
        subprocess.run([AMBER_USER, "init", "alice", "--name", "Alice Park"], env=env,
                       check=True, capture_output=True)
        for name, flags in PEOPLE_ROWS:
            subprocess.run([AMBER_USER, "run", "alice", "--", PEOPLE, "add", name, *flags],
                           env=env, check=True, capture_output=True)
        env["AMBER_USER"] = "alice"

        def call(*args, stdin=""):
            done = subprocess.run([REDACT, *args], env=env, input=stdin,
                                  capture_output=True, text=True, timeout=30)
            if done.returncode:
                raise RuntimeError(done.stderr)
            return done.stdout

        results = {text: json.loads(call("redact", stdin=text)) for text, _ in CASES}

        redacted = score(lambda text: results[text]["text"])
        control = score(lambda text: text)
        for kind in ("known", "pattern", "unknown"):
            hit, total = redacted[kind]
            print(f"  {kind:<8} {hit}/{total} leaked through the redactor, "
                  f"{control[kind][0]}/{control[kind][1]} with none")
        check("known values never leak", redacted["known"][0] == 0, redacted["known"])
        check("pattern values never leak", redacted["pattern"][0] == 0, redacted["pattern"])
        check("control: with no redactor every span leaks",
              all(hit == total for hit, total in control.values()), control)

        # The gap is recorded, not hidden: if unknown names stop leaking, the
        # regex layer has started guessing at capitalised words, which is the
        # over-redaction the benign set below exists to catch.
        check("unknown names leak (the local-model layer's job, measured)",
              redacted["unknown"][0] == redacted["unknown"][1], redacted["unknown"])

        damaged = [text for text in BENIGN if json.loads(call("redact", stdin=text))["text"] != text]
        check("benign prose passes through untouched", not damaged, damaged)

        # Round trip: an answer that uses the placeholders comes back whole,
        # including when the model drops the brackets.
        first = results[CASES[2][0]]
        answer = first["text"].replace("[EMAIL_1]", "EMAIL_1")
        restored = call("restore", first["id"], stdin=answer)
        check("restore puts every value back", restored == CASES[2][0], restored)
        joined = json.loads(call("redact", stdin="Sam Lee said Sam would call."))["text"]
        check("a name and its first name share one placeholder",
              joined == "[PERSON_1] said [PERSON_1] would call.", joined)

        maps = pathlib.Path(tmp, "users", "alice", "redact")
        modes = {oct(p.stat().st_mode & 0o777) for p in maps.iterdir()}
        check("maps stay private to the account", modes == {"0o600"}, modes)
        call("forget", first["id"])
        check("forget deletes the map", not (maps / f"{first['id']}.json").exists())
        refused = subprocess.run([REDACT, "restore", "../../etc"], env=env, capture_output=True)
        check("a request id cannot name a path", refused.returncode != 0)

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
