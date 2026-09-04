# The landscape

Every tool worth knowing about, with real numbers. Star counts and licenses pulled from
the GitHub API on **2026-09-04**. Sorted by layer, then by whether I would actually
reach for it.

The verdict column is the point. Star count is not a recommendation.

---

## macOS-native control (layers 2, 3, 4)

| Repo | Stars | Lang | License | Verdict |
|------|------:|------|---------|---------|
| [openclaw/Peekaboo](https://github.com/openclaw/Peekaboo) | 5,107 | Swift | MIT | **Install this.** Widest macOS surface anywhere: see, click, type, menus, Dock, Spaces, dialogs, status items, windows, MCP server. The one tool that covers layers 3, 4, and 5 |
| [lahfir/agent-desktop](https://github.com/lahfir/agent-desktop) | 1,034 | Rust | Apache-2.0 | **Install this.** The cleanest pure accessibility-tree driver. Stable element refs, JSON out, claims 78–96% token reduction. `npm i -g agent-desktop` |
| [steipete/macos-automator-mcp](https://github.com/steipete/macos-automator-mcp) | 876 | TS | MIT | **Install this.** AppleScript + JXA over MCP with a script knowledge base you can call by ID |
| [ghostwright/ghost-os](https://github.com/ghostwright/ghost-os) | 1,652 | Swift | MIT | Native macOS computer use, self-learning workflows, explicitly "no screenshots required." Right architecture. Last push March 2026, watch for staleness |
| [AmrDab/clawdcursor](https://github.com/AmrDab/clawdcursor) | 399 | TS | MIT | Fuses AX tree + OCR into one addressable UI map, screenshot only when needed, verifies every action through a safety gate. The most thoughtful design in the small-repo tier |
| [BlueM/cliclick](https://github.com/BlueM/cliclick) | 2,008 | ObjC | custom | **Install this.** Does one thing since forever. `brew install cliclick` |
| [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) | 16,050 | ObjC | MIT | Lua + deep macOS bindings. For agents its value is *triggers*: hotkeys, file watchers, screen watchers. Not installed by default |
| [andelf/axcli](https://github.com/andelf/axcli) | 33 | Rust | none | Minimal AX CLI. Useful to read as a reference implementation, too small to depend on |
| [AgentiLoop/Agent](https://github.com/AgentiLoop/Agent) | 591 | Swift | MIT | Mac-exclusive agent harness built on AXorcist for fuzzy element matching |
| [skalesapp/skales](https://github.com/skalesapp/skales) | 1,746 | TS | custom | Cross-platform desktop agent, goal-driven. Check the license before shipping anything on it |

## Apple app MCP servers (layer 1 + 2)

| Repo | Stars | License | Covers |
|------|------:|---------|--------|
| [supermemoryai/apple-mcp](https://github.com/supermemoryai/apple-mcp) | 3,130 | MIT | Notes, Contacts, Mail, Messages, Reminders, Calendar, Maps. The broadest single server |
| [peakmojo/applescript-mcp](https://github.com/peakmojo/applescript-mcp) | 463 | MIT | Raw AppleScript execution. Minimal by design, maximal in power |
| [joshrutkowski/applescript-mcp](https://github.com/joshrutkowski/applescript-mcp) | 393 | MIT | Categorized AppleScript tools |
| [carterlasalle/mac_messages_mcp](https://github.com/carterlasalle/mac_messages_mcp) | 323 | MIT | iMessage via `chat.db`, including the `attributedBody` decode. Solves a real problem |
| [achiya-automation/safari-mcp](https://github.com/achiya-automation/safari-mcp) | 181 | MIT | 97 Safari tools over AppleScript. Keeps logins, no second browser process |

## General computer-use frameworks (layer 5, cross-platform)

| Repo | Stars | Lang | License | Verdict |
|------|------:|------|---------|---------|
| [bytedance/UI-TARS-desktop](https://github.com/bytedance/UI-TARS-desktop) | 38,835 | TS | Apache-2.0 | Biggest in the category. Pure-vision GUI agent app, local and remote operators |
| [trycua/cua](https://github.com/trycua/cua) | 22,172 | n/a | MIT | The full stack: drivers, cross-OS fleets, macOS VM sandboxes via Lume, benchmarks. Where to go for VM-based macOS agents |
| [simular-ai/Agent-S](https://github.com/simular-ai/Agent-S) | 12,222 | Python | Apache-2.0 | Research-grade compositional agent, generalist + specialist. Strong papers behind it |
| [bytedance/UI-TARS](https://github.com/bytedance/UI-TARS) | 11,421 | n/a | Apache-2.0 | The model itself |
| [bytebot-ai/bytebot](https://github.com/bytebot-ai/bytebot) | 11,084 | TS | Apache-2.0 | Self-hosted agent in a containerized Linux desktop. Last push Sept 2025 |
| [OthersideAI/self-operating-computer](https://github.com/OthersideAI/self-operating-computer) | 10,292 | Python | MIT | The original demo of the idea. Last push Sept 2025, read it for history |
| [microsoft/UFO](https://github.com/microsoft/UFO) | 9,629 | Python | MIT | UFO³. Windows-centric, multi-device orchestration |
| [microsoft/fara](https://github.com/microsoft/fara) | 6,172 | Python | MIT | Fara-1.5 frontier CUA models, small enough to run locally |
| [yuruotong1/autoMate](https://github.com/yuruotong1/autoMate) | 3,953 | Python | MIT | Local automation on OmniParser |
| [e2b-dev/open-computer-use](https://github.com/e2b-dev/open-computer-use) | 2,237 | Python | Apache-2.0 | Open models + E2B Desktop Sandbox |
| [showlab/ShowUI](https://github.com/showlab/ShowUI) | 1,897 | Python | Apache-2.0 | CVPR 2025 end-to-end VLA model |
| [openai/openai-cua-sample-app](https://github.com/openai/openai-cua-sample-app) | 1,791 | TS | MIT | OpenAI's CUA reference |
| [OpenAdaptAI/OpenAdapt](https://github.com/OpenAdaptAI/OpenAdapt) | 1,715 | Python | MIT | Different and underrated: record a human demonstration, compile it to a program, and only report VERIFIED when an independent check agrees. Deterministic where everything else improvises |
| [mediar-ai/terminator](https://github.com/mediar-ai/terminator) | 1,629 | Rust | MIT | "Playwright for Windows." The Windows equivalent of agent-desktop |
| [anthropics/claude-quickstarts](https://github.com/anthropics/claude-quickstarts) | 17,602 | TS | MIT | `computer-use-demo` is the canonical reference loop |

## Screen parsing

| Repo | Stars | License | Verdict |
|------|------:|---------|---------|
| [microsoft/OmniParser](https://github.com/microsoft/OmniParser) | 25,368 | CC-BY-4.0 | Turns a screenshot into labeled interactive regions. Essential on Windows and Linux, **largely redundant on macOS** where the AX tree gives you the same thing free and faster |
| [screenpipe/screenpipe](https://github.com/screenpipe/screenpipe) | 21,406 | custom | Continuous screen recording + OCR as agent memory. Memory, not control. Check the license |

## Browser (layer 6)

| Repo | Stars | License | Verdict |
|------|------:|---------|---------|
| [browser-use/browser-use](https://github.com/browser-use/browser-use) | 112,213 | MIT | Most-starred project in the whole space. **If the task is on the web, start here** |
| [alibaba/page-agent](https://github.com/alibaba/page-agent) | 28,977 | MIT | In-page JS agent, no driver process |
| [Skyvern-AI/skyvern](https://github.com/Skyvern-AI/skyvern) | 22,928 | AGPL-3.0 | Vision + DOM workflows. **AGPL**, a real constraint if you ship it |
| [web-infra-dev/midscene](https://github.com/web-infra-dev/midscene) | 14,774 | MIT | Framed as E2E testing, works as a general driver |

## Adjacent

| Repo | Stars | Note |
|------|------:|------|
| [openinterpreter/openinterpreter](https://github.com/openinterpreter/openinterpreter) | 68,232 | Now a coding agent for open models. Its historical OS-control mode is where a lot of this started |
| [callstack/agent-device](https://github.com/callstack/agent-device) | 4,342 | iOS/Android automation. The mobile analogue |
| [X-PLUG/MobileAgent](https://github.com/X-PLUG/MobileAgent) | 9,159 | Mobile GUI agent family |
| [trycua/acu](https://github.com/trycua/acu) | 1,748 | Curated reading list for computer use. Good bibliography |

---

## Reading the table

**The four to install** are Peekaboo, agent-desktop, cliclick, and macos-automator-mcp.
Together they cover layers 2 through 5 with the accessibility tree as the default and
vision as the fallback, which is the correct architecture. That is what `install.sh`
does.

**The three worth reading even if you never install them** are OpenAdapt (demonstration
compiled to a verified program, the only project treating reliability as the primary
problem), clawdcursor (AX + OCR fused into one addressable map with a single safety
gate), and Anthropic's `computer-use-demo` (the canonical loop, in under a thousand
lines).

**What almost everything gets wrong on macOS:** it is ported from a cross-platform
design where vision is the only universal option, so vision becomes the default here
too. On a Mac that is leaving a free, fast, structured API on the table.
