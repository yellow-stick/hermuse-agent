/// Release check of the Hermuse apps over the GitHub releases feed.
///
/// The pipeline publishes desktop artifacts under `hermuse/v*` tags and
/// records them in the release's `VERSION.json`; mobile builds, once they
/// exist, follow the same tags. The checker reads that feed, picks the
/// newest release carrying an artifact for the running platform, and compares
/// its version with the running app: no auto-install, the user downloads the
/// newer bytes themselves.
///
/// Pure Dart (native and web); HTTP through an injected client for tests.
library;

export 'src/models.dart';
export 'src/release_feed.dart';
export 'src/version.dart';
