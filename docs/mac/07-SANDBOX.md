# Layer 7: The sandbox

Two problems make people want a VM. One is safety: an agent with Accessibility can
read your bank tab and click Send on your email. The other is more mundane and, in
practice, the one that actually drives adoption: **the agent takes your mouse.** While
it works, the machine is unusable.

## macOS in a VM on macOS

Apple's Virtualization framework runs macOS guests on Apple Silicon at near-native
speed. Apple's license permits up to two macOS VMs per host.

| Tool | What it is |
|------|-----------|
| [lume](https://github.com/trycua/cua) | CLI for creating and managing Apple Silicon VMs |
| Lumier | Same, addressed with Docker commands |
| [UTM](https://mac.getutm.app/) | GUI, uses the Virtualization backend for macOS guests |
| [trycua/cua](https://github.com/trycua/cua) | 22k stars, MIT. The whole stack: drivers, fleets, benchmarks |

```bash
lume create my-agent-vm --os macos
lume run my-agent-vm
```

The catch is real: a fresh VM is logged into nothing. No iCloud, no Chrome profile, no
Messages history. For "test this installer safely" that is exactly right. For "reply to
my email" it defeats the purpose.

## Linux desktops in containers

Much cheaper when the task does not need macOS.

- [bytebot](https://github.com/bytebot-ai/bytebot): 11k stars, Apache-2.0. A
  self-hosted agent in a containerized Linux desktop.
- [e2b-dev/open-computer-use](https://github.com/e2b-dev/open-computer-use) and
  [e2b-dev/surf](https://github.com/e2b-dev/surf), E2B's Desktop Sandbox.
- Anthropic's `computer-use-demo` ships a Docker image with Xvfb and a VNC viewer.

## Lighter isolation

You do not always need a full VM.

- **A second user account.** Fast User Switching gives the agent its own session, its
  own cursor, and its own TCC grants. It cannot see your screen because it is not your
  session. Cheapest real isolation on a Mac and almost nobody does it.
- **A second physical Mac.** A cheap Mac mini on the desk, driven over SSH and Screen
  Sharing, is the setup most people who do this seriously end up at.
- **A Linux VM for shell only.** Route the agent's `bash` into a VM while GUI control
  stays on the host. Mitigates the destructive-command risk without losing your logins.

## The honest tradeoff

Isolation and usefulness pull against each other, and there is no clever way out. The
whole value of a personal Mac agent is that it has your context: your logged-in
sessions, your files, your history. A sandbox removes exactly that.

What actually works in practice:

- **Sandbox** the untrusted and the long-running. Anything driven by content from the
  internet. Anything that will hold the cursor for an hour.
- **Run on the host** the short, supervised, context-heavy tasks, with a human gate on
  anything irreversible.
- **Prefer layer 3** on the host, because it acts on background windows and does not
  take your cursor, which removes most of the reason you wanted a VM.

Which is the same conclusion as everywhere else in this repo: the accessibility tree
solves problems people are reaching for much heavier tools to solve.
