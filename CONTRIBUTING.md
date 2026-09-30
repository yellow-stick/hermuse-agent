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
   of the workflows and release scripts) and builds the Linux, macOS and
   Windows packages and the web app. A pull request that only changes
   documentation builds nothing; each new push cancels the run it supersedes.
   Pull requests from forks run without secrets, so the web preview is only
   deployed for branches of this repository.
4. **Review and merge queue.** The maintainer reviews every pull request (code
   owner). An approved one goes through the merge queue: the merged result is
   packaged again and the installed packages are tested on fresh Ubuntu 22.04
   and Debian 12 machines (`.deb` and AppImage), on newer distributions, on
   macOS and on Windows before `main` moves.
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
- Web: also `jaspr build` in `apps/hermuse_web`;
- Plugin: `pytest tests/ -q` in `hermes-plugin/hermuse`, then
  `plugin_assets_test.dart` after `dart run tool/sync_plugin_assets.dart` in
  `apps/hermuse_app`;
- Contract: regenerate, then `drift_test.dart`.

Generated files are regenerated, never edited by hand. Setup and commands are
in the [README](README.md#development) and [AGENTS.md](AGENTS.md).

## CI at a glance

| When | What runs |
| --- | --- |
| Draft pull request | Nothing |
| Pull request ready for review | Checks, the Linux, macOS and Windows packages, the web build |
| Merge queue | The same, plus the installed-package smoke tests and their report |
| Every night, when `main` changed | Every smoke scenario: Docker variants, adopting an existing Hermes Agent, upgrade and removal |
| Release tag | Every smoke scenario, then the release below |

## Releases

1. The maintainer sets the version in `apps/hermuse_app/pubspec.yaml`, merges
   it and tags that commit `hermuse/vX.Y.Z` (or `hermuse/vX.Y.Z-rc.N`). Only
   administrators can create these tags, and a tag that does not name the
   pubspec version is refused.
2. The tag runs the full matrix: checks, the packages of every platform (the
   macOS and Windows ones signed with the secrets of the `signing`
   environment), every smoke scenario, the assembly and the provenance
   attestation.
3. The one approval: the maintainer approves the `release` environment, whose
   capped model test account, when configured, runs a real conversation.
4. The release goes out as a public **pre-release** with the tested bytes. A
   failed or missing automated result blocks it; what the run could not prove
   (model conversation, signatures, manual gates, checks outside CI) is listed
   under "Not yet proven" in its notes. A published file is never replaced.
5. Once those points are checked, the maintainer makes it the latest release:
   `gh release edit hermuse/vX.Y.Z --prerelease=false --latest`.

To run a release again, dispatch it on its tag:
`gh workflow run release.yml --ref hermuse/vX.Y.Z -f tag=hermuse/vX.Y.Z`.
