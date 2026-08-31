#!/usr/bin/env bash

set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scripts_dir="$skill_dir/scripts"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat > "$tmp_dir/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >> "$GH_CALL_LOG"
printf '\n' >> "$GH_CALL_LOG"

if [[ "$1" == "api" && "$2" == "graphql" ]]; then
  cat "$GH_API_RESPONSE"
  exit 0
fi

if [[ "$1" == "pr" && "$2" == "checks" ]]; then
  cat "$GH_CHECKS_RESPONSE"
  exit "${GH_CHECKS_EXIT:-0}"
fi

if [[ "$1" == "pr" && "$2" == "view" ]]; then
  printf '%s\n' "${GH_PR_NUMBER:-123}"
  exit 0
fi

printf 'Unexpected gh invocation: %s\n' "$*" >&2
exit 1
STUB
chmod +x "$tmp_dir/bin/gh"

export PATH="$tmp_dir/bin:$PATH"
export GH_CALL_LOG="$tmp_dir/gh-calls.log"
export GH_API_RESPONSE="$tmp_dir/api-response.json"
export GH_CHECKS_RESPONSE="$tmp_dir/checks-response.json"
: > "$GH_CALL_LOG"

assert_jq() {
  local expression=$1
  local file=$2
  jq -e "$expression" "$file" >/dev/null
}

cat > "$GH_API_RESPONSE" <<'JSON'
{
  "data": {
    "repository": {
      "pullRequest": {
        "number": 123,
        "url": "https://github.example/pr/123",
        "reviewDecision": "CHANGES_REQUESTED",
        "isDraft": false,
        "author": {"login": "author"},
        "reviews": {
          "nodes": [
            {
              "state": "CHANGES_REQUESTED",
              "body": "This must be fixed",
              "author": {"login": "reviewer"}
            }
          ]
        },
        "reviewThreads": {
          "nodes": [
            {
              "id": "PRRT_medium",
              "isResolved": false,
              "isOutdated": false,
              "path": "src/example.ts",
              "line": 12,
              "comments": {
                "nodes": [
                  {
                    "id": "PRRC_medium",
                    "body": "m: handle this edge case",
                    "url": "https://github.example/comment/1",
                    "author": {"login": "warden-bot"}
                  }
                ]
              }
            },
            {
              "id": "PRRT_resolved",
              "isResolved": true,
              "isOutdated": false,
              "path": "src/old.ts",
              "line": 4,
              "comments": {
                "nodes": [
                  {
                    "id": "PRRC_resolved",
                    "body": "Already handled",
                    "url": "https://github.example/comment/2",
                    "author": {"login": "reviewer"}
                  }
                ]
              }
            }
          ]
        },
        "comments": {
          "nodes": [
            {
              "body": "l: optional cleanup",
              "url": "https://github.example/comment/3",
              "author": {"login": "author"}
            },
            {
              "body": "Coverage report",
              "url": "https://github.example/comment/4",
              "author": {"login": "codecov"}
            }
          ]
        }
      }
    }
  }
}
JSON

fetch_output="$tmp_dir/fetch-output.json"
"$scripts_dir/fetch-pr-feedback.sh" --pr 123 > "$fetch_output"
assert_jq '.summary == {"high":1,"medium":1,"low":1,"bot_comments":1,"resolved":1,"review_bot_feedback":1,"needs_attention":2}' "$fetch_output"
assert_jq '.feedback.medium[0] | .thread_id == "PRRT_medium" and .review_bot == true' "$fetch_output"
assert_jq '.feedback.low[0].self_authored == true' "$fetch_output"
grep -q 'api graphql' "$GH_CALL_LOG"

cat > "$GH_API_RESPONSE" <<'JSON'
{
  "data": {
    "repository": {
      "pullRequest": {
        "number": 123,
        "url": "https://github.example/pr/123",
        "reviewDecision": "REVIEW_REQUIRED",
        "isDraft": false,
        "author": {"login": "author"},
        "reviews": {"nodes": []},
        "reviewThreads": {"nodes": []},
        "comments": {"nodes": []}
      }
    }
  }
}
JSON
cat > "$GH_CHECKS_RESPONSE" <<'JSON'
[
  {
    "name": "Review required",
    "bucket": "pending",
    "state": "WAITING",
    "description": "Waiting for approval",
    "workflow": ""
  }
]
JSON

monitor_output="$tmp_dir/monitor-output.txt"
"$scripts_dir/monitor-pr-feedback.sh" --pr 123 --poll-seconds 0 --timeout-seconds 1 > "$monitor_output"
grep -q '^NO_ACTIONABLE_FEEDBACK$' "$monitor_output"

reply_body="$tmp_dir/reply.md"
printf 'Fixed the edge case.\n\nAdded a regression test.\n' > "$reply_body"
cat > "$GH_API_RESPONSE" <<'JSON'
{
  "data": {
    "addPullRequestReviewThreadReply": {
      "comment": {"id": "PRRC_reply"}
    }
  }
}
JSON

reply_output="$tmp_dir/reply-output.json"
"$scripts_dir/reply-to-feedback.sh" PRRT_medium "$reply_body" > "$reply_output"
assert_jq '. == {"thread_id":"PRRT_medium","comment_id":"PRRC_reply","status":"ok"}' "$reply_output"
grep -q 'addPullRequestReviewThreadReply' "$GH_CALL_LOG"
grep -q 'threadId=PRRT_medium' "$GH_CALL_LOG"
grep -q "body=@$reply_body" "$GH_CALL_LOG"

printf 'iterate-pr shell tests passed\n'
