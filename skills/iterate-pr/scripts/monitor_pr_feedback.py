#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# ///
"""
Monitor PR feedback until actionable feedback appears or the timeout expires.

Usage:
    uv run monitor_pr_feedback.py [--pr PR_NUMBER]

Output markers:
    FEEDBACK_NEEDS_ATTENTION   high or medium feedback exists
    LOW_PRIORITY_FEEDBACK      only low-priority feedback exists
    NO_ACTIONABLE_FEEDBACK     timeout reached without high/medium/low feedback
    FEEDBACK_MONITOR_ERROR     feedback could not be fetched

The script stays quiet while polling so background monitors do not emit
notifications until the agent needs to act.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def fetch_feedback(pr_number: int | None) -> dict[str, Any] | None:
    script = Path(__file__).with_name('fetch_pr_feedback.py')
    args = [sys.executable, str(script)]
    if pr_number is not None:
        args.extend(['--pr', str(pr_number)])

    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        parsed = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def print_feedback(marker: str, feedback: dict[str, Any] | None) -> None:
    print(marker, flush=True)
    if feedback is not None:
        print(json.dumps(feedback, indent=2), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description='Monitor PR feedback')
    parser.add_argument('--pr', type=int, help='PR number (defaults to current branch PR)')
    parser.add_argument(
        '--poll-seconds',
        type=int,
        default=30,
        help='Polling interval while waiting for feedback',
    )
    parser.add_argument(
        '--timeout-seconds',
        type=int,
        default=1800,
        help='Maximum time to wait before reporting no actionable feedback',
    )
    args = parser.parse_args()

    started_at = time.monotonic()

    while True:
        feedback = fetch_feedback(args.pr)
        if feedback is None or feedback.get('error'):
            if time.monotonic() - started_at >= args.timeout_seconds:
                print_feedback('FEEDBACK_MONITOR_ERROR', feedback)
                return 1
            time.sleep(args.poll_seconds)
            continue

        summary = feedback.get('summary') or {}
        high = int(summary.get('high') or 0)
        medium = int(summary.get('medium') or 0)
        low = int(summary.get('low') or 0)

        if high or medium:
            print_feedback('FEEDBACK_NEEDS_ATTENTION', feedback)
            return 0
        if low:
            print_feedback('LOW_PRIORITY_FEEDBACK', feedback)
            return 0

        if time.monotonic() - started_at >= args.timeout_seconds:
            print_feedback('NO_ACTIONABLE_FEEDBACK', feedback)
            return 0

        time.sleep(args.poll_seconds)


if __name__ == '__main__':
    sys.exit(main())
