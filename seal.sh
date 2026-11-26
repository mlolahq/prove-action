#!/usr/bin/env bash
# Checks the proofs the prove job made, signs them, and writes the summary.
# Exit 0 only when every contract has a sound proof that is proven.
#
# Runs in a job that runs none of the change's code: it reads the contracts,
# and runs only the pinned CLI. The signing key, if any, is MLOLA_RECEIPT_KEY.
# Settings come from MLOLA_* variables (see seal/action.yml).
set -uo pipefail

contracts=${MLOLA_CONTRACTS:-contracts/*.json}
out=${MLOLA_OUT:-proof}
version=${MLOLA_CLI_VERSION:-0.20.0}
commit=${MLOLA_COMMIT:-${GITHUB_SHA:-}}
tmp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
comment_file="$tmp/mlola-seal-comment.md"
: >"$comment_file"

if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "::error::version must be an exact @mlola/browser-cli version, such as 0.20.0"
  exit 2
fi

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

signing=true
if [[ -z ${MLOLA_RECEIPT_KEY:-} ]]; then
  signing=false
  echo "::warning::no MLOLA_RECEIPT_KEY: the proofs are checked but stay unsigned (pull requests from forks get no secrets)"
fi

shopt -s nullglob
# shellcheck disable=SC2206  # the glob is meant to expand
files=($contracts)
shopt -u nullglob
if [[ ${#files[@]} -eq 0 ]]; then
  echo "::error::no contract matches \"$contracts\""
  exit 2
fi

worst=0          # 0 proven, 3 not proven yet, 1 not proven, 2 not sound or missing
auto_merge=true
signed=$signing
for contract in "${files[@]}"; do
  name=$(basename "$contract" .json)
  proof="$out/$name/proof.json"
  if [[ ! -f $proof ]]; then
    echo "::error::$name: no proof (the prove job did not write $proof)"
    # shellcheck disable=SC2016  # the backticks are Markdown
    printf '### %s\n\nNo proof: the prove job did not write `%s`. See its log.\n\n' "$name" "$proof" >>"$comment_file"
    worst=2
    auto_merge=false
    continue
  fi
  pin=(--contract "$contract")
  [[ -n $commit ]] && pin+=(--commit "$commit")

  if [[ $signing == true ]]; then
    if ! "$mlola" receipt seal "$proof" "${pin[@]}"; then
      echo "::error::$name: the proof was not sealed (see above)"
      signed=false
    fi
  fi

  "$mlola" receipt check "$proof" "${pin[@]}"
  status=$?
  if [[ $status -ne 0 && $status -ne 1 ]]; then
    echo "::error::$name: the proof is not sound (see above)"
    # shellcheck disable=SC2016  # the backticks are Markdown
    printf '### %s\n\nThe proof is not sound: `mlola receipt check` refused it. See the job log.\n\n' "$name" >>"$comment_file"
    worst=2
    auto_merge=false
    continue
  fi

  # Sound, so its own fields can be read: the checker judged them again.
  verdict=$(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(p.verdict+" "+p.autoMerge)' "$proof")
  case ${verdict%% *} in
    verified) ;;
    inconclusive) [[ $worst -eq 0 ]] && worst=3 ;;
    *) [[ $worst -ne 2 ]] && worst=1 ;;
  esac
  [[ ${verdict##* } == true ]] || auto_merge=false
  "$mlola" receipt show "$proof" --markdown >>"$comment_file"
  printf '\n' >>"$comment_file"
done

if [[ ${MLOLA_REQUIRE_AUTO_MERGE:-false} == true && $worst -eq 0 && $auto_merge != true ]]; then
  worst=3
fi

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
    echo "signed=$signed"
    echo "proof-dir=$out"
    echo "comment-file=$comment_file"
  } >>"$GITHUB_OUTPUT"
fi
echo "verdict: $verdict · auto-merge: $auto_merge · signed: $signed · proofs in $out/"
exit $worst
