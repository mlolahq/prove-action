#!/usr/bin/env bash
# Posts the proof as one comment on the pull request, and updates that comment
# on later runs. A failure here never fails the job: the proof is in the job
# summary and the artifact either way.
set -uo pipefail

marker='<!-- mlola-prove -->'
file=${MLOLA_COMMENT_FILE:-}
if [[ -z $file || ! -s $file ]]; then
  echo "no proof to post"
  exit 0
fi
if ! [[ ${MLOLA_PR:-} =~ ^[0-9]+$ ]]; then
  echo "not a pull request: nothing to comment on"
  exit 0
fi

body="$(mktemp)"
{
  echo "$marker"
  # GitHub refuses a comment over 65536 characters.
  head -c 60000 "$file"
  echo
  echo "Proofs and screenshots: [the \`${MLOLA_ARTIFACT:-mlola-proof}\` artifact of this run](${MLOLA_RUN_URL:-})."
} >"$body"

existing=$(gh api "repos/$MLOLA_REPO/issues/$MLOLA_PR/comments" --paginate \
  --jq "[.[] | select(.body | startswith(\"$marker\")) | .id] | first // empty" 2>/dev/null | head -n 1)

if [[ $existing =~ ^[0-9]+$ ]]; then
  gh api --method PATCH "repos/$MLOLA_REPO/issues/comments/$existing" -F "body=@$body" >/dev/null &&
    echo "updated the proof comment" || echo "::warning::could not update the proof comment"
else
  gh api --method POST "repos/$MLOLA_REPO/issues/$MLOLA_PR/comments" -F "body=@$body" >/dev/null &&
    echo "posted the proof comment" || echo "::warning::could not post the proof comment (does the job have pull-requests: write?)"
fi
exit 0
