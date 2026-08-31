#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s THREAD_ID BODY_FILE\n' "$(basename "$0")" >&2
  exit 2
fi

thread_id=$1
body_file=$2

[[ -n "$thread_id" ]] || {
  printf 'THREAD_ID must not be empty\n' >&2
  exit 2
}
[[ -f "$body_file" && -r "$body_file" ]] || {
  printf 'BODY_FILE must be a readable file: %s\n' "$body_file" >&2
  exit 2
}

# GraphQL variables must remain literal for gh to submit them.
# shellcheck disable=SC2016
gh api graphql \
  -F threadId="$thread_id" \
  -F "body=@$body_file" \
  -f query='
    mutation($threadId: ID!, $body: String!) {
      addPullRequestReviewThreadReply(
        input: {
          pullRequestReviewThreadId: $threadId
          body: $body
        }
      ) {
        comment { id }
      }
    }
  ' | jq -e --arg thread_id "$thread_id" '
    .data.addPullRequestReviewThreadReply.comment.id as $comment_id
    | select($comment_id != null)
    | {
        thread_id: $thread_id,
        comment_id: $comment_id,
        status: "ok"
      }
  '
