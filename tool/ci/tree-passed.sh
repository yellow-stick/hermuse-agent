#!/usr/bin/env bash
# Whether the tree of HEAD already passed a required check: prints `true` or
# `false`.
#
#   tool/ci/tree-passed.sh <prefix> <workflow-path>...
#
# A gate job that passes uploads the artifact `<prefix>-<tree>` (the tree of
# the commit it checked). The tree is the exact content: a merge group whose
# tree equals the merge commit a pull request run checked (same main, same
# change) has nothing new to check. Only a successful run of one of the given
# workflows, in this repository (never a fork's run), counts.
#
# Needs GH_TOKEN (actions: read) and GITHUB_REPOSITORY. Any API failure
# answers `false`: the check then runs.
set -euo pipefail

prefix=$1
shift
tree=$(git rev-parse 'HEAD^{tree}')
runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/artifacts?name=$prefix-$tree&per_page=20" \
  --jq '[.artifacts[] | select(.expired | not) | .workflow_run.id] | unique | .[]' 2>/dev/null) || runs=''
for run in $runs; do
  if gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run" 2>/dev/null |
    jq -e --arg repo "$GITHUB_REPOSITORY" --args \
      '.conclusion == "success" and .head_repository.full_name == $repo and (.path as $p | $ARGS.positional | index($p))' \
      "$@" >/dev/null; then
    echo "::notice::tree $tree already passed in run $run: nothing to check again" >&2
    echo true
    exit 0
  fi
done
echo false
