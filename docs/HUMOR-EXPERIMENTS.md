# Humor experiments nobody has run

Opened 2026-09-22. Four independent research agents read the computational-humor
literature end to end and each one, separately, came back with a list of things
the field has never measured. Several are cheap. One of them Caleb is already
holding the materials for.

The reason this is worth a day: the whole question of whether Chewbacca can get
funnier turns on measurement, and the measurement literature has holes in exactly
the places a builder needs answers.

**Pre-register the prediction before running each one.** Write the expected
number down first. An experiment whose result you would accept either way is not
an experiment, it is a demo.

---

## 1. Can a comedian predict their own hits?

**Nobody has run this.** Not once, for comedy. The closest is Justin Berg's
circus-arts work (339 professionals forecasting novel acts, validated against
13,248 audience members), which found creators forecast **other people's** ideas
well and **their own** badly. Nobody has taken a comedian's pre-performance
ranking of their own new material and correlated it against measured audience
response.

**Why it matters here.** The entire engine design depends on whose judgment is
the ground truth. If Caleb can rank his own jokes, his verdicts are a training
signal. If he cannot, the engine needs an audience and no amount of taste
modelling substitutes.

**Design.** He ranks his 44 finished tweets before posting any. Post them on a
fixed cadence. Correlate his pre-rank against engagement, normalised for time of
day and follower count. Report Spearman rho.

**Prediction to write down first:** rho around 0.13, from Silvia & Greengross
(2021), who had 1,133 adults rate their own attempts against independent judges
and got r = 0.13 within-person.

**Cost.** One evening to rank, six weeks to post, one script to pull numbers.
`scripts/pull.py` already reads engagement off fxtwitter without auth.

**Threat to validity, stated up front.** Engagement is a bad proxy. A randomly
assigned first upvote moves final score 25% (Muchnik, Aral & Taylor, Science
2013), and content explains about 10% of variance in one Reddit study. This
measures fit-to-audience, not funniness. Say so in the writeup.

---

## 2. Does Gulman's confidence inversion hold?

**Never tested.** Gary Gulman, writing tip 296 of 365: *"there are few better
indicators that you're onto something special than A) I wasn't certain they were
funny and B) If nobody laughed, I would be embarrassed."*

If that is true, then ranking candidates by estimated funniness selects against
the best material, and every generate-then-self-rank architecture is inverted.
That is a load-bearing claim for this project and it rests on one comedian's
testimony.

**Design.** Free to run inside experiment 1. When Caleb ranks the 44, he also
tags each one `certain` or `unsure-but-would-be-embarrassed`. Compare the two
groups on measured response.

**Prediction:** if Gulman is right, the `unsure` group outperforms `certain`.
Write down which way you expect it before looking.

**Why it is novel.** Search found no study testing whether creator uncertainty
predicts creative success in any domain, let alone comedy.

---

## 3. Does a model rank its own candidates worse than a sibling's?

**Isolated by nobody.** Self-preference in LLM judges is established (Panickssery,
Bowman & Feng, NeurIPS 2024, showing a linear relationship between
self-recognition and self-preference). What has never been separated is the exact
operation a generate-then-rank loop performs: model A ranking **its own** output
versus model B ranking that same output.

**Design.** Model A generates 20 candidates on a fixed premise. Model A ranks
them. Model B ranks them. Caleb ranks them. Compare each model's ordering to his.
Repeat over 20 premises.

**Prediction:** cross-ranking beats self-ranking. If it does, the engine must
never let the generator select, which is what every professional comedy
institution already enforces by other means. The Onion strips the author's name
and has headlines read in a monotone by the most boring voice in the room.

**Cost.** An afternoon. This is the cheapest one on the list and the most
directly useful to the build.

---

## 4. Base model versus aligned model on rated joke quality

**The obvious ablation, unrun.** Everyone repeats that safety and instruction
tuning flattens humor. The supporting evidence is real but indirect: stereotypical
and toxic jokes gain 10-21% in mean humor score (Dogra et al. 2025), alignment
measurably reduces output diversity (Verbalized Sampling: 23.8% of base diversity
retained after alignment), and 20 professional comedians at the Edinburgh Fringe
reported moderation blocking the material comedy is made of.

Nobody has published base-versus-instruct, same family, same prompts, blind-rated
for funniness.

**Design.** Llama base and Llama instruct, identical prompts, outputs shuffled and
blind-rated. Report the difference and the diversity of the candidate pool.

**Counter-evidence to respect:** Zhang et al. (NeurIPS 2024) found PPO
*increased* caption diversity, explicitly against the prevailing claim. The
result may not go the way everyone assumes.

---

## 5. Does listening back actually cause improvement?

Gulman calls recording and transcribing your own sets the single most valuable of
his 365 tips, and says it is the one people skip. It has never been tested.

**The Chewbacca version, which is testable here.** Does feeding a generator its
own rejected candidates plus the reason for rejection improve the next batch,
against a control that just regenerates? Today's session is a natural pilot:
roughly a hundred candidates exist with Caleb's rulings attached to ten of them.

**Why this one matters most for the kit.** `docs/LEARNING.md` records that the
self-improvement loop has never closed once. This is a small, bounded domain with
a human grader already in place, which makes it the cheapest available test of
whether the loop can close at all.

---

## The four numbers that frame all of it

| Number | What it is | Source |
| --- | --- | --- |
| **0.124** | Krippendorff's alpha, 20 annotators rating how funny 10,000 texts are | SemEval-2021 Task 7 |
| **0.49** | Same person, same joke, 4-7 days apart | Rosenbusch & Visser 2023 |
| **7.09%** | Variance in funniness explained by the joke itself, out of 1.84M ratings | Rosenbusch et al. 2022 |
| **0.169-0.266** | Spearman rho, LLM judges versus human funniness | Oogiri study 2025 |

The rater explains more than the joke. The rater-by-joke interaction explains more
than either. A funniness eval can work as a **filter** and cannot work as a
**gradient**, and any design that assumes a scalar reward ranking candidates
finely will be optimising noise.

Full research and sources: `comedy-engine/skills/comedy-mechanisms/SKILL.md` in
`calebnewtonusc/comedy-engine`.
