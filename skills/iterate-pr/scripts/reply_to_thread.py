#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# ///
"""
Reply to PR review threads.

Usage:
    uv run reply_to_thread.py --reply THREAD_ID BODY [--reply THREAD_ID BODY ...]

Each --reply takes a thread node id and a reply body. Pass the flag once per
thread; all replies batch into a single GraphQL mutation for efficiency.

Example:
    uv run reply_to_thread.py --reply PRRT_abc "Fixed the issue."
    uv run reply_to_thread.py --reply PRRT_abc "Fixed." --reply PRRT_def "Also fixed."
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys


def _normalize_body(body: str) -> str:
    """Normalize escaped newlines from shell input.

    Bash double quotes keep "\\n" literal, but reply bodies should contain
    actual newlines for readability.
    """
    return body.replace('\\r\\n', '\\n').replace('\\n', '\n')


def reply_to_threads(pairs: list[tuple[str, str]]) -> list[tuple[str, bool]]:
    """Reply to one or more review threads in a single GraphQL call.

    Returns a per-operation list of (thread_id, success) tuples.
    """
    # Build aliased mutation
    mutations = []
    for i, (thread_id, body) in enumerate(pairs):
        escaped_thread_id = json.dumps(thread_id)
        escaped_body = json.dumps(_normalize_body(body))  # handles newlines, quotes
        mutations.append(
            f'  r{i}: addPullRequestReviewThreadReply(input: {{'
            f'pullRequestReviewThreadId: {escaped_thread_id}, '
            f'body: {escaped_body}'
            f'}}) {{ clientMutationId }}'
        )

    query = 'mutation {\n' + '\n'.join(mutations) + '\n}'

    try:
        result = subprocess.run(
            ['gh', 'api', 'graphql', '-f', f'query={query}'],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            print(f'GraphQL error: {result.stderr}', file=sys.stderr)
            return [(tid, False) for tid, _ in pairs]

        # Parse response to detect per-alias GraphQL errors
        try:
            response = json.loads(result.stdout)
        except (json.JSONDecodeError, TypeError):
            print(f'Failed to parse GraphQL response: {result.stdout}', file=sys.stderr)
            return [(tid, False) for tid, _ in pairs]

        data = response.get('data') or {}
        errors = response.get('errors') or []

        # Build a set of alias indices that have errors
        error_paths = set()
        for err in errors:
            for segment in err.get('path') or []:
                if isinstance(segment, str) and segment.startswith('r'):
                    error_paths.add(segment)

        operation_results = []
        for i, (tid, _) in enumerate(pairs):
            alias = f'r{i}'
            if alias in error_paths or data.get(alias) is None:
                operation_results.append((tid, False))
            else:
                operation_results.append((tid, True))

        if any(not ok for _, ok in operation_results):
            failed = [tid for tid, ok in operation_results if not ok]
            print(f'GraphQL partial failure for threads: {failed}', file=sys.stderr)

        return operation_results
    except subprocess.TimeoutExpired:
        print('Request timed out', file=sys.stderr)
        return [(tid, False) for tid, _ in pairs]


def main():
    parser = argparse.ArgumentParser(
        description='Reply to PR review threads',
    )
    parser.add_argument(
        '--reply',
        action='append',
        nargs=2,
        metavar=('THREAD_ID', 'BODY'),
        required=True,
        help='A review thread node id and the reply body; repeatable',
    )
    parsed = parser.parse_args()

    pairs = [(thread_id, body) for thread_id, body in parsed.reply]

    results = reply_to_threads(pairs)

    # Output results
    success = all(ok for _, ok in results)
    by_thread = {}
    for tid, ok in results:
        by_thread.setdefault(tid, []).append(ok)

    output = {
        'replied': sum(1 for _, ok in results if ok),
        'failed': sum(1 for _, ok in results if not ok),
        'operations': [
            {'thread_id': tid, 'status': 'ok' if ok else 'failed'}
            for tid, ok in results
        ],
        'threads': {
            tid: 'ok' if all(statuses) else 'failed'
            for tid, statuses in by_thread.items()
        },
    }
    print(json.dumps(output, indent=2))

    if not success:
        sys.exit(1)


if __name__ == '__main__':
    main()
