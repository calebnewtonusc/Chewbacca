#!/usr/bin/env bash
# chewbacca completion <shell>: print completion for zsh, bash, or fish.
#
# Generated from the same subcommand table the help text uses, so a new verb
# is completable the moment it exists.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERBS="$(grep -oE '^  "[a-z-]+\|' "$ROOT/bin/chewbacca" | tr -d ' "|' | tr '\n' ' ')"

case "${1:-}" in
zsh)
  echo "#compdef chewbacca"
  echo "_chewbacca() { _arguments '1:command:($VERBS)' '*::arg:->args' }"
  echo "compdef _chewbacca chewbacca"
  ;;
bash)
  echo "_chewbacca() { COMPREPLY=(\$(compgen -W \"$VERBS\" -- \"\${COMP_WORDS[1]}\")); }"
  echo "complete -F _chewbacca chewbacca"
  ;;
fish)
  for v in $VERBS; do
    echo "complete -c chewbacca -n __fish_use_subcommand -a $v"
  done
  ;;
*)
  echo "usage: chewbacca completion [zsh|bash|fish]" >&2
  echo >&2
  echo "  zsh:  chewbacca completion zsh  > ~/.zsh/completions/_chewbacca" >&2
  echo "  bash: chewbacca completion bash >> ~/.bashrc" >&2
  echo "  fish: chewbacca completion fish > ~/.config/fish/completions/chewbacca.fish" >&2
  exit 2
  ;;
esac
