#!/usr/bin/env bash
# Proves every contract and writes the summary. Exit 0 only when all are proven.
#
# Reads its settings from MLOLA_* variables (see action.yml). It can be run by
# hand the same way, outside GitHub Actions.
set -uo pipefail

contracts=${MLOLA_CONTRACTS:-contracts/*.json}
out=${MLOLA_OUT:-proof}
version=${MLOLA_CLI_VERSION:-0.18.0}
tmp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
comment_file="$tmp/mlola-prove-comment.md"
: >"$comment_file"

if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "::error::version must be an exact @mlola/browser-cli version, such as 0.18.0"
  exit 2
fi

# One install for all contracts, away from the project's own node_modules.
cli_dir="$tmp/mlola-cli-$version"
mlola=${MLOLA_BIN:-"$cli_dir/node_modules/.bin/mlola"}
if [[ -z ${MLOLA_BIN:-} && ! -x $mlola ]]; then
  echo "::group::Install @mlola/browser-cli@$version"
  npm install --prefix "$cli_dir" --no-audit --no-fund --silent "@mlola/browser-cli@$version" || {
    echo "::error::could not install @mlola/browser-cli@$version"
    exit 2
  }
  echo "::endgroup::"
fi

base=${MLOLA_BASE:-}
if [[ -z $base && -n ${MLOLA_PR_BASE:-} ]]; then base="origin/$MLOLA_PR_BASE"; fi

shopt -s nullglob
# shellcheck disable=SC2206  # the glob is meant to expand
files=($contracts)
shopt -u nullglob
if [[ ${#files[@]} -eq 0 ]]; then
  echo "::error::no contract matches \"$contracts\""
  exit 2
fi

worst=0          # 0 proven, 3 not proven yet, 1 not proven, 2 could not run
auto_merge=true
for contract in "${files[@]}"; do
  name=$(basename "$contract" .json)
  args=("$contract" --out "$out/$name" --summary "$comment_file")
  [[ -n ${MLOLA_BASE_URL:-} ]] && args+=(--base-url "$MLOLA_BASE_URL")
  [[ -n $base ]] && args+=(--base "$base")
  [[ -n ${MLOLA_APPROVED:-} ]] && args+=(--approved "$MLOLA_APPROVED")
  [[ -n ${MLOLA_STORAGE_STATE:-} ]] && args+=(--storage-state "$MLOLA_STORAGE_STATE")
  [[ ${MLOLA_REQUIRE_AUTO_MERGE:-false} == true ]] && args+=(--require-auto-merge)
  if [[ -n ${MLOLA_BASELINE_DIR:-} && -f "$MLOLA_BASELINE_DIR/$name/proof.json" ]]; then
    args+=(--baseline "$MLOLA_BASELINE_DIR/$name/proof.json")
  fi

  "$mlola" browser prove "${args[@]}"
  status=$?
  case $status in
    0) ;;
    3) [[ $worst -eq 0 ]] && worst=3 ;;
    1) [[ $worst -ne 2 ]] && worst=1 ;;
    *)
      worst=2
      # shellcheck disable=SC2016  # the backticks are Markdown
      printf '### %s\n\n`mlola prove` could not run this contract (exit %s). See the job log.\n\n' "$name" "$status" >>"$comment_file"
      ;;
  esac
  if ! grep -Eq '"autoMerge": *true' "$out/$name/proof.json" 2>/dev/null; then auto_merge=false; fi
done

case $worst in
  0) verdict=proven ;;
  3) verdict=not-proven-yet ;;
  *) verdict=not-proven ;;
esac

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then cat "$comment_file" >>"$GITHUB_STEP_SUMMARY"; fi
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "verdict=$verdict"
    echo "auto-merge=$auto_merge"
    echo "proof-dir=$out"
    echo "comment-file=$comment_file"
  } >>"$GITHUB_OUTPUT"
fi
echo "verdict: $verdict · auto-merge: $auto_merge · proofs in $out/"
exit $worst
