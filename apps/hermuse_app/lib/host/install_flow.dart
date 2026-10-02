import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/local_host.dart';
import 'setup_view.dart';

/// Desktop install flow: detect → (supervise | staged install) → onboard.
///
/// [detected] is the [HermesDetector.detect] outcome computed by the caller
/// (so Welcome can decide). When non-null the flow just supervises the
/// existing install via [host] and hands the registered local instance back.
/// Otherwise it runs the staged installer: prerequisites → manifest →
/// stages with their output log → retry-this-stage on failure → supervise.
/// Both show as the setup checklist: the developer tools, then Hermes
/// Agent.
final class InstallFlowScreen extends ConsumerStatefulWidget {
  const InstallFlowScreen({
    required this.host,
    required this.detected,
    required this.onDone,
    required this.onCancel,
    this.installer,
    super.key,
  });

  final LocalHermesHost host;
  final DetectedHermes? detected;

  /// Fired with the registered local instance once supervised.
  final ValueChanged<HermesInstance> onDone;
  final VoidCallback onCancel;

  /// Injected installer (tests); production builds one from [host.hermesHome].
  final HermesInstaller? installer;

  @override
  ConsumerState<InstallFlowScreen> createState() => _InstallFlowScreenState();
}

enum _Phase { working, stages, failed, supervising }

/// What the flow does while it works or supervises.
enum _Activity {
  lookingForHermes,
  checkingTools,
  readingPlan,
  startingFound,
  startingInstalled,
}

/// The checklist's rows.
enum _Row { tools, hermes }

final class _InstallFlowScreenState extends ConsumerState<InstallFlowScreen> {
  _Phase _phase = _Phase.working;
  _Activity _activity = _Activity.lookingForHermes;
  PrerequisiteCheck? _prereqs;

  /// Whether the installer of the missing prerequisites was opened.
  bool _prereqsRequested = false;

  /// Whether that installer is being opened: Install and Check again wait.
  bool _requestingPrereqs = false;

  /// Whether a check found prerequisites missing: once present they were
  /// installed now, not found in place.
  bool _toolsWereMissing = false;

  /// Whether the prerequisites could not be checked at all.
  bool _toolsFailed = false;
  InstallManifest? _manifest;
  final _done = <String, StageResult>{};
  String? _running;
  String? _failedStage;
  String? _error;
  final _log = <String>[];

  late final HermesInstaller _installer =
      widget.installer ??
      makeInstaller(
        widget.host.hermesHome,
        journalPath: widget.host.installJournalPath,
      );

  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  void _appendLog(String stream, String line) {
    if (!mounted) return;
    setState(() {
      _log.add('[$stream] $line');
      if (_log.length > 200) _log.removeRange(0, _log.length - 200);
    });
  }

  Future<void> _start() async {
    final existing = widget.detected;
    if (existing != null) {
      setState(() {
        _phase = _Phase.supervising;
        _activity = _Activity.startingFound;
        _error = null;
      });
      await _superviseAndFinish();
      return;
    }
    setState(() {
      _phase = _Phase.working;
      _activity = _Activity.checkingTools;
      _error = null;
      _failedStage = null;
      _toolsFailed = false;
    });
    try {
      _prereqs = await _installer.checkPrerequisites();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
          _toolsFailed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    if (!_prereqs!.ok) {
      setState(() {
        _phase = _Phase.failed;
        _toolsWereMissing = true;
      });
      return;
    }
    _prereqsRequested = false;
    setState(() => _activity = _Activity.readingPlan);
    try {
      _manifest = await _installer.manifest();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.stages);
    await _runStages();
  }

  /// Opens the installer of the missing prerequisites (macOS: Apple's
  /// Command Line Tools dialog); the user then checks again.
  Future<void> _installPrerequisites() async {
    setState(() {
      _requestingPrereqs = true;
      _error = null;
    });
    try {
      await _installer.installPrerequisites();
      if (mounted) setState(() => _prereqsRequested = true);
    } on ProcessFailed catch (e) {
      if (mounted) setState(() => _error = '${e.message}: ${e.outputTail}');
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _requestingPrereqs = false);
  }

  Future<void> _runStages() async {
    try {
      await for (final event in _installer.run()) {
        if (!mounted) return;
        switch (event) {
          case InstallStageStarted(:final stage):
            setState(() => _running = stage.name);
          case InstallStageFinished(:final stage, :final result):
            setState(() {
              _done[stage.name] = result;
              _running = null;
            });
          case InstallLog(:final stream, :final line):
            _appendLog(stream, line);
        }
      }
    } on InstallFailed catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _failedStage = e.stage;
          _error = e.message;
          _running = null;
        });
      }
      return;
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
          _running = null;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.supervising;
      _activity = _Activity.startingInstalled;
      _failedStage = null;
    });
    await _superviseAndFinish();
  }

  Future<void> _retryStage() async {
    final stage = _failedStage;
    if (stage == null) {
      setState(() => _phase = _Phase.stages);
      await _runStages();
      return;
    }
    setState(() {
      _phase = _Phase.stages;
      _error = null;
      _running = stage;
    });
    try {
      final result = await _installer.runStage(stage, onLine: _appendLog);
      if (!mounted) return;
      setState(() {
        _done[stage] = result;
        _running = null;
      });
      if (result.failed) {
        setState(() {
          _phase = _Phase.failed;
          _error = result.reason ?? 'stage $stage failed';
        });
        return;
      }
      // Continue with the remaining stages.
      await _runStages();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
          _running = null;
        });
      }
    }
  }

  Future<void> _superviseAndFinish() async {
    // Registering the instance swaps the welcome routes for the chat, which
    // disposes this screen while boot still runs: read what the end needs
    // now, not through a disposed ref.
    final registry = ref.read(registryProvider.future);
    final activeThread = ref.read(activeThreadProvider.notifier);
    try {
      final instance = await widget.host.boot(await registry);
      if (instance == null) {
        // Install finished but detection still misses: re-detect failed.
        throw const InstallFailed(
          '__supervise__',
          'Install finished but no Hermes launcher answers --version.',
        );
      }
      await activeThread.openInstance(instance.id);
      widget.onDone(instance);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
        });
      }
    }
  }

  /// Whether the flow stopped on the prerequisites rather than on Hermes.
  bool get _toolsBlock =>
      _phase == _Phase.failed &&
      (_toolsFailed || (_prereqs != null && !_prereqs!.ok));

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(
      vertical: YsSpace.xxl + YsSpace.lg,
      horizontal: YsSpace.xl,
    ),
    child: SetupCard(
      title: 'Install Hermes',
      status: _status,
      items: [_tools(), _hermes()],
      log: _log,
      actions: [YsButton.neutral(label: 'Cancel', onPressed: widget.onCancel)],
    ),
  );

  String get _status => switch (_phase) {
    _Phase.working || _Phase.supervising => switch (_activity) {
      _Activity.lookingForHermes => 'Looking for Hermes…',
      _Activity.checkingTools => 'Checking prerequisites…',
      _Activity.readingPlan => 'Reading install plan…',
      _Activity.startingFound =>
        '${widget.detected?.version ?? 'Hermes'} is already installed — '
            'starting it…',
      _Activity.startingInstalled => 'Install finished — starting Hermes…',
    },
    _Phase.stages => 'Installing Hermes Agent…',
    _Phase.failed when _toolsBlock => 'Some developer tools are missing.',
    _Phase.failed => 'The install stopped on a failure.',
  };

  YsChecklistItem _tools() {
    YsChecklistItem item(
      YsStepState state,
      String status, {
      List<YsChecklistNote> notes = const [],
      List<Widget> actions = const [],
    }) => YsChecklistItem(
      id: _Row.tools,
      icon: YsIcon.package,
      title: 'Developer tools',
      state: state,
      status: status,
      notes: notes,
      actions: actions,
    );
    if (widget.detected != null) {
      return item(
        YsStepState.skipped,
        'Not needed — Hermes is already installed',
      );
    }
    // The Windows installer provisions its own tools.
    if (Platform.isWindows) {
      return item(
        YsStepState.skipped,
        'Not needed — the installer brings them',
      );
    }
    if (_phase == _Phase.working && _activity == _Activity.checkingTools) {
      return item(YsStepState.checking, 'Checking…');
    }
    final prereqs = _prereqs;
    if (_toolsFailed || prereqs == null) {
      return _toolsFailed
          ? item(
              YsStepState.failed,
              'Could not be checked',
              notes: [
                if (_error case final error?)
                  YsChecklistNote(error, tone: YsNoteTone.alert),
              ],
              actions: [
                YsButton.neutral(label: 'Check again', onPressed: _start),
              ],
            )
          : item(YsStepState.pending, 'Waiting');
    }
    if (!prereqs.ok) {
      final fix = prereqs.fixCommand;
      return item(
        YsStepState.needsAction,
        'Missing: ${prereqs.missing.join(', ')}',
        notes: [
          if (prereqs.installable)
            YsChecklistNote(
              _prereqsRequested
                  ? 'Finish the installation in the dialog that opened, '
                        'then choose Check again.'
                  : 'Install them, then choose Check again.',
            )
          else if (fix != null)
            YsChecklistNote('Run $fix, then choose Check again.'),
          if (_error case final error?)
            YsChecklistNote(error, tone: YsNoteTone.alert),
        ],
        actions: [
          if (prereqs.installable && !_prereqsRequested)
            YsButton.neutral(
              label: _requestingPrereqs ? 'Opening the installer…' : 'Install',
              onPressed: _requestingPrereqs ? null : _installPrerequisites,
            ),
          YsButton.neutral(
            label: 'Check again',
            onPressed: _requestingPrereqs ? null : _start,
          ),
        ],
      );
    }
    return _toolsWereMissing
        ? item(YsStepState.done, 'Installed now')
        : item(YsStepState.found, 'Already installed');
  }

  YsChecklistItem _hermes() {
    YsChecklistItem item(
      YsStepState state,
      String status, {
      double? progress,
      String? trailing,
      List<YsChecklistNote> notes = const [],
      List<Widget> actions = const [],
    }) => YsChecklistItem(
      id: _Row.hermes,
      icon: YsIcon.bot,
      title: 'Hermes Agent',
      state: state,
      status: status,
      progress: progress,
      trailing: trailing,
      notes: notes,
      actions: actions,
    );
    final manifest = _manifest;
    final total = manifest?.stages.length ?? 0;
    final count = manifest == null ? null : '${_done.length}/$total';
    switch (_phase) {
      case _Phase.working:
        return switch (_activity) {
          _Activity.lookingForHermes => item(
            YsStepState.checking,
            'Looking for it on this computer…',
          ),
          _Activity.readingPlan => item(
            YsStepState.working,
            'Reading the install plan…',
          ),
          _ => item(YsStepState.pending, 'Waiting'),
        };
      case _Phase.stages:
        final running = _running;
        return item(
          YsStepState.working,
          running == null ? 'Preparing the next step…' : _stageTitle(running),
          progress: total == 0 ? null : _done.length / total,
          trailing: count,
        );
      case _Phase.supervising:
        // An install found in place is started, not installed.
        return _activity == _Activity.startingFound
            ? item(YsStepState.checking, switch (widget.detected?.semver) {
                final version? => 'Already installed · $version — starting it…',
                null => 'Already installed — starting it…',
              })
            : item(YsStepState.working, 'Starting it…');
      case _Phase.failed when _toolsBlock:
        return item(YsStepState.pending, 'Waiting');
      case _Phase.failed:
        final stage = _failedStage;
        return item(
          YsStepState.failed,
          stage == null ? 'Failed' : 'Failed at “${_stageTitle(stage)}”',
          trailing: count,
          notes: [
            YsChecklistNote(
              _error ?? 'The install failed.',
              tone: YsNoteTone.alert,
            ),
            if (stage != null)
              const YsChecklistNote(
                'Fix the cause, then retry just this stage.',
              ),
          ],
          actions: [
            if (stage != null)
              YsButton.neutral(
                label: 'Retry this stage',
                onPressed: _retryStage,
              )
            else
              YsButton.neutral(label: 'Try again', onPressed: _start),
          ],
        );
    }
  }

  String _stageTitle(String stage) {
    for (final s in _manifest?.stages ?? const <InstallStage>[]) {
      if (s.name == stage) return s.title;
    }
    return stage;
  }
}
