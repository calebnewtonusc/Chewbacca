# Threat model

This kit gives an agent your texts, your email, your calendar, your contacts,
your screen, and a shell. SECURITY.md said where to report a vulnerability and
nothing about what the exposure actually is. This is that.

Written against v1.0.0. If you find something here that is wrong, that is a
bug report worth more than a feature request.

## What this protects

- Your local data: messages, contacts, the people store, the context repo.
- Your credentials: keychain entries, SSH keys, API tokens, `.env` files.
- Your accounts: GitHub, cloud providers, anything the shell can reach.
- Your machine's integrity: files, system protections, installed software.

## Who could attack it

**1. Content you did not write.** An email, a web page, a PDF, a calendar
invite, a code comment, a filename. This is the realistic attack and it needs
no access to your machine at all. Mitigated by
[`.claude/rules/untrusted-content.md`](../.claude/rules/untrusted-content.md),
which is always on. That mitigation is a prompt, and prompts are not
guarantees. Treat it as a strong default, not a boundary.

**2. A malicious skill, plugin, or MCP server.** Anything installed gets the
same access you have. The kit vendors third-party skills and registers twelve
MCP servers. Nothing sandboxes them and nothing signs them. Only install what
you would run as yourself, because that is what you are doing.

**3. A compromised upstream.** The installer clones repos and pulls Homebrew
formulas at whatever version is current. Nothing is pinned by hash. A
compromised upstream reaches your machine on your next `chewbacca update`.

**4. Someone with your unlocked Mac.** Everything the kit stores is readable by
your user account. Nothing is encrypted at rest.

**5. You, on a bad day.** A destructive command run by mistake. The deny list
covers 57 patterns, and it is a string match on the command text.

## What is deliberately not protected

- **The shell is real.** `defaultMode` is `bypassPermissions`, so tool calls do
  not prompt. That is the product working as designed and it is the single
  biggest decision in this repo. Turn it off with `chewbacca setup --no-bypass`
  if that trade is wrong for your machine.
- **The deny list is not a sandbox.** It matches strings. An equivalent command
  spelled differently gets through. It exists to stop accidents, not attackers.
- **No egress control.** Anything the shell can reach, the agent can reach.
- **No multi-user isolation.** One machine, one person is the assumption.

## The curl-pipe-bash question

The README tells an agent to run
`curl -fsSL .../start.sh | bash`. That is the pattern an attacker would use, and
saying "but it is our script" is not an answer. What is actually true:

- You are trusting GitHub's TLS and this repo's contents, the same trust you
  extend by cloning it.
- Since v1.1.0 there are checksums. `SHA256SUMS.txt` covers every file that
  actually runs, `start.sh` verifies the download against it and stops on a
  mismatch, and `--version v1.1.0` pins the install to a tag instead of
  whatever landed on main an hour ago.
- That is not a signature. It catches a truncated download, a proxy that
  rewrote something in flight, and a mirror that is not what it claims. It does
  not defend against a compromised repo, because the checksums live in the same
  repo. Signing is still open, item 530.
- The safe alternative works today and is one line longer:

```
git clone https://github.com/calebnewtonusc/Chewbacca
less Chewbacca/start.sh      # read it
bash Chewbacca/start.sh --full-send
```

Anyone who would not run a script without reading it should take that path, and
the README should say so more loudly than it does.

## Reporting

See [SECURITY.md](../.github/SECURITY.md). Anything that lets content the user
did not write cause an outbound action or a credential read is the highest
severity thing this project can have.
