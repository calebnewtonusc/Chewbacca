#!/usr/bin/env python3
"""Compatibility entry point for Codex skill installation."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from agent_skills import *  # noqa: F403: preserve the installed skill API

if __name__ == '__main__':
    main()
