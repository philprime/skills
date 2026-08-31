# Iterate PR Sources

## Iteration Changelog

### Narrow GitHub API wrappers

- **Evidence:** Local permission rules need to distinguish fixed read and reply operations from unrestricted `gh api` access.
- **Negative example:** Allow-listing the generic `gh api` command permits both reads and arbitrary writes, while Python helpers obscure otherwise standard `gh` operations.
- **Behavior delta:** Standard PR checks and run logs use direct `gh` commands. Each required GraphQL query or mutation lives in a narrow shell wrapper that can be allow-listed independently.
- **Preserved behavior:** Feedback remains categorized, checks and feedback are monitored in parallel, human gates terminate monitoring, and review-thread replies remain available after explicit confirmation.

### Feedback monitor completion

- **Evidence:** Human-verified regression from an `iterate-pr` run.
- **Negative example:** CI had no actionable pending checks and feedback was clear, but `monitor_pr_feedback.py` continued polling until its 30-minute timeout.
- **Behavior delta:** After a clear feedback fetch, the monitor now checks registered CI state and exits with `NO_ACTIONABLE_FEEDBACK` when no actionable checks remain.
- **Preserved behavior:** Actionable feedback still exits immediately, missing checks still receive their registration grace period through the parallel check monitor, and transient check-fetch failures do not cause early completion.
