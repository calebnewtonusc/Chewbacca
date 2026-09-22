#!/usr/bin/env python3
"""Link a shared skill library into a native discovery directory."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def install(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    linked, conflicts = [], []
    for skill in sorted(source.iterdir()):
        if not (skill / 'SKILL.md').is_file():
            continue
        target = destination / skill.name
        if target.exists() or target.is_symlink():
            if target.resolve() == skill.resolve():
                linked.append(skill.name)
            else:
                conflicts.append(skill.name)
            continue
        target.symlink_to(skill.resolve(), target_is_directory=True)
        linked.append(skill.name)
    return {'linked': linked, 'conflicts': conflicts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--destination', type=Path, default=Path.home() / '.agents/skills')
    args = parser.parse_args()
    source = args.source or Path.home() / '.chewbacca/skills'
    if not source.is_dir():
        source = ROOT / 'skills'
    print(json.dumps(install(source, args.destination)))


if __name__ == '__main__':
    main()
