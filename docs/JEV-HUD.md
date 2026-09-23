# Jev in the HUD

How the HUD uses TypeSafe's Jev to run many agents and act faster, step by step
against Movez's "Jev Engineering: how to build the fastest AI Agent Brain in 10
Steps" (2026-09-18). Started 2026-09-23. The wider plan, beyond the HUD, is
[JEV-EVERYWHERE.md](JEV-EVERYWHERE.md).

The rule the whole plan follows, from the article: **if an operation creates text,
it stays with the LLM. If it picks from a list, scores, or answers yes or no, it
goes to Jev. An exact rule goes in code.** Jev answers in 0.2 to 0.6 s and costs
$0.042 per million input tokens, so a decision stops being the slow part of a
voice turn.

## Where each step lands

| Step            | In the HUD                                                                                                                                                            | Status                   |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| 01 Split        | The decisions in `hud-listen` today: where a sentence goes, which agent it is for, whether a prompt is safe, whether to speak or write the answer, what to click next | Inventory below          |
| 02 Playground   | `tests/eval_*_jev.py`: labelled sentences against the live API before any code trusts a threshold                                                                     | Two evals exist          |
| 03 SDK          | `bin/lib/jev.py`: one HTTP call, None on any failure so rules still work when Jev is down                                                                             | Done                     |
| 04 Handoff      | The agent board: every Claude session's state, folded from hook events (`agent-events.jsonl`)                                                                         | Built, see below         |
| 05 Questions    | Choice for destination and agent, Noul for safety and "is this a status question", Score for urgency                                                                  | Choice in use            |
| 06 Dynamic menu | `agent_board.menu` rebuilds the agent list from the live board on every call; guide mode does the same with the controls on screen                                    | Agents built, guide next |
| 07 Parallel     | One call per sentence carrying every question: destination, agent, status question, urgency                                                                           | Next                     |
| 08 Guardrails   | Floors under every choice (below them the voice asks), a safety Noul in front of permission answers, a spend cap, outcome checked separately from the decision        | Floors built             |
| 09 Cost         | Per-call cost and latency logged with each `turn:` line in listen.log                                                                                                 | Next                     |
| 10 Deploy       | Voice router tier 3 (live), agent picking, permission triage, guide mode, compaction                                                                                  | Rolling out              |

## The decisions (step 01)

| Decision                                                | Today                          | Jev question                                                |
| ------------------------------------------------------- | ------------------------------ | ----------------------------------------------------------- |
| Where does a sentence go (terminal, browser, assistant) | Word lists, then Jev tier 3    | Choice, live since 2026-09-23 (30/30 on its eval)           |
| Which agent is it for                                   | Only one remembered tab exists | Choice over the live board (built)                          |
| Is it asking for status rather than giving an order     | Nothing                        | Noul, answered from the board with no model turn            |
| Is a waiting permission prompt safe to allow            | Only the person, by voice      | Noul, used to rank and phrase the ask, never to grant alone |
| Speak the answer or write it to the hyper bar           | Length rule                    | Choice, later                                               |
| What to click next in guide mode                        | Word match on control names    | Choice over the controls on screen, rebuilt every step      |
| Which tool calls to keep when compacting a long session | Nothing                        | Score per call (fast-jev-compaction's approach)             |

## What is built

- `bin/lib/agent_board.py`: fold, expire, order (waiting, then running, then done),
  the spoken summary, the dynamic menu, and `pick`. One session means no Jev call.
  Below `PICK_FLOOR` or on "none", nobody gets the sentence and the voice asks which.
- `mac/lib/terminal_events.py`: the hook now writes every session to
  `agent-events.jsonl`. Only the remembered tab's prompts are held, as before.
- `bin/agents`: `agents`, `agents say`, `agents pick "<words>"`, `agents --json`.
- `tests/test_agent_board.py` (21 checks) and two new checks in
  `tests/test_terminal_events.py`.
- `tests/eval_agent_board_jev.py`: 19/20 on 2026-09-23, none sent to the wrong
  agent, worst latency 0.58 s. The miss is recorded in the file.

## Next, in order

1. **Topics on the menu.** The eval's one miss was "the heads up display one": the
   menu said the folder and the current tool call, not what the session is for. Record
   each session's first prompt (the UserPromptSubmit hook) and put it on the menu.
2. **Voice wiring.** In `hud-listen`: a status question speaks `agents say`; a sentence
   routed to the terminal goes through `pick` to the chosen session's tab, found by
   matching its `cwd` against `chewie terminal tabs`. Yes and no answer the session
   that is waiting, not only the remembered one.
3. **One parallel call.** Fold the router's destination question and the agent question
   into one `jev.ask` with both, so a sentence costs one round trip.
4. **Permission triage.** A Noul per waiting prompt, "safe to allow without review",
   used to order what the voice reads out and to say "three safe, one risky". It never
   grants: the only allow stays one a person said.
5. **Guide mode on Jev.** `hud-guide` lists the controls; Jev picks the next one from
   that list instead of word matching. Same loop Browser Use ships.
6. **Cost line.** Log tokens and seconds per Jev call next to each `turn:` line.

## Hard lines

- Jev never grants a permission and never sends text anywhere on its own. It picks,
  scores and ranks; code and the person act.
- Every threshold carries the eval run that set it. A floor with no run behind it
  says so in its comment.
- Personal text (messages, mail) does not go to Jev until the privacy choice for the
  brain is made.
