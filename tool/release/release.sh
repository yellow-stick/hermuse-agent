#!/usr/bin/env bash
# Cuts a release of Hermuse Agent from the maintainer's machine, with their gh
# credentials: a release pull request, the tag once it is merged, then the
# release run of the tag to its end.
#
#   tool/release/release.sh [--dry-run] patch|minor|major|rc|X.Y.Z|X.Y.Z-rc.N
#   tool/release/release.sh [--dry-run] tag [X.Y.Z[-rc.N]]
#   tool/release/release.sh [--dry-run] watch [X.Y.Z[-rc.N]]
#
# Version: from the app pubspec on origin/main (X.Y.Z+B or X.Y.Z-rc.N+B, the
# only version source, tool/release/release-metadata.sh). patch, minor and
# major bump X.Y.Z as semver does: a release candidate's own version comes
# first when it is of that kind (0.3.0-rc.2: patch and minor 0.3.0, major
# 1.0.0; 0.3.1-rc.1: patch 0.3.1, minor 0.4.0). rc is the next release
# candidate of the next patch: 0.3.0 -> 0.3.1-rc.1 -> 0.3.1-rc.2 (the rc of a
# minor or a major is given explicitly: 0.4.0-rc.1). An explicit version must
# be newer than every hermuse/v* tag. The build number B always goes up by one.
#
# 1. Preflight: gh logged in as an administrator of yellow-stick/hermuse-agent
#    (the "Release tags" ruleset lets only administrators create hermuse/v*
#    tags, so a workflow token cannot tag), a clean working tree, origin
#    fetched, HEAD at origin/main, neither the tag nor the release branch on
#    origin yet.
# 2. Release pull request: the branch yellow-stick/release-<version> holds one
#    commit on origin/main, `Release: Hermuse Agent <version>`: the pubspec
#    version and, for a final version, the download file names in README.md
#    and docs/guides/desktop.md (a release candidate leaves them on the last
#    final release). Its body names the version, the previous tag and the
#    commits since it. Auto-merge is turned on (the merge queue squashes it),
#    then the pull request is checked every 60 s until it is merged: a failed
#    check, a closed pull request or one out of the merge queue without being
#    merged stops the script, with the names of the failed checks.
# 3. tag: the squash commit of that pull request (`gh pr view --json
#    mergeCommit`), once its pubspec is checked to name the version, gets the
#    annotated tag hermuse/v<version>, pushed: release.yml starts.
# 4. watch: the release.yml run of the tag, checked every 60 s. A failed job
#    stops the script with the end of its log; when the run waits for the
#    `release` environment, the approval URL is printed. Exit 0 once the run
#    succeeded (the public pre-release, then the published-release check),
#    with the pre-release URL and the command that promotes it.
#
# `tag` and `watch` resume an interrupted release (default version: the
# pubspec of origin/main); `tag` first waits for a release pull request still
# open. --dry-run fetches and reads, and prints every action that would push
# or create something (commit, branch, pull request, auto-merge, tag) instead.
set -euo pipefail

REPO=yellow-stick/hermuse-agent
PUBSPEC=apps/hermuse_app/pubspec.yaml
DOWNLOAD_DOCS=(README.md docs/guides/desktop.md)
POLL=60
# User input; existing versions (pubspec, tags) are read leniently, as
# release-metadata.sh accepts them.
STRICT_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc\.([1-9][0-9]*))?$'
LENIENT_RE='^([0-9]+)\.([0-9]+)\.([0-9]+)(-rc\.([0-9]+))?$'
SEP=$'\x1f'

DRY_RUN=false
RESUME=''

die() {
  printf 'release: %s\n' "$*" >&2
  exit 1
}
usage_error() {
  printf 'release: %s (see --help)\n' "$*" >&2
  exit 2
}
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

# The arguments as one shell-quoted command line.
quote() {
  local arg line=''
  for arg in "$@"; do
    case $arg in
      '' | *[!A-Za-z0-9_./:=@%^+,-]*) arg="'${arg//\'/\'\\\'\'}'" ;;
    esac
    line+="${line:+ }$arg"
  done
  printf '%s\n' "$line"
}

# Runs a command that pushes or creates something; --dry-run prints it instead.
act() {
  if [ "$DRY_RUN" = true ]; then
    printf 'would run: %s\n' "$(quote "$@")" >&2
  else
    printf '+ %s\n' "$(quote "$@")" >&2
    "$@"
  fi
}

on_interrupt() {
  [ -z "$RESUME" ] || printf '\nstopped; resume with: %s\n' "$RESUME" >&2
  exit 130
}

# --- versions ------------------------------------------------------------------

# A sortable key of X.Y.Z[-rc.N]; a final version sorts after its release candidates.
version_key() {
  [[ $1 =~ $LENIENT_RE ]] || return 1
  printf '%010d%010d%010d%010d\n' "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))" \
    "$((10#${BASH_REMATCH[3]}))" "$((10#${BASH_REMATCH[5]:-9999999999}))"
}

# <current X.Y.Z[-rc.N]> <patch|minor|major|rc>
next_version() {
  [[ $1 =~ $LENIENT_RE ]] || die "'$1' is not X.Y.Z or X.Y.Z-rc.N"
  local x=$((10#${BASH_REMATCH[1]})) y=$((10#${BASH_REMATCH[2]})) z=$((10#${BASH_REMATCH[3]}))
  local rc=${BASH_REMATCH[5]}
  case $2 in
    patch)
      [ -n "$rc" ] || z=$((z + 1))
      echo "$x.$y.$z"
      ;;
    minor)
      if [ -z "$rc" ] || [ "$z" != 0 ]; then y=$((y + 1)); fi
      echo "$x.$y.0"
      ;;
    major)
      if [ -z "$rc" ] || [ "$y" != 0 ] || [ "$z" != 0 ]; then x=$((x + 1)); fi
      echo "$x.0.0"
      ;;
    rc)
      if [ -n "$rc" ]; then echo "$x.$y.$z-rc.$((10#$rc + 1))"; else echo "$x.$y.$((z + 1))-rc.1"; fi
      ;;
  esac
}

is_rc() { [[ $1 == *-rc.* ]]; }

# <key> <metadata>: one value of release-metadata.sh's key=value lines.
meta() { sed -n "s/^$1=//p" <<<"$2"; }

# The hermuse/v* tags on origin, one per line.
remote_tags() { git ls-remote --tags --refs origin 'refs/tags/hermuse/v*' | sed 's|.*refs/tags/||'; }

# <tag>: the commit a tag on origin points at (annotated or not); empty when origin has no such tag.
remote_tag_commit() {
  git ls-remote origin "refs/tags/$1" "refs/tags/$1^{}" |
    awk -v ref="refs/tags/$1" '$2 == ref "^{}" { peeled = $1 } $2 == ref { plain = $1 }
      END { print (peeled != "" ? peeled : plain) }'
}

# <tags> <version> <finals only: true|false>: the newest tag older than the version.
previous_tag() {
  local tag key best='' best_key='' limit
  limit=$(version_key "$2")
  while read -r tag; do
    key=$(version_key "${tag#hermuse/v}") || continue
    [[ $key < $limit ]] || continue
    [ "$3" = false ] || ! is_rc "$tag" || continue
    if [[ $key > $best_key ]]; then best=$tag best_key=$key; fi
  done <<<"$1"
  printf '%s\n' "$best"
}

# <version argument>: X.Y.Z[-rc.N], with or without hermuse/v.
version_arg() {
  local version=${1#hermuse/v}
  [[ $version =~ $STRICT_RE ]] || usage_error "'$1' is not X.Y.Z or X.Y.Z-rc.N"
  printf '%s\n' "$version"
}

# --- repository ----------------------------------------------------------------

check_gh() {
  command -v gh >/dev/null || die "the GitHub CLI is required: https://cli.github.com"
  gh auth status --hostname github.com >/dev/null 2>&1 || die "gh is not logged in to github.com: gh auth login"
}

# Only administrators push hermuse/v* tags (the "Release tags" ruleset).
check_admin() {
  local admin
  admin=$(gh api "repos/$REPO" --jq '.permissions.admin') || die "cannot read $REPO with gh"
  [ "$admin" = true ] ||
    die "only administrators of $REPO push hermuse/v* tags (the \"Release tags\" ruleset): ask one to run this"
}

check_origin() {
  local url slug
  url=$(git remote get-url origin 2>/dev/null) || die "this checkout has no 'origin' remote"
  slug=${url%.git}
  slug=${slug#*github.com[:/]}
  [ "$slug" = "$REPO" ] || die "origin is $url: releases are cut in $REPO"
}

fetch_origin() {
  git fetch --quiet --tags origin ||
    die "git fetch --tags origin failed (a local hermuse/v* tag that differs from origin's? git tag -l 'hermuse/v*')"
}

# <commit> <file>: the app pubspec of a commit, as release-metadata.sh reads it.
pubspec_of() {
  mkdir -p "$(dirname "$2")"
  git show "$1:$PUBSPEC" >"$2" || die "no $PUBSPEC in $1"
}

# <version>: the version argument of tag/watch, by default the pubspec version of origin/main.
version_or_main() {
  if [ -n "$1" ]; then
    version_arg "$1"
  else
    pubspec_of origin/main "$WORK/pubspec.main"
    meta app_version "$("$METADATA" --pubspec "$WORK/pubspec.main")"
  fi
}

# --- release pull request ------------------------------------------------------

# <old file> <new file>: a unified diff for the reader; differences are expected.
show_diff() { diff -u --label "a/$3" --label "b/$3" "$1" "$2" || true; }

# Regex-quotes a literal for sed.
sed_literal() { printf '%s\n' "$1" | sed 's/[]\/$*.^[]/\\&/g'; }

# The download names of a final release in the user docs follow the new
# version: the names of the last final release (as README.md shows them) give
# way to those of this one.
bump_download_docs() { # <new metadata>
  local old_deb old_version old_appimage new_deb new_appimage new_version doc
  old_deb=$(git show "$BASE:README.md" | grep -oE 'hermuse-agent_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+_amd64\.deb' | head -n 1) || true
  if [ -z "$old_deb" ]; then
    log "README.md names no hermuse-agent_X.Y.Z-B_amd64.deb: the download names stay as they are"
    return 0
  fi
  old_version=${old_deb#hermuse-agent_}
  old_version=${old_version%-*}
  old_appimage="Hermuse-Agent-$old_version-linux-x86_64.AppImage"
  new_deb=$(meta deb_file "$1")
  new_appimage=$(meta appimage_file "$1")
  new_version=$(meta app_version "$1")
  for doc in "${DOWNLOAD_DOCS[@]}"; do
    git cat-file -e "$BASE:$doc" 2>/dev/null || continue
    mkdir -p "$WORK/old/$(dirname "$doc")" "$WORK/new/$(dirname "$doc")"
    git show "$BASE:$doc" >"$WORK/old/$doc"
    sed -e "s/$(sed_literal "$old_deb")/$new_deb/g" \
      -e "s/$(sed_literal "$old_appimage")/$new_appimage/g" \
      -e "s/Hermuse Agent $(sed_literal "$old_version") /Hermuse Agent $new_version /g" \
      "$WORK/old/$doc" >"$WORK/new/$doc"
    cmp -s "$WORK/old/$doc" "$WORK/new/$doc" && continue
    if { [ "$old_deb" != "$new_deb" ] && grep -qF "$old_deb" "$WORK/new/$doc"; } ||
      { [ "$old_appimage" != "$new_appimage" ] && grep -qF "$old_appimage" "$WORK/new/$doc"; }; then
      die "$doc still names the $old_version downloads after the update"
    fi
    CHANGED+=("$doc")
  done
  DOCS_OLD=$old_deb
  DOCS_NEW=$new_deb
}

# One commit on origin/main with the files of $WORK/new, made without touching
# the working tree or HEAD (a temporary index). Sets COMMIT.
make_release_commit() {
  local index=$WORK/index file mode blob tree
  GIT_INDEX_FILE=$index git read-tree "$BASE"
  for file in "${CHANGED[@]}"; do
    mode=$(git ls-tree "$BASE" -- "$file" | cut -d' ' -f1)
    blob=$(git hash-object -w --path="$file" "$WORK/new/$file")
    GIT_INDEX_FILE=$index git update-index --cacheinfo "$mode,$blob,$file"
  done
  tree=$(GIT_INDEX_FILE=$index git write-tree)
  COMMIT=$(git commit-tree "$tree" -p "$BASE" -m "Release: Hermuse Agent $VERSION")
  pubspec_of "$COMMIT" "$WORK/pubspec.commit"
  "$METADATA" --pubspec "$WORK/pubspec.commit" --tag "$TAG" >/dev/null
  git show --stat --format='%h %s' "$COMMIT"
}

write_pr_body() { # <file> <current pubspec version> <new pubspec version>
  local range=$BASE label=final count changes since items docs
  if [ -n "$PREVIOUS_TAG" ]; then range="$PREVIOUS_TAG..$BASE"; fi
  if is_rc "$VERSION"; then label='release candidate'; fi
  count=$(git rev-list --count "$range")
  changes=$(git log --oneline --max-count=100 "$range")
  [ "$count" -le 100 ] || changes+=$'\n'"… and $((count - 100)) more"
  items="- \`$PUBSPEC\`: \`$2\` → \`$3\`."
  if [ "${#CHANGED[@]}" -gt 1 ]; then
    docs=$(printf ', %s' "${CHANGED[@]:1}")
    items+=$'\n'"- Download names in ${docs#, }: \`$DOCS_OLD\` → \`$DOCS_NEW\`."
  fi
  if [ -n "$PREVIOUS_TAG" ]; then
    since="Previous tag: \`$PREVIOUS_TAG\`; the $count commits since it (\`git log --oneline $PREVIOUS_TAG..origin/main\`):"
  else
    since="No previous tag, first release; the $count commits of main (\`git log --oneline origin/main\`):"
  fi
  cat >"$1" <<EOF
Release of Hermuse Agent $VERSION ($label), cut by \`tool/release/release.sh\`.

$items
- Once merged, its squash commit is tagged \`$TAG\`: \`release.yml\` builds and signs it, runs every smoke leg, waits for the \`release\` approval, publishes a public pre-release and checks its downloads.

$since

\`\`\`text
$changes
\`\`\`
EOF
}

# --- merge, tag, release run ---------------------------------------------------

# <number>: one line, fields separated by $SEP: state, in merge queue, merge
# queue entry state, auto-merge on, pending checks, checks, failed checks
# (comma-separated names).
pr_status() {
  # shellcheck disable=SC2016 # GraphQL variables and jq, not shell expansions
  gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F number="$1" -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          state isInMergeQueue
          mergeQueueEntry { state }
          autoMergeRequest { enabledAt }
          commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
            __typename
            ... on CheckRun { name status conclusion }
            ... on StatusContext { context state }
          } } } } } }
        }
      }
    }' --jq '
    .data.repository.pullRequest as $pr
    | [$pr.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]? | {
        name: (.name // .context),
        done: (if .__typename == "CheckRun" then .status == "COMPLETED" else (.state | IN("PENDING", "EXPECTED") | not) end),
        failed: (if .__typename == "CheckRun"
                 then (.conclusion | IN("FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"))
                 else (.state | IN("FAILURE", "ERROR")) end)
      }] as $checks
    | [$pr.state, ($pr.isInMergeQueue | tostring), ($pr.mergeQueueEntry.state // "-"),
       ($pr.autoMergeRequest != null | tostring),
       ([$checks[] | select(.done | not)] | length | tostring), ($checks | length | tostring),
       ([$checks[] | select(.failed) | .name] | unique | join(", "))]
    | join("\u001f")'
}

# <number>: the failed runs of the latest merge group of a pull request, and their failed jobs.
report_merge_group_failures() {
  local run url name
  gh run list -R "$REPO" --event merge_group --limit 50 --json databaseId,headBranch,headSha,conclusion,url,workflowName \
    --jq "[.[] | select(.headBranch | startswith(\"gh-readonly-queue/main/pr-$1-\"))]
      | (.[0].headSha) as \$latest | .[] | select(.headSha == \$latest)
      | select(.conclusion | IN(\"failure\", \"cancelled\", \"timed_out\", \"startup_failure\"))
      | \"\(.databaseId) \(.url) \(.workflowName)\"" |
    while read -r run url name; do
      printf '  merge queue: %s failed, %s\n' "$name" "$url"
      gh run view "$run" -R "$REPO" --json jobs \
        --jq '.jobs[] | select(.conclusion | IN("failure", "cancelled", "timed_out")) | "    \(.name): \(.conclusion)"' || true
    done
}

# <number>: waits until the pull request is merged.
wait_for_merge() {
  local number=$1 line state in_queue queue_state auto pending total failed
  local status last='' seen_queue=false unqueued=0
  RESUME="tool/release/release.sh tag $VERSION"
  log "waiting for #$number to be merged, checked every ${POLL}s (Ctrl-C stops waiting: $RESUME resumes)"
  while :; do
    if ! line=$(pr_status "$number"); then
      log "#$number could not be read: trying again"
      sleep "$POLL"
      continue
    fi
    IFS=$SEP read -r state in_queue queue_state auto pending total failed <<<"$line"
    case $state in
      MERGED)
        log "#$number is merged"
        return 0
        ;;
      CLOSED) die "#$number was closed without being merged" ;;
    esac
    [ -z "$failed" ] ||
      die "#$number has failed checks: $failed (https://github.com/$REPO/pull/$number/checks). Re-run them or fix main, then: $RESUME"
    [ "$in_queue" != true ] || seen_queue=true
    if [ "$in_queue" != true ] && [ "$auto" != true ]; then
      # Neither queued nor set to merge: left the queue, or auto-merge was turned off. Settles in seconds: look twice.
      if [ "$unqueued" -ge 1 ]; then
        report_merge_group_failures "$number" >&2
        [ "$seen_queue" = false ] ||
          die "#$number left the merge queue without being merged. Once fixed: gh pr merge $number -R $REPO --squash --auto, then $RESUME"
        die "#$number is no longer set to merge (auto-merge turned off): gh pr merge $number -R $REPO --squash --auto, then $RESUME"
      fi
      unqueued=$((unqueued + 1))
      sleep 20
      continue
    fi
    unqueued=0
    status="checks $((total - pending))/$total done"
    [ "$in_queue" != true ] || status="in the merge queue ($queue_state), $status"
    [ "$status" = "$last" ] || log "#$number: $status"
    last=$status
    sleep "$POLL"
  done
}

# <number>: tags the squash commit of the merged release pull request (sets
# MERGE_COMMIT), or finds the tag already there on that commit.
tag_release() {
  local remote local_commit
  MERGE_COMMIT=$(gh pr view "$1" -R "$REPO" --json mergeCommit --jq '.mergeCommit.oid // empty')
  [ -n "$MERGE_COMMIT" ] || die "#$1 has no merge commit"
  git merge-base --is-ancestor "$MERGE_COMMIT" origin/main 2>/dev/null || fetch_origin
  git merge-base --is-ancestor "$MERGE_COMMIT" origin/main ||
    die "$MERGE_COMMIT, the merge commit of #$1, is not on origin/main"
  pubspec_of "$MERGE_COMMIT" "$WORK/pubspec.merged"
  "$METADATA" --pubspec "$WORK/pubspec.merged" --tag "$TAG" >/dev/null ||
    die "the pubspec of $MERGE_COMMIT does not name $VERSION: nothing tagged"
  log "$MERGE_COMMIT, the squash commit of #$1, names $VERSION in $PUBSPEC"
  remote=$(remote_tag_commit "$TAG")
  if [ -n "$remote" ]; then
    [ "$remote" = "$MERGE_COMMIT" ] || die "origin already has $TAG, on $remote instead of $MERGE_COMMIT"
    log "$TAG is already on origin, on $MERGE_COMMIT"
    return 0
  fi
  if local_commit=$(git rev-parse -q --verify "refs/tags/$TAG^{commit}"); then
    [ "$local_commit" = "$MERGE_COMMIT" ] ||
      die "the local tag $TAG points at $local_commit, not $MERGE_COMMIT: git tag -d $TAG, then tool/release/release.sh tag $VERSION"
  else
    act git tag -a -m "Hermuse Agent $VERSION" "$TAG" "$MERGE_COMMIT"
  fi
  act git push origin "refs/tags/$TAG"
}

# [commit]: sets RUN_ID and RUN_URL to the newest release.yml run of TAG (on that commit); empty when none.
find_release_run() {
  local filter=".headBranch == \"$TAG\" and (.event == \"push\" or .event == \"workflow_dispatch\")"
  [ -z "${1:-}" ] || filter+=" and .headSha == \"$1\""
  RUN_ID='' RUN_URL=''
  read -r RUN_ID RUN_URL < <(gh run list -R "$REPO" --workflow release.yml --branch "$TAG" --limit 20 \
    --json databaseId,url,headBranch,headSha,event --jq "[.[] | select($filter)][0] | select(.) | \"\(.databaseId) \(.url)\"") ||
    true
}

# <commit>: waits for the run the tag push starts.
wait_for_run() {
  local deadline=$((SECONDS + 180))
  find_release_run "$1"
  while [ -z "$RUN_ID" ]; do
    [ "$SECONDS" -lt "$deadline" ] ||
      die "no release.yml run for $TAG after 3 minutes: https://github.com/$REPO/actions/workflows/release.yml"
    sleep 10
    find_release_run "$1"
  done
  log "release run of $TAG: $RUN_URL"
}

# Prints the approval of each environment the run waits for, once.
announce_approvals() {
  local pending env_id env_name
  pending=$(gh api "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" \
    --jq '.[] | "\(.environment.id)\u001f\(.environment.name)"') || return 0
  while IFS=$SEP read -r env_id env_name; do
    [ -n "$env_id" ] || continue
    case " $ANNOUNCED " in *" $env_id "*) continue ;; esac
    ANNOUNCED+=" $env_id"
    cat <<EOF

The release run waits for the approval of the \`$env_name\` environment. Approve it on the run page
(Review deployments, tick $env_name, Approve and deploy):
  $RUN_URL
or from here:
  gh api -X POST repos/$REPO/actions/runs/$RUN_ID/pending_deployments -F 'environment_ids[]=$env_id' -f state=approved -f comment='$TAG'

EOF
  done <<<"$pending"
}

# <failed jobs: id<SEP>name per line> <publish conclusion>
report_failures() {
  local id name
  while IFS=$SEP read -r id name; do
    printf '\nFailed: %s\n' "$name"
    gh run view -R "$REPO" --job "$id" --log-failed 2>/dev/null | tail -n 40 ||
      printf '  (no log yet: gh run view -R %s --job %s --log)\n' "$REPO" "$id"
  done <<<"$1"
  echo
  if [ "$2" = success ]; then
    die "$TAG is published, but its published-release check failed ($RUN_URL). A published release is never replaced: fix it on main and release the next version."
  fi
  die "the release run of $TAG failed: nothing is published ($RUN_URL). The run goes on for the evidence of its other jobs; a flaky job: gh run rerun $RUN_ID -R $REPO --failed once it ends, then tool/release/release.sh watch $VERSION; a defect: fix it on main and release the next version."
}

report_published() {
  local url
  url=$(gh release view "$TAG" -R "$REPO" --json url --jq .url 2>/dev/null) || url="https://github.com/$REPO/releases/tag/$TAG"
  log "Hermuse Agent $VERSION is published as a pre-release, its downloads checked: $url"
  if is_rc "$VERSION"; then
    echo "A release candidate stays a pre-release."
  else
    echo "Once the points under \"Not yet proven\" in its notes are checked, make it the latest release:"
    echo "  gh release edit $TAG -R $REPO --prerelease=false --latest"
  fi
}

# Follows RUN_ID to its end.
watch_run() {
  local out status conclusion id job_status job_conclusion name finished total failed publish summary last=''
  RESUME="tool/release/release.sh watch $VERSION"
  ANNOUNCED=''
  log "following $RUN_URL, checked every ${POLL}s (Ctrl-C stops following: $RESUME resumes)"
  while :; do
    if ! out=$(gh run view "$RUN_ID" -R "$REPO" --json status,conclusion,jobs --jq '"\(.status)\u001f\(.conclusion)",
      (.jobs[] | "\(.databaseId)\u001f\(.status)\u001f\(.conclusion)\u001f\(.name)")'); then
      log "the run could not be read: trying again"
      sleep "$POLL"
      continue
    fi
    IFS=$SEP read -r status conclusion <<<"${out%%$'\n'*}"
    finished=0 total=0 failed='' publish=''
    while IFS=$SEP read -r id job_status job_conclusion name; do
      [ -n "$id" ] || continue
      total=$((total + 1))
      [ "$job_status" != completed ] || finished=$((finished + 1))
      [ "$name" != Publish ] || publish=$job_conclusion
      case $job_conclusion in
        failure | cancelled | timed_out | startup_failure) failed+="$id$SEP$name"$'\n' ;;
      esac
    done < <(tail -n +2 <<<"$out")
    [ -z "$failed" ] || report_failures "${failed%$'\n'}" "$publish"
    if [ "$status" = completed ]; then
      [ "$conclusion" = success ] || die "the release run of $TAG ended '$conclusion': $RUN_URL"
      [ "$publish" = success ] || die "the release run of $TAG ended without publishing (Publish: ${publish:-no such job}): $RUN_URL"
      report_published
      return 0
    fi
    [ "$status" != waiting ] || announce_approvals
    summary="$status, $finished/$total jobs done"
    [ "$summary" = "$last" ] || log "$summary"
    last=$summary
    [ "$DRY_RUN" = false ] || {
      echo "would follow it until it ends (every ${POLL}s)"
      return 0
    }
    sleep "$POLL"
  done
}

# --- commands ------------------------------------------------------------------

cmd_release() { # <patch|minor|major|rc|X.Y.Z|X.Y.Z-rc.N>
  local bump=$1 current_meta current current_build new_pubspec new_meta tags newest='' tag key newest_key=''
  local number pr_url kind docs file
  case $bump in
    patch | minor | major | rc) ;;
    *) [[ $bump =~ $STRICT_RE ]] || usage_error "'$bump' is not patch, minor, major, rc, X.Y.Z or X.Y.Z-rc.N" ;;
  esac
  check_gh
  check_origin
  check_admin
  [ -z "$(git status --porcelain)" ] ||
    die "the working tree has changes (git status): commit or stash them, or release from a clean worktree: git worktree add --detach ../hermuse-release origin/main"
  fetch_origin
  BASE=$(git rev-parse origin/main)
  [ "$(git rev-parse HEAD)" = "$BASE" ] ||
    die "HEAD is $(git rev-parse --short HEAD), not origin/main ($(git rev-parse --short "$BASE")): release from origin/main itself (git switch --detach origin/main, or git switch main && git merge --ff-only origin/main)"

  pubspec_of "$BASE" "$WORK/old/$PUBSPEC"
  current_meta=$("$METADATA" --pubspec "$WORK/old/$PUBSPEC")
  current=$(meta app_version "$current_meta")
  current_build=$(meta build_number "$current_meta")
  case $bump in
    patch | minor | major | rc) VERSION=$(next_version "$current" "$bump") ;;
    *) VERSION=$bump ;;
  esac
  TAG=hermuse/v$VERSION
  BRANCH=yellow-stick/release-$VERSION
  new_pubspec="$VERSION+$((10#$current_build + 1))"

  tags=$(remote_tags)
  while read -r tag; do
    key=$(version_key "${tag#hermuse/v}") || continue
    if [[ $key > $newest_key ]]; then newest=$tag newest_key=$key; fi
  done <<<"$tags"
  [ -z "$newest" ] || [[ $(version_key "$VERSION") > $newest_key ]] ||
    die "$VERSION is not newer than $newest, the newest release tag"
  [ -z "$(remote_tag_commit "$TAG")" ] || die "origin already has $TAG"
  ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null ||
    die "a local tag $TAG exists but origin has none: git tag -d $TAG"
  [ -z "$(git ls-remote --heads origin "refs/heads/$BRANCH")" ] ||
    die "origin already has $BRANCH, an earlier attempt: resume it with tool/release/release.sh tag $VERSION, or drop it: gh pr close $BRANCH -R $REPO --delete-branch (without a pull request: git push origin --delete $BRANCH)"
  if is_rc "$VERSION"; then
    PREVIOUS_TAG=$(previous_tag "$tags" "$VERSION" false)
    kind='release candidate, a public pre-release'
  else
    PREVIOUS_TAG=$(previous_tag "$tags" "$VERSION" true)
    kind='final, a public pre-release until promoted'
  fi

  # The pubspec, then for a final version the download names of the user docs.
  mkdir -p "$WORK/new/$(dirname "$PUBSPEC")"
  sed "s/^version:.*/version: $new_pubspec/" "$WORK/old/$PUBSPEC" >"$WORK/new/$PUBSPEC"
  new_meta=$("$METADATA" --pubspec "$WORK/new/$PUBSPEC" --tag "$TAG") ||
    die "$new_pubspec does not make a valid release of $TAG"
  [ "$(meta pubspec_version "$new_meta")" = "$new_pubspec" ] || die "the pubspec version did not become $new_pubspec"
  CHANGED=("$PUBSPEC")
  DOCS_OLD='' DOCS_NEW=''
  if is_rc "$VERSION"; then
    docs='unchanged: README.md and docs/guides/desktop.md keep the last final release'
  else
    bump_download_docs "$new_meta"
    docs=${DOCS_OLD:+$DOCS_OLD -> $DOCS_NEW}
  fi

  cat <<EOF
Hermuse Agent $VERSION$([ "$DRY_RUN" = false ] || echo ' (dry run: nothing is pushed or created)')
  repository  $REPO, origin/main $(git log -1 --format='%h %s' "$BASE")
  pubspec     $(meta pubspec_version "$current_meta") -> $new_pubspec ($PUBSPEC)
  version     $VERSION ($kind)
  tag         $TAG
  branch      $BRANCH
  previous    ${PREVIOUS_TAG:-none (first release)}
  files       ${CHANGED[*]}
  downloads   ${docs:-unchanged}
EOF
  echo
  for file in "${CHANGED[@]}"; do show_diff "$WORK/old/$file" "$WORK/new/$file" "$file"; done
  echo
  write_pr_body "$WORK/pr-body.md" "$(meta pubspec_version "$current_meta")" "$new_pubspec"

  if [ "$DRY_RUN" = true ]; then
    echo "would commit on origin/main ($(git rev-parse --short "$BASE")): Release: Hermuse Agent $VERSION (${CHANGED[*]})"
    act git push origin "<release commit>:refs/heads/$BRANCH"
    act gh pr create -R "$REPO" --base main --head "$BRANCH" --title "Release: Hermuse Agent $VERSION" --body-file '<body below>'
    act gh pr merge '<pull request>' -R "$REPO" --squash --auto
    echo "would wait for the merge, checking the pull request every ${POLL}s (stops on a failed check or one out of the merge queue)"
    act gh pr view '<pull request>' -R "$REPO" --json mergeCommit
    act git tag -a -m "Hermuse Agent $VERSION" "$TAG" '<squash commit>'
    act git push origin "refs/tags/$TAG"
    echo "would follow the release.yml run of $TAG (gh run list -R $REPO --workflow release.yml --branch $TAG) until it ends"
    printf '\npull request body:\n'
    sed 's/^/  | /' "$WORK/pr-body.md"
    return 0
  fi

  make_release_commit
  act git push origin "$COMMIT:refs/heads/$BRANCH"
  pr_url=$(act gh pr create -R "$REPO" --base main --head "$BRANCH" --title "Release: Hermuse Agent $VERSION" \
    --body-file "$WORK/pr-body.md")
  number=${pr_url##*/}
  log "release pull request: $pr_url"
  act gh pr merge "$number" -R "$REPO" --squash --auto
  wait_for_merge "$number"
  tag_release "$number"
  wait_for_run "$MERGE_COMMIT"
  watch_run
}

cmd_tag() { # [version]
  local pr number state
  check_gh
  check_origin
  check_admin
  fetch_origin
  VERSION=$(version_or_main "$1")
  TAG=hermuse/v$VERSION
  BRANCH=yellow-stick/release-$VERSION
  pr=$(gh pr list -R "$REPO" --head "$BRANCH" --base main --state all --json number,state \
    --jq 'sort_by(.number) | last | select(.) | "\(.number) \(.state)"')
  [ -n "$pr" ] || die "no pull request from $BRANCH: cut the release first, tool/release/release.sh $VERSION"
  read -r number state <<<"$pr"
  log "$TAG: release pull request #$number, $state"
  case $state in
    MERGED) ;;
    OPEN)
      if [ "$DRY_RUN" = true ]; then
        echo "would wait for the merge of #$number, then tag its squash commit:"
        act gh pr view "$number" -R "$REPO" --json mergeCommit
        act git tag -a -m "Hermuse Agent $VERSION" "$TAG" '<squash commit>'
        act git push origin "refs/tags/$TAG"
        return 0
      fi
      wait_for_merge "$number"
      ;;
    *) die "#$number was closed without being merged: cut the release again, tool/release/release.sh $VERSION" ;;
  esac
  tag_release "$number"
  if [ "$DRY_RUN" = true ]; then
    echo "would follow the release.yml run of $TAG until it ends"
    return 0
  fi
  wait_for_run "$MERGE_COMMIT"
  watch_run
}

cmd_watch() { # [version]
  check_gh
  if [ -n "$1" ]; then
    VERSION=$(version_arg "$1")
  else
    check_origin
    fetch_origin
    VERSION=$(version_or_main '')
  fi
  TAG=hermuse/v$VERSION
  find_release_run
  [ -n "$RUN_ID" ] ||
    die "no release.yml run for $TAG: tag it first (tool/release/release.sh tag $VERSION), or run it again: gh workflow run release.yml -R $REPO --ref $TAG -f tag=$TAG"
  log "release run of $TAG: $RUN_URL"
  watch_run
}

main() {
  local args=() top
  while [ $# -gt 0 ]; do
    case $1 in
      -n | --dry-run) DRY_RUN=true ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*) usage_error "unknown option $1" ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  [ ${#args[@]} -gt 0 ] || usage_error "what to release: patch, minor, major, rc, X.Y.Z or X.Y.Z-rc.N"
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "run it inside a checkout of $REPO"
  cd "$top"
  METADATA=$top/tool/release/release-metadata.sh
  [ -x "$METADATA" ] || die "no $METADATA"
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/hermuse-release.XXXXXX")
  trap 'rm -rf "$WORK"' EXIT
  trap on_interrupt INT
  case ${args[0]} in
    tag | watch)
      [ ${#args[@]} -le 2 ] || usage_error "${args[0]} takes one version at most"
      "cmd_${args[0]}" "${args[1]:-}"
      ;;
    *)
      [ ${#args[@]} -eq 1 ] || usage_error "one version or bump at a time"
      cmd_release "${args[0]}"
      ;;
  esac
}

main "$@"
