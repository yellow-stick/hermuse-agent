/// Layout of a Hermes runtime installed by Hermuse on Linux.
///
/// The staged installer runs with `HOME=<hermesHome>/runtime`, a persistent
/// private home: the command links it writes to `~/.local/bin` (`hermes`,
/// `hermes-agent`, `node`, `npm`, `npx`), the uv-managed Python under
/// `~/.local/share/uv` and the npm/uv caches land there instead of in the
/// user's home, and no shell rc file of the user is edited. `HERMES_HOME`
/// and `<hermesHome>/hermes-agent` stay the standard ones, and the backend
/// itself runs with the real `HOME`. The directory is part of the install,
/// not a cache: the venv's interpreter and the launchers live in it.
final class ManagedRuntime {
  const ManagedRuntime(this.hermesHome);

  /// The `HERMES_HOME` the runtime belongs to.
  final String hermesHome;

  /// The private `HOME` of every installer stage.
  String get home => '$hermesHome/runtime';

  /// The `hermes` launcher the installer's `path` stage writes.
  String get launcher => '$home/.local/bin/hermes';

  /// Directories holding the runtime's tools, in `PATH` order: the command
  /// links (including npm's global bins, whose prefix the installer points
  /// at `~/.local`), the managed Node and the managed uv.
  List<String> get binDirs => [
    '$home/.local/bin',
    '$hermesHome/node/bin',
    '$hermesHome/bin',
  ];

  /// [path] with [binDirs] in front, for the processes that run this
  /// runtime's tools; the user's `PATH` is otherwise left alone.
  String prefixPath(String? path) =>
      [...binDirs, if (path != null && path.isNotEmpty) path].join(':');
}
