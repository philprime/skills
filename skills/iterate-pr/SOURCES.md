# Iterate PR Sources

## Iteration Changelog

### Feedback monitor completion

- **Evidence:** Human-verified regression from an `iterate-pr` run.
- **Negative example:** CI had no actionable pending checks and feedback was clear, but `monitor_pr_feedback.py` continued polling until its 30-minute timeout.
- **Behavior delta:** After a clear feedback fetch, the monitor now checks registered CI state and exits with `NO_ACTIONABLE_FEEDBACK` when no actionable checks remain.
- **Preserved behavior:** Actionable feedback still exits immediately, missing checks still receive their registration grace period through the parallel check monitor, and transient check-fetch failures do not cause early completion.
