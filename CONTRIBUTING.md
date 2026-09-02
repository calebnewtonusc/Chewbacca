# Contributing to Mac Claude Maxing

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
