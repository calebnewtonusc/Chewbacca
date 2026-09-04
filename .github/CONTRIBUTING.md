# Contributing to Chewbacca

Thank you for your interest in contributing. This project aims to be the definitive Claude Code setup for developers who ship. Contributions that raise the bar are welcome.

## How to contribute

### Reporting issues

Open a GitHub issue if you find:

- Broken commands or hooks
- Hardcoded paths that should be templated
- Missing patterns that every project needs
- Errors in documentation

### Suggesting additions

Before adding a new command, rule, template, or snippet, open an issue first describing:

- What it does
- Why it belongs in the default setup (not just your personal workflow)
- Whether it's a command, rule, template, or snippet

### Pull requests

1. Fork the repo
2. Create a branch: `feat/your-feature` or `fix/your-fix`
3. Make your changes
4. Test: run `setup.sh` or `install.sh` on a clean directory to verify nothing breaks
5. Open a PR with a clear description

### What we look for in PRs

- **Universality**: does this work for any developer, not just one person's setup?
- **No hardcoded paths**: use `$HOME`, `$WORKSPACE_DIR`, or variables from setup.sh
- **No personal API keys or tokens**: use placeholders like `YOUR_API_KEY`
- **Follows existing patterns**: match the style of existing commands/rules
- **Tested**: did you actually run it?

## Code style

- Markdown: no trailing whitespace, one blank line between sections
- Shell scripts: `set -e`, use functions for reusable logic, quote variables
- TypeScript: strict mode, no `any` types
- All files: no em dashes, no emojis in code/copy

## What NOT to contribute

- Personal workflow preferences that wouldn't help other developers
- Commands that only work on one OS without fallbacks
- Rules that enforce a specific religion, political view, or personal opinion
- Anything that requires a paid service without a free alternative

## File structure conventions

| Type           | Location            | Naming                 |
| -------------- | ------------------- | ---------------------- |
| Slash commands | `.claude/commands/` | `kebab-case.md`        |
| Rules          | `.claude/rules/`    | `kebab-case.md`        |
| Templates      | `templates/`        | `descriptive-name.ext` |
| Snippets       | `snippets/`         | `descriptive-name.ext` |
| Documentation  | `docs/`             | `UPPER-CASE.md`        |

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

## Trust, because this kit runs as you

Anything merged here gets a shell on somebody's Mac, their messages, and their
contacts. That changes what review is for.

**A contributed skill is code.** It is prose the model will follow, which is
the same thing. A skill that tells the agent to read a credential file, send
something outbound without confirmation, or act on content the user did not
write will be rejected, and those are the three things review looks for first.

**Nothing here is sandboxed.** There is no isolation between a skill and the
rest of the machine. Do not propose one that assumes there is.

**Vendored work keeps its author.** Skills cloned from upstream carry a
`.source` file and their original license. They are held to the upstream
author's standard, not this repo's prose rules, which is why the slop threshold
in CI is 60 rather than 0.

## Adding a skill

```bash
./add-skill.sh <name>          # scaffolds SKILL.md and evals/
```

A skill is accepted when all of this is true:

1. **The description says when to load it, not what it is.** Routing reads that
   sentence and nothing else. Write the words a person would actually type.
2. **It declares what it needs.** `requires: [tool, tool]` in the frontmatter.
   `chewbacca doctor` checks those exist, so an undeclared dependency is a
   promise nothing verifies.
3. **It has evals.** At least four cases in `evals/evals.json`, each with a
   prompt and an expectation (`expect_tools`, `expect_behavior`, or `reject`).
   A case with no expectation can never fail. `chewbacca evals` checks this.
4. **At least one case is a rejection.** What should this skill *not* do, and
   what should it refuse to be talked into.
5. **It passes the writing rules.** `python3 bin/slop-check skills/<name>`.

## Running the checks yourself

```bash
bash tests/run.sh              # 93 tests, hermetic, touches no real data
bash tests/run.sh people       # one group
./doctor.sh                    # the install on this machine
python3 tools/evals.py         # every skill's evals
python3 bin/secret-scan .      # credentials
python3 tools/checksums.py     # regenerate after changing any script
```

CI runs all of that plus shellcheck and a macOS job. A pull request that has
run `bash tests/run.sh` locally has already passed most of it.

## What gets a fast yes

- A bug with a failing test in the same change.
- A doctor check for a failure that was previously silent. That is the pattern
  this repo is built on: every silent failure it ever shipped got a check.
- An item from [docs/1000.md](../docs/1000.md), with the number in the commit
  message as `Fixes items N of docs/1000.md`, which is how the status file
  counts it.
