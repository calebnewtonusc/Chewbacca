#!/usr/bin/env python3
"""Compatibility entry point for installations using the original Codex reader."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from agent_context import *  # noqa: F403: preserve the installed reader API

if __name__ == '__main__':
    raise SystemExit(main())
