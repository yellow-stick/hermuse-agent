import 'dart:io';

/// Variables the AppImage `AppRun` rewrites to load the bundled GTK runtime.
///
/// Before touching anything, `AppRun` exports `HERMUSE_APPIMAGE_ENV_SAVED=1`
/// and, for each name set in the original environment,
/// `HERMUSE_ORIG_<NAME>=<original value>` (a name unset originally gets no
/// `HERMUSE_ORIG_` variable). This list and the one in `AppRun` must stay
/// identical: a variable rewritten by `AppRun` but missing here would leak
/// the bundle runtime into every child process.
const appImageSavedVariables = [
  'LD_LIBRARY_PATH',
  'GTK_DATA_PREFIX',
  'GTK_THEME',
  'GDK_BACKEND',
  'XDG_DATA_DIRS',
  'GTK_EXE_PREFIX',
  'GTK_PATH',
  'GTK_IM_MODULE_FILE',
  'GDK_PIXBUF_MODULE_FILE',
  'GIO_MODULE_DIR',
  'GSETTINGS_SCHEMA_DIR',
  'GI_TYPELIB_PATH',
  'PATH',
];

/// Set by `AppRun` once the originals of [appImageSavedVariables] are saved.
const _savedMarker = 'HERMUSE_APPIMAGE_ENV_SAVED';

/// Prefix of the saved originals.
const _originalPrefix = 'HERMUSE_ORIG_';

/// Variables the AppImage runtime (uruntime) and `AppRun` add, meaningless
/// to a host process.
const _appImageOnly = {
  'APPDIR',
  'APPIMAGE',
  'APPOFFSET',
  'ARGV0',
  'OWD',
  'URUNTIME',
  'URUNTIME_DIR',
};

/// The environment of the user's session, for spawning a host process.
///
/// Every non-privileged child (Hermes, its installer and plugin CLI,
/// CLIProxyAPI, `xdg-open`, …) runs with `includeParentEnvironment: false`
/// and `{...hostEnvironment(), ...specific}`, so the libraries and GTK
/// settings of an AppImage never reach Python, Node, Git or the browser.
///
/// [environment] defaults to [Platform.environment]. Without
/// `HERMUSE_APPIMAGE_ENV_SAVED` (`.deb`, development) it is returned as is —
/// possibly unmodifiable, so copy it before mutating. Inside the AppImage
/// the result is a new map where every [appImageSavedVariables] name holds
/// its `HERMUSE_ORIG_` value or is removed when it had none, and the
/// `HERMUSE_ORIG_*` bookkeeping, `HERMUSE_APPIMAGE_ENV_SAVED` and the
/// runtime's own variables (`APPDIR`, `APPIMAGE`, `APPOFFSET`, `ARGV0`,
/// `OWD`, `URUNTIME`, `URUNTIME_DIR`) are gone.
///
/// On macOS the app's own environment gets the `PATH` directories of a
/// login shell ([withSystemPath] of [macOSSystemPaths]): opened from the
/// Finder or the Dock, the app inherits launchd's
/// `/usr/bin:/bin:/usr/sbin:/sbin` only, without `/usr/local/bin` where
/// Docker Desktop installs `docker`.
Map<String, String> hostEnvironment([Map<String, String>? environment]) {
  final current = environment ?? Platform.environment;
  if (environment == null && Platform.isMacOS) {
    return withSystemPath(current, _macOSSystemPaths ??= macOSSystemPaths());
  }
  if (!current.containsKey(_savedMarker)) return current;
  final host = <String, String>{
    for (final MapEntry(:key, :value) in current.entries)
      if (key != _savedMarker &&
          !key.startsWith(_originalPrefix) &&
          !_appImageOnly.contains(key))
        key: value,
  };
  for (final name in appImageSavedVariables) {
    final original = current['$_originalPrefix$name'];
    if (original == null) {
      host.remove(name);
    } else {
      host[name] = original;
    }
  }
  return host;
}

List<String>? _macOSSystemPaths;

/// The directories `path_helper` puts on a macOS login shell's `PATH`: the
/// lines of `<etc>/paths`, then those of each file in `<etc>/paths.d` in
/// name order. Unreadable files add nothing.
List<String> macOSSystemPaths({String etc = '/etc'}) {
  List<String> lines(File file) {
    try {
      return [
        for (final line in file.readAsLinesSync())
          if (line.trim() case final dir when dir.startsWith('/')) dir,
      ];
    } on FileSystemException {
      return const [];
    }
  }

  final List<File> extra;
  try {
    extra = Directory('$etc/paths.d').listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  } on FileSystemException {
    return lines(File('$etc/paths'));
  }
  return [
    ...lines(File('$etc/paths')),
    for (final file in extra) ...lines(file),
  ];
}

/// [environment] with the [systemPaths] its `PATH` lacks appended, in
/// order: the session's own `PATH` is kept as is, ahead of them.
Map<String, String> withSystemPath(
  Map<String, String> environment,
  List<String> systemPaths,
) {
  final path = environment['PATH'] ?? '';
  final entries = path.split(':');
  final missing = {
    for (final dir in systemPaths)
      if (!entries.contains(dir)) dir,
  };
  if (missing.isEmpty) return environment;
  return {
    ...environment,
    'PATH': [if (path.isNotEmpty) path, ...missing].join(':'),
  };
}
