<!--
Open the pull request as a draft while you work: drafts run no CI. Mark it
ready for review to run the checks and the builds (CONTRIBUTING.md).
-->

## What changes

<!-- For the user or the developer: what the product or the repository does now. -->

## Validation

<!--
The checks that actually ran, and their result (AGENTS.md, "Validation per area"):
- Dart/Flutter: `melos run analyze` and the package's tests (`melos run test:dart` / `melos run test:flutter`)
- Web: `jaspr build` in apps/hermuse_web, on top of analyze and tests
- Plugin: `pytest tests/ -q` in hermes-plugin/hermuse, then `plugin_assets_test.dart` after re-syncing the assets
- Contract: regenerate, then `drift_test.dart`
Do not list a check that did not run; say what failed.
-->

## Checklist

- [ ] Commit subjects follow `<Area>: <what changed>`, one logical change per commit ([AGENTS.md](https://github.com/yellow-stick/hermuse-agent/blob/main/AGENTS.md#commits-branches-and-prs))
- [ ] Generated files are regenerated, never edited by hand (`contract.g.dart`)
- [ ] After a change in `hermes-plugin/hermuse`: plugin assets synced with `dart run tool/sync_plugin_assets.dart` in `apps/hermuse_app`
