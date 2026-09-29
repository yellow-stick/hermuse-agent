// Private fields with public constructor params need explicit initializers.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'errors.dart';
import 'host_environment.dart';

/// SHA-256 (lowercase hex) of `packaging/linux/hermuse-linux-setup`,
/// compiled into release builds with
/// `--dart-define=HERMUSE_LINUX_HELPER_SHA256=<hex>`. Empty in development
/// builds, which can only use [LinuxSetupHelper.fromWorkspace].
const linuxHelperSha256 = String.fromEnvironment('HERMUSE_LINUX_HELPER_SHA256');

/// Largest helper the privileged verifier accepts, in bytes.
const linuxHelperMaxBytes = 256 * 1024;

/// The constant script `pkexec /usr/bin/sh -c` runs as root, with
/// `hermuse-verify <sha256> <helper path> apply <category>...` as arguments.
///
/// It copies the helper ONCE (at most [linuxHelperMaxBytes]) into a fresh
/// root-only directory under `/run`, hashes that copy, runs that same copy
/// only when the hash matches, and deletes the directory when it exits; the
/// source path is never reopened after the copy, so swapping the file after
/// the consent changes nothing. Hangup, interrupt and termination signals are
/// ignored so a closing app never cuts an APT transaction.
///
/// Exit statuses of its own: 90 bad arguments, 91 no private directory,
/// 92 helper missing, unreadable or too large, 93 digest mismatch. Otherwise
/// the helper's status.
const linuxPrivilegeVerifier = r'''set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077
cd / || exit 90
trap '' HUP INT QUIT TERM
[ "$#" -ge 4 ] || exit 90
expected=$1
source=$2
shift 2
[ "$1" = apply ] || exit 90
case $expected in
  *[!0-9a-f]*) exit 90 ;;
esac
[ "${#expected}" -eq 64 ] || exit 90
case $source in
  /*) ;;
  *) exit 90 ;;
esac
dir=$(mktemp -d /run/hermuse-verify.XXXXXXXXXX) || exit 91
trap 'rm -rf -- "$dir"' EXIT
copy=$dir/hermuse-linux-setup
[ -f "$source" ] || exit 92
head -c 262145 -- "$source" > "$copy" || exit 92
size=$(wc -c < "$copy") || exit 92
[ "$size" -le 262144 ] || exit 92
actual=$(sha256sum < "$copy") || exit 92
[ "${actual%% *}" = "$expected" ] || exit 93
/usr/bin/sh "$copy" "$@"
''';

/// The setup helper this app runs, and the digest the privileged verifier
/// requires of it.
final class LinuxSetupHelper {
  const LinuxSetupHelper._(this.path, this.sha256, {required this.development});

  /// The helper shipped in the bundle, `<exe-dir>/libexec/hermuse-linux-setup`,
  /// bound to the digest compiled into the app ([linuxHelperSha256], or
  /// [compiledSha256] in tests).
  ///
  /// Throws [LinuxSetupUnavailable] when no valid digest was compiled in: such
  /// a build never elevates.
  factory LinuxSetupHelper.bundled({
    String? executableDir,
    String compiledSha256 = linuxHelperSha256,
  }) {
    if (!_isSha256(compiledSha256)) {
      throw const LinuxSetupUnavailable(
        'this build has no setup-helper digest '
        '(HERMUSE_LINUX_HELPER_SHA256), so it cannot prepare the system',
      );
    }
    final dir = executableDir ?? File(Platform.resolvedExecutable).parent.path;
    return LinuxSetupHelper._(
      File('$dir/libexec/hermuse-linux-setup').absolute.path,
      compiledSha256,
      development: false,
    );
  }

  /// Development only: the workspace's `packaging/linux/hermuse-linux-setup`,
  /// trusted as it is when this runs — its digest is computed now, so an edit
  /// after this call is refused by the verifier.
  ///
  /// Explicit opt-in for `flutter run` from a checkout at [workspaceRoot].
  /// Throws [LinuxSetupUnavailable] in product (release) builds and in any
  /// build that carries a compiled digest: those use [LinuxSetupHelper.bundled].
  static Future<LinuxSetupHelper> fromWorkspace(
    String workspaceRoot, {
    String compiledSha256 = linuxHelperSha256,
  }) async {
    if (const bool.fromEnvironment('dart.vm.product') ||
        compiledSha256.isNotEmpty) {
      throw const LinuxSetupUnavailable(
        'the workspace setup helper is for development builds only',
      );
    }
    final file = File('$workspaceRoot/packaging/linux/hermuse-linux-setup')
        .absolute;
    final path = file.path;
    if (!await file.exists()) {
      throw LinuxSetupUnavailable('setup helper not found: $path');
    }
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return LinuxSetupHelper._(path, '$digest', development: true);
  }

  /// Absolute path of the helper script.
  final String path;

  /// Lowercase hex SHA-256 the verifier requires of the copy it runs.
  final String sha256;

  /// Whether the digest was computed from the workspace file at runtime.
  final bool development;

  static bool _isSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

/// Privileged categories of `hermuse-linux-setup apply`, in the fixed order
/// the helper applies them.
enum LinuxHelperCategory {
  /// Build tools the Hermes Agent installer needs (APT).
  hermesTools('hermes-tools'),

  /// GNOME Keyring and libsecret when no Secret Service provider exists.
  secretService('secret-service'),

  /// The distribution's `docker.io`, only when no Docker exists.
  dockerInstall('docker-install'),

  /// `systemctl enable --now` of an installed, stopped system engine.
  dockerStart('docker-start'),

  /// `usermod -aG docker` for the calling user.
  dockerGroup('docker-group');

  const LinuxHelperCategory(this.wire);

  /// The helper argument and JSON value.
  final String wire;

  /// The category for a JSON value, or null.
  static LinuxHelperCategory? fromWire(Object? wire) {
    for (final category in values) {
      if (category.wire == wire) return category;
    }
    return null;
  }
}

/// Result codes of the helper's last line, with the exit status each one
/// implies.
enum LinuxHelperCode {
  ok('ok', 0),
  usage('usage', 2),
  callerInvalid('caller-invalid', 3),
  notRoot('not-root', 3),
  unsupportedOs('unsupported-os', 4),
  aptFailed('apt-failed', 5),
  dockerStartFailed('docker-start-failed', 5),
  usermodFailed('usermod-failed', 5),
  dockerPresent('docker-present', 6),
  dockerUnitMissing('docker-unit-missing', 6),
  dockerGroupMissing('docker-group-missing', 6),
  internal('internal', 70);

  const LinuxHelperCode(this.wire, this.exitCode);

  /// The JSON value.
  final String wire;

  /// The exit status the helper uses with this code.
  final int exitCode;

  /// The code for a JSON value, or null.
  static LinuxHelperCode? fromWire(Object? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// Kinds of the helper's JSON event lines.
enum LinuxHelperEventKind {
  /// `plan`/`apply`: the operating-system verdict (`code`, `base`).
  os('os'),

  /// `plan`: a package `apply` would install (`category`, `package`).
  missing('missing'),

  /// `plan`, or before a `docker-present` refusal: a trace of an existing
  /// Docker (`code`).
  dockerFootprint('docker-footprint'),

  /// `plan`: whether a D-Bus activation file for `org.freedesktop.secrets`
  /// is installed (`code` `present`/`absent`).
  secretProvider('secret-provider'),

  /// `apply`: a category starts (`category`).
  begin('begin'),

  /// `apply`: a package about to be installed (`category`, `package`).
  install('install'),

  /// `apply`: `apt-get update` finished (`code` `ok`/`failed`).
  aptUpdate('apt-update'),

  /// `apply`: GNOME Keyring left out next to another provider (`category`,
  /// `code` `provider-present`).
  note('note'),

  /// `apply`: nothing to change (`category`, `code` `satisfied`,
  /// `already-active` or `already-member`).
  skip('skip'),

  /// `apply`: a category was applied (`category`).
  done('done'),

  /// `apply`: a category failed (`category`, `code` = a [LinuxHelperCode]).
  fail('fail');

  const LinuxHelperEventKind(this.wire);

  /// The JSON value of `event`.
  final String wire;
}

/// One JSON event line of the helper.
final class LinuxHelperEvent {
  const LinuxHelperEvent(
    this.kind, {
    this.category,
    this.code,
    this.package,
    this.base,
  });

  final LinuxHelperEventKind kind;
  final LinuxHelperCategory? category;

  /// The fixed code of `os`, `docker-footprint`, `secret-provider`,
  /// `apt-update`, `note`, `skip` and `fail` events.
  final String? code;

  /// Debian package name of `missing` and `install` events.
  final String? package;

  /// Base release codename of a supported `os` event (`noble`, `trixie`…).
  final String? base;
}

/// The helper's last line: `{"result":{"ok","code","applied","exit"}}`.
final class LinuxHelperResult {
  const LinuxHelperResult({
    required this.code,
    required this.applied,
    required this.exitCode,
  });

  final LinuxHelperCode code;

  /// Requested categories whose state holds after the run, in fixed order.
  final List<LinuxHelperCategory> applied;
  final int exitCode;

  bool get ok => code == LinuxHelperCode.ok;
}

/// A complete, protocol-valid helper stdout.
final class LinuxHelperOutput {
  const LinuxHelperOutput(this.events, this.result);
  final List<LinuxHelperEvent> events;
  final LinuxHelperResult result;
}

const _eventCodes = <LinuxHelperEventKind, Set<String>>{
  LinuxHelperEventKind.os: {
    'supported',
    'unsupported-distribution',
    'unsupported-release',
    'unsupported-architecture',
    'os-release-unreadable',
  },
  LinuxHelperEventKind.dockerFootprint: {
    'package',
    'binary',
    'socket',
    'unit',
    'data',
    'config',
    'snap',
    'rootless',
  },
  LinuxHelperEventKind.secretProvider: {'present', 'absent'},
  LinuxHelperEventKind.aptUpdate: {'ok', 'failed'},
  LinuxHelperEventKind.note: {'provider-present'},
  LinuxHelperEventKind.skip: {'satisfied', 'already-active', 'already-member'},
};

const _eventKeys = <LinuxHelperEventKind, Set<String>>{
  LinuxHelperEventKind.os: {'code'},
  LinuxHelperEventKind.missing: {'category', 'package'},
  LinuxHelperEventKind.dockerFootprint: {'code'},
  LinuxHelperEventKind.secretProvider: {'code'},
  LinuxHelperEventKind.begin: {'category'},
  LinuxHelperEventKind.install: {'category', 'package'},
  LinuxHelperEventKind.aptUpdate: {'code'},
  LinuxHelperEventKind.note: {'category', 'code'},
  LinuxHelperEventKind.skip: {'category', 'code'},
  LinuxHelperEventKind.done: {'category'},
  LinuxHelperEventKind.fail: {'category', 'code'},
};

final _packageName = RegExp(r'^[a-z0-9][a-z0-9.+-]*$');
final _codename = RegExp(r'^[a-z]+$');

/// Parses one helper event line; throws [FormatException] for anything
/// outside the protocol (unknown event, key, category, code or value).
LinuxHelperEvent parseLinuxHelperEvent(Map<String, Object?> json) {
  final name = json['event'];
  final kind = LinuxHelperEventKind.values
      .where((k) => k.wire == name)
      .firstOrNull;
  if (kind == null) throw FormatException('unknown helper event: $name');
  final keys = json.keys.toSet()..remove('event');
  final required = _eventKeys[kind]!;
  final allowed = kind == LinuxHelperEventKind.os
      ? {...required, 'base'}
      : required;
  if (!keys.containsAll(required) || !allowed.containsAll(keys)) {
    throw FormatException('malformed helper event: ${jsonEncode(json)}');
  }
  for (final key in keys) {
    if (json[key] is! String) {
      throw FormatException('malformed helper event: ${jsonEncode(json)}');
    }
  }
  final code = json['code'] as String?;
  final codes = _eventCodes[kind];
  if (codes != null && !codes.contains(code)) {
    throw FormatException('unknown $name code: $code');
  }
  if (kind == LinuxHelperEventKind.fail) {
    final failure = LinuxHelperCode.fromWire(code);
    if (failure == null || failure == LinuxHelperCode.ok) {
      throw FormatException('unknown failure code: $code');
    }
  }
  LinuxHelperCategory? category;
  if (keys.contains('category')) {
    category = LinuxHelperCategory.fromWire(json['category']);
    if (category == null) {
      throw FormatException('unknown helper category: ${json['category']}');
    }
  }
  final package = json['package'] as String?;
  if (package != null && !_packageName.hasMatch(package)) {
    throw FormatException('invalid package name: $package');
  }
  final base = json['base'] as String?;
  if (kind == LinuxHelperEventKind.os &&
      ((code == 'supported') != (base != null) ||
          (base != null && !_codename.hasMatch(base)))) {
    throw FormatException('malformed os event: ${jsonEncode(json)}');
  }
  return LinuxHelperEvent(
    kind,
    category: category,
    code: code,
    package: package,
    base: base,
  );
}

/// Parses the helper's final `{"result":…}` line and checks it against the
/// process [exitCode]; throws [FormatException] when they disagree.
LinuxHelperResult parseLinuxHelperResult(
  Map<String, Object?> json,
  int exitCode,
) {
  final result = json['result'];
  if (json.length != 1 ||
      result is! Map<String, Object?> ||
      result.length != 4) {
    throw FormatException('malformed helper result: ${jsonEncode(json)}');
  }
  final code = LinuxHelperCode.fromWire(result['code']);
  final ok = result['ok'];
  final exit = result['exit'];
  final applied = result['applied'];
  if (code == null || ok is! bool || exit is! int || applied is! List) {
    throw FormatException('malformed helper result: ${jsonEncode(json)}');
  }
  if (exit != code.exitCode || exit != exitCode || ok != (exit == 0)) {
    throw FormatException(
      'helper result ${jsonEncode(json)} does not match exit status $exitCode',
    );
  }
  final categories = <LinuxHelperCategory>[];
  for (final wire in applied) {
    final category = LinuxHelperCategory.fromWire(wire);
    if (category == null ||
        (categories.isNotEmpty && categories.last.index >= category.index)) {
      throw FormatException('malformed applied list: ${jsonEncode(applied)}');
    }
    categories.add(category);
  }
  return LinuxHelperResult(code: code, applied: categories, exitCode: exitCode);
}

/// Parses a whole helper stdout: event lines, then exactly one result line
/// last. Throws [FormatException] on any other shape.
LinuxHelperOutput parseLinuxHelperOutput(List<String> lines, int exitCode) {
  if (lines.isEmpty) throw const FormatException('no helper result');
  final events = <LinuxHelperEvent>[];
  for (final (index, line) in lines.indexed) {
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      throw FormatException('non-JSON helper output: $line');
    }
    if (json is! Map<String, Object?>) {
      throw FormatException('non-object helper output: $line');
    }
    if (index == lines.length - 1) {
      return LinuxHelperOutput(events, parseLinuxHelperResult(json, exitCode));
    }
    events.add(parseLinuxHelperEvent(json));
  }
  throw StateError('unreachable');
}

/// Why the verifier refused to run the helper.
enum LinuxVerifierFailure {
  /// Exit 90: arguments the constant script does not accept.
  arguments,

  /// Exit 91: no private directory under `/run`.
  privateDirectory,

  /// Exit 92: helper missing, unreadable or larger than
  /// [linuxHelperMaxBytes].
  copy,

  /// Exit 93: the helper is not the one this app was built with.
  digest,
}

/// How one privileged helper run ended.
sealed class LinuxHelperOutcome {
  const LinuxHelperOutcome();
}

/// The helper ran and ended with a protocol-valid result (successful or
/// not).
final class LinuxHelperFinished extends LinuxHelperOutcome {
  const LinuxHelperFinished(this.result, this.events);
  final LinuxHelperResult result;
  final List<LinuxHelperEvent> events;
}

/// The authentication dialog was dismissed (pkexec exit 126): nothing ran.
final class LinuxHelperDismissed extends LinuxHelperOutcome {
  const LinuxHelperDismissed();
}

/// Authorization was refused or impossible — wrong password, policy, no
/// authentication agent in this session (pkexec exit 127): nothing ran.
final class LinuxHelperDenied extends LinuxHelperOutcome {
  const LinuxHelperDenied(this.detail);

  /// pkexec's last stderr line, possibly empty.
  final String detail;
}

/// The verifier refused the helper before running it.
final class LinuxHelperRejected extends LinuxHelperOutcome {
  const LinuxHelperRejected(this.reason);
  final LinuxVerifierFailure reason;
}

/// pkexec could not start, or the run broke the protocol (missing or
/// inconsistent result, stray output): its effect is unknown.
final class LinuxHelperFailed extends LinuxHelperOutcome {
  const LinuxHelperFailed(this.reason, {this.exitCode});
  final String reason;
  final int? exitCode;
}

/// Environment variables pkexec receives; everything else (LD_*, GTK_*,
/// GCONV_PATH, PYTHON*, DOCKER*, AppImage variables…) is dropped.
const _privilegedPassThrough = [
  'DISPLAY',
  'WAYLAND_DISPLAY',
  'XAUTHORITY',
  'DBUS_SESSION_BUS_ADDRESS',
  'XDG_RUNTIME_DIR',
  'LANG',
];

/// Fixed PATH of every privileged process.
const _systemPath = '/usr/sbin:/usr/bin:/sbin:/bin';

/// Runs `hermuse-linux-setup apply` as root through ONE pkexec invocation
/// per consent, via [linuxPrivilegeVerifier].
///
/// pkexec gets a minimal environment ([_privilegedPassThrough] + a fixed
/// PATH, no parent environment) and `--disable-internal-agent`, so the
/// password is only ever typed into the desktop's own authentication dialog —
/// never read by this app. A started run is never killed: an APT
/// transaction always completes.
final class LinuxPrivilegeRunner {
  LinuxPrivilegeRunner({
    required LinuxSetupHelper helper,
    Map<String, String>? environment,
    Future<Process> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
    )?
    startProcess,
  }) : _helper = helper,
       _environment = environment ?? hostEnvironment(),
       _start = startProcess ?? _startDefault;

  /// The only elevation mechanism.
  static const pkexec = '/usr/bin/pkexec';

  /// The shell pkexec runs [linuxPrivilegeVerifier] with.
  static const shell = '/usr/bin/sh';

  final LinuxSetupHelper _helper;
  final Map<String, String> _environment;
  final Future<Process> Function(String, List<String>, Map<String, String>)
  _start;

  /// Applies [categories] (at least one; duplicates ignored, fixed order)
  /// under a single authorization. [onEvent] and [onLog] receive helper
  /// events and stderr lines while it runs.
  Future<LinuxHelperOutcome> apply(
    Iterable<LinuxHelperCategory> categories, {
    void Function(LinuxHelperEvent event)? onEvent,
    void Function(String line)? onLog,
  }) async {
    final ordered = categories.toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (ordered.isEmpty) {
      throw ArgumentError.value(categories, 'categories', 'is empty');
    }
    final Process process;
    try {
      process = await _start(pkexec, [
        '--disable-internal-agent',
        shell,
        '-c',
        linuxPrivilegeVerifier,
        'hermuse-verify',
        _helper.sha256,
        _helper.path,
        'apply',
        for (final category in ordered) category.wire,
      ], _privilegedEnvironment());
    } on ProcessException catch (e) {
      return LinuxHelperFailed('cannot start $pkexec: ${e.message}');
    }
    unawaited(process.stdin.close().catchError((Object _) {}));

    final lines = <String>[];
    String? violation;
    var lastError = '';
    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          lines.add(line);
          if (violation != null) return;
          try {
            final json = jsonDecode(line);
            if (json is! Map<String, Object?>) {
              violation = 'non-object helper output: $line';
            } else if (!json.containsKey('result')) {
              onEvent?.call(parseLinuxHelperEvent(json));
            }
          } on FormatException catch (e) {
            violation = e.message;
          }
        });
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isNotEmpty) lastError = line.trim();
          onLog?.call(line);
        });
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    if (lines.isEmpty) {
      return switch (exitCode) {
        126 => const LinuxHelperDismissed(),
        127 => LinuxHelperDenied(lastError),
        90 => const LinuxHelperRejected(LinuxVerifierFailure.arguments),
        91 => const LinuxHelperRejected(LinuxVerifierFailure.privateDirectory),
        92 => const LinuxHelperRejected(LinuxVerifierFailure.copy),
        93 => const LinuxHelperRejected(LinuxVerifierFailure.digest),
        _ => LinuxHelperFailed(
          'the setup helper printed no result (exit $exitCode)',
          exitCode: exitCode,
        ),
      };
    }
    if (violation case final reason?) {
      return LinuxHelperFailed(reason, exitCode: exitCode);
    }
    final LinuxHelperOutput output;
    try {
      output = parseLinuxHelperOutput(lines, exitCode);
    } on FormatException catch (e) {
      return LinuxHelperFailed(e.message, exitCode: exitCode);
    }
    final applied = output.result.applied;
    final consistent = output.result.ok
        ? _sameCategories(applied, ordered)
        : applied.every(ordered.contains);
    if (!consistent) {
      return LinuxHelperFailed(
        'the setup helper reported categories it was not asked for',
        exitCode: exitCode,
      );
    }
    return LinuxHelperFinished(output.result, output.events);
  }

  Map<String, String> _privilegedEnvironment() => {
    'PATH': _systemPath,
    for (final name in _privilegedPassThrough)
      if (_environment[name] case final value? when value.isNotEmpty)
        name: value,
  };

  static bool _sameCategories(
    List<LinuxHelperCategory> a,
    List<LinuxHelperCategory> b,
  ) => a.length == b.length && a.indexed.every((e) => b[e.$1] == e.$2);

  static Future<Process> _startDefault(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) => Process.start(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: false,
  );
}
