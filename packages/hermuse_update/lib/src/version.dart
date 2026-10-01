/// Release tag versions: `hermuse/vX.Y.Z` or `hermuse/vX.Y.Z-rc.N`.
///
/// Comparison is numeric per segment: `0.2.0` beats `0.10.0` lexicographically
/// but loses here; a final beats its release candidates (`-rc.N` sorts below
/// the same `X.Y.Z`). Build metadata (`+B` from the app pubspec) never decides.
library;

/// An app version parsed from a release tag or the app pubspec.
final class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.major, this.minor, this.patch, this.rc);

  /// Parses `hermuse/vX.Y.Z[-rc.N]` or a bare `X.Y.Z[-rc.N][+B]`; null when
  /// the text is not one of those.
  static AppVersion? parse(String raw) {
    var text = raw.trim();
    const prefix = 'hermuse/v';
    if (text.startsWith(prefix)) text = text.substring(prefix.length);
    final plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    return AppVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4) == null ? null : int.parse(match.group(4)!),
    );
  }

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-rc\.(\d+))?$');

  final int major;
  final int minor;
  final int patch;

  /// Release candidate number; null for a final release.
  final int? rc;

  /// True for a final release (strictly newer than its own `-rc.N`).
  bool get isFinal => rc == null;

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (pair.$1 != pair.$2) return pair.$1.compareTo(pair.$2);
    }
    return switch ((rc, other.rc)) {
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
      (final int a, final int b) => a.compareTo(b),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      rc == other.rc;

  @override
  int get hashCode => Object.hash(major, minor, patch, rc);

  @override
  String toString() => '$major.$minor.$patch${rc == null ? '' : '-rc.$rc'}';
}
