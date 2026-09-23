# Backlog

## Codex integration handoff, 2026-09-23

These two tasks are for a future contributor using Codex. The user reports Claude Code works normally; preserve its settings and behavior. Do not re-enable disabled Codex lifecycle hooks just to reproduce a problem. Keep model, provider and permission choices unchanged.

- [ ] **Restore and verify the native Codex MCP connection.** The Chewbacca server passes direct stdio initialization, tools/list and all five read-only tool calls. In the existing Codex task, native who_do_i_know still returns `Transport closed` after disconnect/reconnect. Configuration is enabled and five tools are discoverable, which does not prove the transport is live. Next: restart Codex, open a fresh task and invoke a read-only tool through native MCP. If it still fails, inspect app-server launch environment, process lifetime and MCP logs. Acceptance: successful native response after cold start and reconnect, no duplicate orphan server processes, and no Claude Code configuration changes. Do not infer a server defect solely from a stale task transport.

- [ ] **Verify and repair Codex automatic review, durability and closeout integration.** These hooks remain disabled. Prior defects included false correction detection, mismatched write evidence, and unverified native hook trust/enforcement. The durable checker can match words such as broken in a status question; its 13-times/209-sessions wording is historical hard-coded text, not a live count. The adapter now checks the current hooks.json registration before dispatch so a removed handler cached by Codex exits silently. Next: test ordinary status questions, genuine corrections, repeated hook feedback, permitted and refused tool calls, and removal/reload behavior in an isolated native Codex task. Verify actual trust/enforcement rather than editing trust records. Treat original-checkout closeout failures (dirty tracked work and divergent remote history) separately from hook behavior; preserve unrelated changes and never force-reset them. Acceptance: no correction loop on status questions or hook-generated feedback; real byte changes are credited to the right turn; genuine required review still blocks correctly when deliberately enabled; failed closeout is reported accurately. Re-enable only after targeted repair, native verification and user authorization.

## Completed prerequisite

The disconnected-hook fix adds a current-registration check in tools/codex_hooks.py before dispatch or receipt writes. Two regression tests cover removal and event-specific registration. All 33 adapter tests passed, and the exact installed Stop command returned exit 0 with empty stdout/stderr against the disabled configuration. Independent scoped review found no blocker. This does not certify all remaining native integration behavior.

## Broader session failures to prevent

These are open regression targets, not completed repairs. Keep domain execution moving while Codex-specific repair is delegated.

- [ ] Preserve prior commitments when new user steering arrives. Test a multi-goal session with interruptions; completed work, deferred tasks and next actions must remain explicit.
- [ ] Separate plan, clone, read, test, apply and verified outcome statuses. Later source reviews must update the central coverage ledger; old summaries must be labeled historical.
- [ ] Make agent-capacity claims from actual overlapping worker receipts. A capacity setting, queue length or DAG is not proof of simultaneous execution. Preserve runtime/model neutrality.
- [ ] Prioritize live user outcomes over expanding infrastructure. A prepared CSV or fixture is not a successful destination workflow; verify stable IDs and postconditions.
- [ ] Turn repository/media insights into selected behavioral tests. Preserve every explicitly supplied source in a coverage index, including unread links and failed transcript fetches.
- [ ] Test graph, math and learning additions against baselines and unfamiliar tasks. Do not claim novelty, retained expertise or superiority from corpus size or unit tests alone.
- [ ] Validate tool isError and business-level result before writing success receipts. Direct server calls and native host calls need separate evidence.
- [ ] Stop dependent publication commands after commit failure; verify remote HEAD equals the intended commit. Publish only scoped work and preserve unrelated dirty changes.
- [ ] Prevent hook feedback from becoming another user correction. Test ordinary status questions, keyword false positives and repeated hook-generated feedback, with bounded termination.
- [ ] Make disconnect/reconnect cover config, discovery, instructions and live process/transport state. Never report config presence as operational success.
- [ ] Keep status replies concise and accurate. Do not repeatedly ask the user to review routine code or respond to a malfunctioning checker instead of fixing its mechanism.

Detailed client-specific request/resource traceability is kept in the user's private GTM workspace, not this public repository.
