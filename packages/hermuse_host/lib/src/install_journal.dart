import 'dart:convert';
import 'dart:io';

/// Durable record of the Hermes install Hermuse owns (Linux, macOS).
///
/// Kept as JSON at a caller-chosen path under the app support directory and
/// written before the first installer stage runs. It proves the checkout at
/// [installDir] is the app's (so an interrupted install may continue in it),
/// lists the stages that already succeeded (a resumed run skips them and
/// re-runs [currentStage]), and stays unfinished until the result is
/// validated: bootstrap marker, checkout at [commit] and a launcher that
/// answers `--version`. An unfinished journal wins over a `hermes --version`
/// that already works, so an interrupted install never passes for complete.
final class InstallJournal {
  const InstallJournal({
    required this.hermesHome,
    required this.installDir,
    required this.runtimeHome,
    required this.commit,
    required this.startedAt,
    this.completedStages = const [],
    this.currentStage,
    this.finished = false,
  });

  /// Parses the file content written by [write]. Throws [FormatException]
  /// on another schema or a malformed field.
  factory InstallJournal.fromJson(Map<String, Object?> json) {
    final schema = json['schema_version'];
    if (schema != schemaVersion) {
      throw FormatException('unsupported install journal schema $schema');
    }
    String text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => throw FormatException('install journal misses $key'),
    };
    final startedAt = DateTime.tryParse(text('started_at'));
    if (startedAt == null) {
      throw const FormatException('install journal has a malformed started_at');
    }
    return InstallJournal(
      hermesHome: text('hermes_home'),
      installDir: text('install_dir'),
      runtimeHome: switch (json['runtime_home']) {
        null => null,
        final String home when home.isNotEmpty => home,
        _ => throw const FormatException(
          'install journal has a malformed runtime_home',
        ),
      },
      commit: text('commit'),
      startedAt: startedAt,
      completedStages: switch (json['completed_stages']) {
        final List<Object?> stages when stages.every((s) => s is String) =>
          List.unmodifiable(stages.cast<String>()),
        _ => throw const FormatException(
          'install journal has malformed completed_stages',
        ),
      },
      currentStage: switch (json['current_stage']) {
        null => null,
        final String stage => stage,
        _ => throw const FormatException(
          'install journal has a malformed current_stage',
        ),
      },
      finished: switch (json['finished']) {
        final bool finished => finished,
        _ => throw const FormatException('install journal misses finished'),
      },
    );
  }

  /// Version of the JSON layout.
  static const schemaVersion = 1;

  /// The `HERMES_HOME` of the install.
  final String hermesHome;

  /// The hermes-agent checkout the installer writes (`--dir`).
  final String installDir;

  /// The private `HOME` of the installer stages, or null when they run in
  /// the user's own.
  final String? runtimeHome;

  /// The hermes-agent commit the install pins (`--commit`).
  final String commit;

  /// When this install started.
  final DateTime startedAt;

  /// Stages that reported success, in completion order.
  final List<String> completedStages;

  /// The stage that was running when the journal was last written — it
  /// failed or was interrupted — or null between stages.
  final String? currentStage;

  /// Whether the install was validated and needs nothing more.
  final bool finished;

  /// Whether [stage] succeeded in this or an earlier run.
  bool hasCompleted(String stage) => completedStages.contains(stage);

  /// This journal with [stage] running.
  InstallJournal withStageStarted(String stage) => _copy(currentStage: stage);

  /// This journal with [stage] succeeded and nothing running.
  InstallJournal withStageCompleted(String stage) => _copy(
    completedStages: hasCompleted(stage)
        ? completedStages
        : List.unmodifiable([...completedStages, stage]),
  );

  /// This journal with [stage] to run again: validation traced a defect of
  /// the install back to it.
  InstallJournal withStageReopened(String stage) => _copy(
    completedStages: List.unmodifiable(
      completedStages.where((s) => s != stage),
    ),
    currentStage: stage,
  );

  /// This journal closed after a successful validation.
  InstallJournal asFinished() => _copy(finished: true);

  InstallJournal _copy({
    List<String>? completedStages,
    String? currentStage,
    bool finished = false,
  }) => InstallJournal(
    hermesHome: hermesHome,
    installDir: installDir,
    runtimeHome: runtimeHome,
    commit: commit,
    startedAt: startedAt,
    completedStages: completedStages ?? this.completedStages,
    currentStage: currentStage,
    finished: finished,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'hermes_home': hermesHome,
    'install_dir': installDir,
    'runtime_home': runtimeHome,
    'commit': commit,
    'started_at': startedAt.toUtc().toIso8601String(),
    'completed_stages': completedStages,
    'current_stage': currentStage,
    'finished': finished,
  };

  /// Reads the journal at [path]; null when there is none. Throws
  /// [FormatException] when the file is not a journal this build reads.
  static Future<InstallJournal?> read(String path) async {
    final String content;
    try {
      content = await File(path).readAsString();
    } on PathNotFoundException {
      return null;
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('install journal $path is not a JSON object');
    }
    return InstallJournal.fromJson(decoded);
  }

  /// Replaces the journal at [path] atomically: the JSON goes to a sibling
  /// temporary file, is flushed to disk, then renamed over [path], so a
  /// crash leaves either the previous journal or this one, never a torn
  /// file.
  Future<void> write(String path) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    final temporary = File('$path.tmp');
    final handle = await temporary.open(mode: FileMode.writeOnly);
    try {
      await handle.writeString(
        '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
      );
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temporary.rename(path);
  }
}
