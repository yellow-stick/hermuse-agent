# Contributing to Hermuse Agent

Thanks for helping. Hermuse Agent is open source (AGPL-3.0): anyone can
contribute through a pull request from a fork. The
[Miro board](https://miro.com/app/board/uXjVHgMyu18=/) is the visual overview
of the project and of this flow.

## Questions, bugs and ideas

- Questions and help: [Discussions](https://github.com/yellow-stick/hermuse-agent/discussions).
- Bugs and ideas: [open an issue](https://github.com/yellow-stick/hermuse-agent/issues/new/choose)
  with the bug or idea form.
- Security vulnerabilities: never in public, see [SECURITY.md](SECURITY.md).

## Pull requests

1. **Fork and branch.** Push a branch to your fork and open the pull request
   against `main`. You do not need to create the fork yourself: GitHub makes
   one when you edit a file on github.com, and `gh pr create` offers to from a
   clone.
2. **Draft while you work.** A draft pull request runs no CI.
3. **Ready for review.** Marking it ready runs the checks (analysis, format,
   Dart and Flutter tests, plugin tests against the pinned Hermes Agent, lint
   of the workflows and release scripts), builds the Linux, macOS and Windows
   packages and the web app, then installs and starts the Linux packages in
   Ubuntu 24.04, Ubuntu 26.04 and Debian 13 containers (the compat smoke
   legs). A pull request that only changes documentation builds nothing; each
   new push cancels the run it supersedes. Pull requests from forks run
   without secrets, so the web preview is only deployed for branches of this
   repository.
4. **Review and merge queue.** The maintainer reviews every pull request (code
   owner). An approved one goes through the merge queue: the merged result is
   checked, built and run through the compat legs again before `main` moves,
   unless its pull request run already checked that exact result (a branch up
   to date with `main`): the queue then passes in about a minute. The other
   installed-package smoke tests do not run there: they run for each release
   and in manual test runs ([CI at a glance](#ci-at-a-glance)).
5. **One squashed commit.** Pull requests are squash-merged only: the pull
   request title becomes the single commit on `main` (GitHub appends `(#N)`)
   and its description becomes the commit message.

Maintainers push branches named `yellow-stick/<topic>` (kebab-case, cut from
`origin/main`) to this repository. A ruleset only lets `main`,
`yellow-stick/**`, `release/**`, `dependabot/**` and the merge queue's
`gh-readonly-queue/**` branches be created here; administrators can bypass it.

### Titles, commits and validation

The pull request title follows the commit style `<Area>: <what changed>`
([Commits, branches and PRs](AGENTS.md#commits-branches-and-prs)), since it
becomes the commit on `main`. The commits on your branch are free-form. A pull
request too big for one commit is split into several. The description says
what changes for the user or the developer, then the validation that actually
ran ([Validation per area](AGENTS.md#validation-per-area)):

- Dart/Flutter: `melos run analyze` and the package's tests
  (`melos run test:dart`, `melos run test:flutter`);
- Web: also `jaspr build` in `apps/hermuse_web`, and `demo/build.sh` when the
  chat shell, the app scope or `demo/` changes;
- Plugin: `pytest tests/ -q` in `hermes-plugin/hermuse`, then
  `plugin_assets_test.dart` after `dart run tool/sync_plugin_assets.dart` in
  `apps/hermuse_app`;
- Contract: regenerate, then `drift_test.dart`.

Generated files are regenerated, never edited by hand. Setup and commands are
in the [README](README.md#development) and [AGENTS.md](AGENTS.md).

### Orca worktree archiving

Orca runs `tool/orca/archive-worktree.sh` from the repository's main checkout
(`ORCA_ROOT_PATH`), including when removing an older worktree. On Linux the hook
stops processes whose working directory or executable is inside the target
worktree, escalating from SIGTERM to SIGKILL. It runs its own process sweep from
`/` so its temporary helpers cannot be mistaken for worktree processes.
Zombies are ignored; genuinely surviving processes still block removal.

Run the isolated process regression tests with
`python3 -B -m unittest discover -s tool/orca -p 'test_*.py' -v`.
To use an updated hook for existing worktrees, update the copy in the main
checkout; changing only the worktree's copy does not change the archive command.

## CI at a glance

One workflow per scenario, in `.github/workflows/`:

| When | Workflow | What runs |
| --- | --- | --- |
| Draft pull request | `ci.yml`, `web-pr.yml` | Nothing |
| Pull request ready for review | `ci.yml`, `web-pr.yml` | Checks, the Linux, macOS and Windows packages, the compat smoke legs (the `.deb` and AppImage installed and started in Ubuntu 24.04, Ubuntu 26.04 and Debian 13 containers), the web app and demo builds, and a demo preview |
| Merge queue | `ci.yml`, `web-queue.yml` | The same checks, builds and compat legs, without preview; nothing when a passing run already checked the same tree (`tool/ci/tree-passed.sh`) |
| Push to `main` touching the web app or the demo | `web-deploy.yml` | The read-only demo deployed to https://demo.hermuse.app |
| Release tag | `release.yml` | Every smoke scenario on the signed packages, then the release below, then the published-release check |
| Manual test run | `smoke.yml` | Unsigned packages of a branch, then every smoke scenario or those selected |

`build.yml` (checks and packages), `smoke-legs.yml` (smoke scenarios) and
`web-build.yml` are the steps these workflows share; `published-release.yml`
is the published-release check of `release.yml`. The required checks of
`main` are `CI` and `Web`: the last job of their workflows, which passes only
when every job before it succeeded or was skipped (a draft, a change that does
not concern it).

The installed-package smoke tests run on fresh Ubuntu 22.04 and Debian 12
machines (`.deb` and AppImage: first launch, Docker variants, adopting an
existing Hermes Agent, upgrade and removal), on newer distributions, on macOS
and on Windows. Only the compat legs, on the newer distributions in
containers, also run with every build of a pull request and of the merge
queue; all of them run for each release. The maintainer runs them on a branch
with `gh workflow run smoke.yml --ref <branch>`, all of them or, with
`-f legs=<regex>`, those whose name matches (the names are listed in
`packaging/smoke/proof_summary.py`); such a run never signs nor publishes.

## Releases

The maintainer cuts a release with `tool/release/release.sh`, from a clean
checkout at `origin/main`, with `gh` logged in as an administrator: only
administrators can create `hermuse/v*` tags, so no workflow can.

```bash
tool/release/release.sh --dry-run patch   # what it would do; nothing is pushed or created
tool/release/release.sh patch             # or minor, major, rc, X.Y.Z, X.Y.Z-rc.N
```

1. **Release pull request.** The script bumps the version of
   `apps/hermuse_app/pubspec.yaml` on `origin/main` (the build number goes up
   by one) and, for a final version, updates the download names in the README
   and the desktop guide. It opens `Release: Hermuse Agent X.Y.Z` from
   `yellow-stick/release-X.Y.Z`, with the commits since the previous tag,
   turns auto-merge on and waits for the merge queue; a failed check stops it.
2. **Tag.** It tags the squash commit of that pull request `hermuse/vX.Y.Z`
   and pushes the tag. A tag that does not name the pubspec version is
   refused.
3. **Release run.** The tag runs the full matrix: checks, the packages of
   every platform (the macOS and Windows ones signed with the secrets of the
   `signing` environment), every smoke scenario, the assembly and the
   provenance attestation. The script follows the run and prints the failed
   jobs with the end of their log.
4. **The one approval.** The maintainer approves the `release` environment
   (the script prints where), whose capped model test account, when
   configured, runs a real conversation.
5. **Public pre-release.** The release goes out as a public **pre-release**
   with the tested bytes. A failed or missing automated result blocks it; what
   the run could not prove (model conversation, signatures, manual gates,
   checks outside CI) is listed under "Not yet proven" in its notes. A
   published file is never replaced.
6. **Published-release check.** The run then downloads the published files by
   their public URL, as a user would, checks them against `SHA256SUMS.txt`,
   and installs and starts them on clean Linux, macOS and Windows runners. A
   failure there fails the run but cannot unpublish anything: the fix goes
   into the next release (fix forward). The script exits once the run
   succeeded, with the release URL.
7. **Promotion.** Once the points under "Not yet proven" are checked, the
   maintainer makes it the latest release:
   `gh release edit hermuse/vX.Y.Z --prerelease=false --latest`.

Release candidates take the same path: `tool/release/release.sh rc` cuts
`hermuse/vX.Y.Z-rc.N`, after a final version the first release candidate of
the next patch, after a release candidate the next one (`X.Y.Z-rc.1` gives
the first one of a minor or a major). A release candidate stays a pre-release
and leaves the download names of the docs on the last final release;
`tool/release/release.sh patch` then releases its final version.

An interrupted script resumes where it stopped:
`tool/release/release.sh tag [X.Y.Z]` waits for the release pull request if it
is still open, then tags it; `tool/release/release.sh watch [X.Y.Z]` follows
the release run. To run a release again, dispatch it on its tag:
`gh workflow run release.yml --ref hermuse/vX.Y.Z -f tag=hermuse/vX.Y.Z`.
