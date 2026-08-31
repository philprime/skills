---
name: iterate-pr
description: Iterate on an existing pull request until actionable feedback is handled and actionable checks pass. Use for PR CI failures, review feedback, green-check loops, or after pushing fixes; run checks and feedback monitors in parallel.
---

# Iterate PR

Fix actionable PR feedback and CI failures. Do not wait on human approval, draft readiness, merge gates, or informational bots.

Require authenticated `gh` and `jq`. Run from the target repository root.

## Commands

Use standard read-only `gh` commands directly. Use the fixed-operation wrappers for GraphQL reads and writes so permission rules can allow-list each wrapper without allowing generic `gh api` access.

Always invoke wrappers by their absolute paths. Substitute the absolute skill path for `<skill>` below.

| Command                                                          | Operation                                                                                  |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `scripts/fetch-pr-feedback.sh`                                   | fixed read-only GraphQL query that fetches and categorizes feedback                        |
| `scripts/monitor-pr-feedback.sh`                                 | polls the fixed feedback query and exits when feedback appears or actionable checks finish |
| `scripts/reply-to-feedback.sh --reply THREAD_ID BODY_FILE [...]` | batches review-thread replies and submits reviews GitHub leaves pending                    |
| `gh pr checks NUMBER --json ...`                                 | reads checks                                                                               |
| `gh pr checks NUMBER --watch --fail-fast`                        | watches checks                                                                             |
| `gh run view RUN_ID --log-failed`                                | reads failed logs                                                                          |

`reply-to-feedback.sh` is externally visible and writes to GitHub. Get explicit user confirmation immediately before invoking it. Put each reply in a file and pass every confirmed reply to one wrapper invocation. Do not pass Markdown inline through the shell. Never launch concurrent reply wrappers because GitHub associates replies with mutable review state.

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

2. Fetch initial feedback and checks:

```bash
<skill>/scripts/fetch-pr-feedback.sh [--pr NUMBER]
gh pr checks NUMBER --json name,bucket,state,description,workflow,link
```

`gh pr checks` exits with status 8 while checks are pending and can exit nonzero for failures. Inspect its JSON output instead of treating those statuses as command errors.

3. Fix current high and medium feedback first:
   - verify the root cause
   - search related code
   - fix all instances
   - treat `review_bot: true` as actionable when the issue is real
   - explain false positives instead of changing code
   - judge each `self_authored: true` item because PR-author comments can be either change requests or reviewer context

Ask the user before addressing low-priority suggestions.

4. Fix current failed checks:
   - use the check link or list recent runs for the PR branch:

```bash
gh run list --branch HEAD_REF --limit 20 --json databaseId,name,status,conclusion,headSha,url
gh run view RUN_ID --log-failed
```

- state the failure cause before editing
- fix the root cause, not symptoms
- add focused tests when needed

5. Verify locally, commit, and push:

```bash
git add FILES
git commit -m "fix: descriptive message"
git push
```

6. Start both monitors after every push:

```bash
gh pr checks NUMBER --watch --fail-fast --interval 30
<skill>/scripts/monitor-pr-feedback.sh [--pr NUMBER]
```

Run them as parallel background tasks.

- If feedback returns first, stop the check watcher, fix the feedback, verify, commit, push, and restart both monitors.
- If the check watcher returns first, consume the feedback monitor result. Stop it only after a final feedback fetch is clear.
- If only human review or approval gates remain, the feedback monitor returns `NO_ACTIONABLE_FEEDBACK`. Stop the check watcher and report the gate.
- If checks fail, inspect the current check JSON and failed logs before editing.

7. Handle results:

| Result or state              | Action                                                                              |
| ---------------------------- | ----------------------------------------------------------------------------------- |
| `FEEDBACK_NEEDS_ATTENTION`   | fix high or medium feedback, push, restart both monitors                            |
| `LOW_PRIORITY_FEEDBACK`      | ask the user which suggestions to address                                           |
| failed check                 | fetch failed logs, fix, push, restart both monitors                                 |
| all actionable checks passed | consume the feedback monitor result and perform a final fetch if the monitor failed |
| `NO_ACTIONABLE_FEEDBACK`     | succeed if actionable checks passed                                                 |
| only human gates remain      | stop the check watcher and report the review or approval gate                       |
| no checks registered         | stop and report that no CI is registered                                            |
| draft PR with no checks      | stop and report the draft and no-check state                                        |
| `FEEDBACK_MONITOR_ERROR`     | run `fetch-pr-feedback.sh` once and ask the user if the result is still unclear     |

8. Reply to addressed review threads only when useful and after confirmation:

```bash
<skill>/scripts/reply-to-feedback.sh \
  --reply THREAD_ID BODY_FILE \
  --reply ANOTHER_THREAD_ID ANOTHER_BODY_FILE
```

Use each feedback item's GraphQL `thread_id`, such as `PRRT_...`. The wrapper batches all replies in one GraphQL mutation, submits any review GitHub created as pending, and returns each thread id, comment id, review id, final review state, and status as JSON.

## Exit Conditions

| Exit     | Conditions                                                                      |
| -------- | ------------------------------------------------------------------------------- |
| Success  | actionable checks passed and the final feedback fetch is clear                  |
| Ask user | low-priority choice, unclear feedback, same failure twice, infrastructure issue |
| Stop     | no PR, branch needs rebase, no checks, draft no-checks, only human gates remain |

## Failure Handling

If a wrapper fails, inspect its stderr and stop rather than falling back to unrestricted `gh api`. Standard read-only `gh pr` and `gh run` commands remain valid fallbacks for checks and logs.
