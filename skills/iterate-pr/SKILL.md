---
name: iterate-pr
description: Iterate on an existing pull request until actionable feedback is handled and actionable checks pass. Use for PR CI failures, review feedback, green-check loops, or after pushing fixes; run checks and feedback monitors in parallel.
---

# Iterate PR

Fix actionable PR feedback and CI failures. Do not wait on human approval, draft readiness, merge gates, or informational bots.

Requires authenticated `gh`, `uv`, and the target repository root as cwd.

## Scripts

Run scripts from `skills/iterate-pr/` or use equivalent skill-root-relative paths.

| Script                           | Purpose                                             |
| -------------------------------- | --------------------------------------------------- |
| `scripts/fetch_pr_checks.py`     | fetch checks, summaries, and failure snippets       |
| `scripts/fetch_pr_feedback.py`   | fetch categorized feedback                          |
| `scripts/monitor_pr_checks.py`   | quiet check monitor; exits on pass/fail/block/no CI |
| `scripts/monitor_pr_feedback.py` | quiet feedback monitor; exits when feedback appears |
| `scripts/reply_to_thread.py`     | reply to review threads                             |

Check monitor markers:

- `ALL_CHECKS_PASSED`
- `CHECKS_DONE_WITH_FAILURES`
- `NO_CHECKS_REGISTERED`
- `DRAFT_PR_WITH_NO_CHECKS`
- `CHECKS_BLOCKED_BY_REVIEW_GATE`

Feedback monitor markers:

- `FEEDBACK_NEEDS_ATTENTION`
- `LOW_PRIORITY_FEEDBACK`
- `NO_ACTIONABLE_FEEDBACK`
- `FEEDBACK_MONITOR_ERROR`

## Workflow

1. Identify the PR:

```bash
gh pr view --json number,url,headRefName,isDraft,reviewDecision
```

Stop when no PR exists. For draft PRs with no checks, inspect current feedback but do not wait forever or mark ready unless asked.

2. Fetch initial state:

```bash
uv run scripts/fetch_pr_feedback.py [--pr NUMBER]
uv run scripts/fetch_pr_checks.py [--pr NUMBER]
```

3. Fix current high/medium feedback first:
   - verify root cause
   - search related code
   - fix all instances
   - treat `review_bot: true` as actionable when the issue is real
   - explain false positives instead of changing code

Ask the user before addressing low-priority suggestions.

4. Fix current failed checks:
   - read full failed logs with `gh run view <run-id> --log-failed`
   - state the failure cause before editing
   - fix root cause, not symptoms
   - add focused tests when needed

5. Verify locally, commit, and push:

```bash
git add <files>
git commit -m "fix: <descriptive message>"
git push
```

6. Start both monitors after every push:

```bash
uv run scripts/monitor_pr_checks.py [--pr NUMBER]
uv run scripts/monitor_pr_feedback.py [--pr NUMBER]
```

Run them as parallel background tasks. Feedback usually arrives before checks finish; when `monitor_pr_feedback.py` returns `FEEDBACK_NEEDS_ATTENTION`, fix that feedback immediately, verify, commit, push, and restart both monitors.

7. Handle monitor results:

| Result                          | Action                                                           |
| ------------------------------- | ---------------------------------------------------------------- |
| `FEEDBACK_NEEDS_ATTENTION`      | fix high/medium feedback, push, restart both monitors            |
| `LOW_PRIORITY_FEEDBACK`         | ask user which suggestions to address                            |
| `CHECKS_DONE_WITH_FAILURES`     | fetch failed checks/logs, fix, push, restart both monitors       |
| `ALL_CHECKS_PASSED`             | wait for feedback monitor result or run one final feedback fetch |
| `NO_ACTIONABLE_FEEDBACK`        | success if checks passed                                         |
| `CHECKS_BLOCKED_BY_REVIEW_GATE` | stop and report human review/approval gate                       |
| `NO_CHECKS_REGISTERED`          | stop and report no CI registered                                 |
| `DRAFT_PR_WITH_NO_CHECKS`       | stop and report draft/no-check state                             |
| `FEEDBACK_MONITOR_ERROR`        | fall back to `fetch_pr_feedback.py`; ask user if still unclear   |

## Exit Conditions

| Exit     | Conditions                                                                      |
| -------- | ------------------------------------------------------------------------------- |
| Success  | actionable checks passed and feedback monitor reports no actionable feedback    |
| Ask user | low-priority choice, unclear feedback, same failure twice, infrastructure issue |
| Stop     | no PR, branch needs rebase, no checks, draft no-checks, only human gates remain |

## Fallback

If scripts fail, use `gh` directly:

- `gh pr view --json number,url,headRefName,isDraft,reviewDecision`
- `gh pr checks --json name,state,bucket,description,link`
- `gh run view <run-id> --log-failed`
- `gh api repos/{owner}/{repo}/pulls/{number}/comments`
