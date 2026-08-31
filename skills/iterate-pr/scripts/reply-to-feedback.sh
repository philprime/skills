#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s --reply THREAD_ID BODY_FILE [--reply THREAD_ID BODY_FILE ...]\n' "$(basename "$0")" >&2
  exit 2
}

[[ $# -ge 3 ]] || usage

thread_ids=()
body_files=()

while [[ $# -gt 0 ]]; do
  [[ $# -ge 3 && "$1" == "--reply" ]] || usage

  thread_id=$2
  body_file=$3

  [[ -n "$thread_id" ]] || {
    printf 'THREAD_ID must not be empty\n' >&2
    exit 2
  }
  [[ -f "$body_file" && -r "$body_file" ]] || {
    printf 'BODY_FILE must be a readable file: %s\n' "$body_file" >&2
    exit 2
  }

  thread_ids+=("$thread_id")
  body_files+=("$body_file")
  shift 3
done

graphql_variables=""
graphql_replies=""
gh_args=(api graphql)

for index in "${!thread_ids[@]}"; do
  if [[ -n "$graphql_variables" ]]; then
    graphql_variables+=", "
  fi
  graphql_variables+="\$threadId${index}: ID!, \$body${index}: String!"
  graphql_replies+="
      r${index}: addPullRequestReviewThreadReply(
        input: {
          pullRequestReviewThreadId: \$threadId${index}
          body: \$body${index}
        }
      ) {
        comment {
          id
          state
          pullRequestReview {
            id
            state
          }
        }
      }"
  gh_args+=(-F "threadId${index}=${thread_ids[$index]}")
  gh_args+=(-F "body${index}=@${body_files[$index]}")
done

graphql_query="mutation(${graphql_variables}) {${graphql_replies}
    }"
reply_response=$(gh "${gh_args[@]}" -f "query=$graphql_query")

operations='[]'
pending_review_ids='[]'

for index in "${!thread_ids[@]}"; do
  comment_path=".data.r${index}.comment"
  comment_id=$(jq -er "${comment_path}.id" <<< "$reply_response")
  comment_state=$(jq -er "${comment_path}.state" <<< "$reply_response")
  review_id=$(jq -er "${comment_path}.pullRequestReview.id" <<< "$reply_response")
  review_state=$(jq -er "${comment_path}.pullRequestReview.state" <<< "$reply_response")

  operations=$(jq -c \
    --arg thread_id "${thread_ids[$index]}" \
    --arg comment_id "$comment_id" \
    --arg review_id "$review_id" \
    --arg review_state "$review_state" \
    '. + [{
      thread_id: $thread_id,
      comment_id: $comment_id,
      review_id: $review_id,
      review_state: $review_state,
      status: "ok"
    }]' <<< "$operations")

  if [[ "$comment_state" == "PENDING" || "$review_state" == "PENDING" ]]; then
    pending_review_ids=$(jq -c --arg review_id "$review_id" '
      if index($review_id) then . else . + [$review_id] end
    ' <<< "$pending_review_ids")
  fi
done

while IFS= read -r review_id; do
  # GraphQL variables must remain literal for gh to submit them.
  # shellcheck disable=SC2016
  submit_response=$(gh api graphql \
    -F reviewId="$review_id" \
    -f query='
      mutation($reviewId: ID!) {
        submitPullRequestReview(
          input: {
            pullRequestReviewId: $reviewId
            event: COMMENT
          }
        ) {
          pullRequestReview {
            id
            state
          }
        }
      }
    ')

  review_state=$(jq -er '.data.submitPullRequestReview.pullRequestReview.state' <<< "$submit_response")
  [[ "$review_state" != "PENDING" ]] || {
    printf 'Review remains pending after submission: %s\n' "$review_id" >&2
    exit 1
  }

  operations=$(jq -c --arg review_id "$review_id" --arg review_state "$review_state" '
    map(
      if .review_id == $review_id then
        .review_state = $review_state
      else
        .
      end
    )
  ' <<< "$operations")
done < <(jq -r '.[]' <<< "$pending_review_ids")

jq -n --argjson operations "$operations" '{
  replied: ($operations | length),
  operations: $operations,
  status: "ok"
}'
