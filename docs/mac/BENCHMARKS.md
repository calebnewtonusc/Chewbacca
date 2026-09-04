# What these agents actually score

Numbers, so you can calibrate how much to trust one of these with something that
matters.

## macOSWorld

The only macOS-specific benchmark. 202 multilingual interactive tasks across 30
applications, 28 of them macOS-exclusive, with instructions and interfaces in English,
Chinese, Arabic, Japanese, and Russian.

- **Proprietary computer-use agents: above 30% success.**
- **Open-source lightweight research models: below 5%.**

Paper: [arxiv 2506.04135](https://arxiv.org/html/2506.04135v4)

Thirty percent means seven out of ten tasks fail. On your actual Mac.

## OSWorld

The general cross-platform benchmark, and the one people quote when they say computer
use is solved.

- **April 2024: 12%.**
- **June 2026: 85%.**

That is a real and fast climb, and it is the number behind most of the optimism.

## OSWorld 2.0

The follow-up, built for long-horizon tasks where **the median task takes a human 1.6
hours**.

- **Best frontier system: 20.6%.**

The gap between 85% and 20.6% is the whole story of this field. Short, well-scoped,
single-app tasks are close to working. Long, multi-app, multi-hour work is not, and the
failure mode is compounding: twenty steps at 95% each is a 36% success rate.

Paper: [arxiv 2606.29537](https://arxiv.org/pdf/2606.29537)

## Others worth knowing

| Benchmark | What it measures |
|-----------|------------------|
| [MacArena](https://arxiv.org/pdf/2606.06560) | Online macOS environment |
| [OSUniverse](https://arxiv.org/pdf/2505.03570) | Multimodal GUI navigation, graded difficulty |
| [OpenComputer](https://arxiv.org/pdf/2605.19769) | Verifiable software worlds |
| ScreenSpot | Grounding only: given an instruction and a screenshot, click the right thing |

## What to take from this

**Scope tightly.** Success falls off a cliff with task length. Five steps in one app is
a different problem from fifty steps across four apps, and the benchmarks say so.

**Verify every step.** Twenty steps at 95% is 36%. The only defense is checking state
after each action instead of assuming it worked, which is why the `see → act → see`
loop in [CLAUDE.md](OPERATING-MANUAL.md) is not optional ceremony.

**Prefer the deterministic layer.** These numbers are for vision-driven agents. An
AppleScript that says `tell application "Mail" to send message 1` either works or
returns an error. It does not have a success rate. Every task you push down from layer
5 to layers 1 through 3 leaves the probabilistic regime entirely.

**Take the demos at a discount.** A demo is a task someone already got working. The
benchmark is the distribution.
