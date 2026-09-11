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

## Driving a browser you are signed in to

`chrome-js` runs JavaScript in a real Chrome that is logged in to real accounts,
usually with an agent choosing the script. That is a genuinely dangerous shape,
and the rules below are what keeps it usable.

**Reading a password field is refused, in every mode, with no override flag.**
A credential read out of a page lands in the transcript, the hook log, and the
model's context in one step, and it cannot be recalled from any of them. The
check is a pattern match over the script before injection, so it is a floor
against the common accident, not a wall against a determined bypass. It is
deliberately not configurable: a flag to disable it would be set once, in a
hurry, and never unset.

**There is no credential store here, on purpose.** The safe version of
agent-driven sign-in is the one [Realm](https://github.com/31Carlton7/realm)
implements, and it is worth naming because it shows what the bar actually is:

- the human enrolls the credential themselves, in app settings. No tool, no RPC
  call, and no chat message can create one, which is the only reason the origin
  check below is worth anything
- values live in the OS keychain, encrypted by the platform, decrypted only
  inside the privileged process, never readable back over any bridge
- a fill is gated three ways: the page's current origin, read from the browser,
  must exactly equal the enrolled origin (no subdomains, no lookalikes); the
  human approves that specific fill on a card naming origin, username and label;
  and a biometric prompt confirms a person is present
- the approval card appears **in every permission mode**, including a
  bypass-everything mode, is never batched with other approvals, and answering
  "always" licenses nothing
- fills are logged with timestamp, origin, credential id and outcome, and never
  the value, the field name, or its length
- typing into a password field with the generic "act on the page" tool stays
  refused everywhere; the fill is a separate, narrower operation, not a way
  around the refusal
- two-factor is not automated and is not planned. A push prompt cannot be driven
  from here, so an SSO sign-in stays partly manual by design

Chewbacca implements none of that machinery, so it takes the only other honest
position: secrets do not pass through this tool at all. Sign in by hand, in the
window, and let the agent take it from the authenticated page.

**Screen capture is the other leak.** `peekaboo image` photographs whatever is
on screen, including a visible password field or an open password manager. The
capture tools are not restricted, because restricting them would break the
feature; the mitigation is that `chrome-js` exists specifically so that reading
a page does not require photographing the desktop.

## Reporting

See [SECURITY.md](../.github/SECURITY.md). Anything that lets content the user
did not write cause an outbound action or a credential read is the highest
severity thing this project can have.
