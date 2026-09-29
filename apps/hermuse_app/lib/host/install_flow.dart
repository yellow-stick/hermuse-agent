import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/local_host.dart';
import '../shell/screens.dart';

/// Desktop install flow: detect → (supervise | staged install) → onboard.
///
/// [detected] is the [HermesDetector.detect] outcome computed by the caller
/// (so Welcome can decide). When non-null the flow just supervises the
/// existing install via [host] and hands the registered local instance back.
/// Otherwise it runs the staged installer UI: prerequisites → manifest →
/// stage progress with output log → retry-this-stage on failure → supervise.
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

final class _InstallFlowScreenState extends ConsumerState<InstallFlowScreen> {
  _Phase _phase = _Phase.working;
  String _status = 'Looking for Hermes…';
  PrerequisiteCheck? _prereqs;

  /// Whether the installer of the missing prerequisites was opened.
  bool _prereqsRequested = false;
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
        _status = 'Found ${existing.version} — starting it…';
      });
      await _superviseAndFinish();
      return;
    }
    setState(() {
      _phase = _Phase.working;
      _status = 'Checking prerequisites…';
      _error = null;
    });
    try {
      _prereqs = await _installer.checkPrerequisites();
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
    if (!_prereqs!.ok) {
      setState(() => _phase = _Phase.failed);
      return;
    }
    _prereqsRequested = false;
    setState(() => _status = 'Reading install plan…');
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
    try {
      await _installer.installPrerequisites();
      if (mounted) setState(() => _prereqsRequested = true);
    } on ProcessFailed catch (e) {
      if (mounted) setState(() => _error = '${e.message}: ${e.outputTail}');
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
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
      _status = 'Install finished — starting Hermes…';
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
    try {
      final instance = await widget.host.boot(
        await ref.read(registryProvider.future),
      );
      if (instance == null) {
        // Install finished but detection still misses: re-detect failed.
        throw const InstallFailed(
          '__supervise__',
          'Install finished but no Hermes launcher answers --version.',
        );
      }
      await ref.read(activeThreadProvider.notifier).openInstance(instance.id);
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

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: YsLayout.dialogWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.paperColor,
              borderRadius: BorderRadius.circular(YsRadius.bubble),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const YsDialogTitle('Install Hermes'),
                  const SizedBox(height: 16),
                  ..._body(palette),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      YsButton.neutral(
                        label: 'Cancel',
                        onPressed: widget.onCancel,
                      ),
                      if (_phase == _Phase.failed && _failedStage != null)
                        YsButton.primary(
                          label: 'Retry this stage',
                          onPressed: _retryStage,
                        ),
                      if (_phase == _Phase.failed &&
                          _prereqs != null &&
                          !_prereqs!.ok) ...[
                        if (_prereqs!.installable && !_prereqsRequested)
                          YsButton.primary(
                            label: 'Install',
                            onPressed: _installPrerequisites,
                          ),
                        YsButton.neutral(
                          label: 'Check again',
                          onPressed: _start,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(YsPalette palette) {
    switch (_phase) {
      case _Phase.working:
      case _Phase.supervising:
        return [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const YsSpinner(size: 16),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _status,
                  style: YsType.body.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ];
      case _Phase.failed:
        final prereqs = _prereqs;
        if (prereqs != null && !prereqs.ok) {
          return [
            Text(
              'Missing tools: ${prereqs.missing.join(', ')}.',
              style: YsType.body.flutter.copyWith(color: palette.errorColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (prereqs.installable)
              Text(
                _prereqsRequested
                    ? 'Finish the installation in the dialog that opened, '
                          'then check again.'
                    : 'Install them, then check again.',
                style: YsType.body.flutter.copyWith(
                  color: palette.contentMutedColor,
                ),
                textAlign: TextAlign.center,
              )
            else if (prereqs.fixCommand != null)
              SelectableText(
                prereqs.fixCommand!,
                style: YsType.body.flutter.copyWith(
                  color: palette.contentColor,
                ),
                textAlign: TextAlign.center,
              ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: YsType.small.flutter.copyWith(color: palette.errorColor),
                textAlign: TextAlign.center,
              ),
            ],
          ];
        }
        return [
          Text(
            _error ?? 'The install failed.',
            style: YsType.body.flutter.copyWith(color: palette.errorColor),
            textAlign: TextAlign.center,
          ),
          if (_failedStage != null) ...[
            const SizedBox(height: 8),
            Text(
              'Stage "${_failedStage!}" failed; fix the cause, then retry '
              'just this stage.',
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            InstallLogBox(log: _log),
          ],
          if (_manifest != null) ...[
            const SizedBox(height: 12),
            InstallStageList(
              manifest: _manifest!,
              done: _done,
              running: _running,
            ),
          ],
        ];
      case _Phase.stages:
        final manifest = _manifest!;
        final total = manifest.stages.length;
        final finished = _done.length;
        return [
          Text(
            'Step $finished of $total',
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          InstallProgressBar(value: total == 0 ? 1 : finished / total),
          const SizedBox(height: 12),
          InstallStageList(manifest: manifest, done: _done, running: _running),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            InstallLogBox(log: _log),
          ],
        ];
    }
  }
}

/// Install progress: [value] from 0 to 1.
final class InstallProgressBar extends StatelessWidget {
  const InstallProgressBar({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return SizedBox(
      height: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.neutralAmbientColor,
          borderRadius: BorderRadius.circular(YsRadius.pill),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.primaryColor,
                borderRadius: BorderRadius.circular(YsRadius.pill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The installer's stages with their state (waiting, running, done, skipped,
/// failed).
final class InstallStageList extends StatelessWidget {
  const InstallStageList({
    required this.manifest,
    required this.done,
    required this.running,
    super.key,
  });

  final InstallManifest manifest;
  final Map<String, StageResult> done;
  final String? running;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final stage in manifest.stages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(child: _stageIcon(palette, stage)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stage.title,
                        style: YsType.label.flutter.copyWith(
                          color: palette.contentColor,
                        ),
                      ),
                      if (stage.category.isNotEmpty)
                        Text(
                          stage.category,
                          style: YsType.caption.flutter.copyWith(
                            color: palette.contentSubtleColor,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _stageState(stage),
                  style: YsType.caption.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _stageState(InstallStage stage) {
    final result = done[stage.name];
    if (stage.name == running) return 'Running…';
    if (result == null) return 'Waiting';
    if (result.failed) return 'Failed';
    if (result.skipped) return 'Skipped';
    return 'Done';
  }

  Widget _stageIcon(YsPalette palette, InstallStage stage) {
    final result = done[stage.name];
    if (stage.name == running) return const YsSpinner(size: 14);
    if (result == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.lineColor, width: ysHairline),
        ),
        child: const SizedBox(width: 14, height: 14),
      );
    }
    if (result.failed) {
      return YsIconWidget(YsIcon.close, size: 14, color: palette.errorColor);
    }
    return YsIconWidget(YsIcon.check, size: 14, color: palette.successColor);
  }
}

/// Last output lines, scrolled to the newest.
final class InstallLogBox extends StatefulWidget {
  const InstallLogBox({required this.log, super.key});

  final List<String> log;

  @override
  State<InstallLogBox> createState() => _InstallLogBoxState();
}

final class _InstallLogBoxState extends State<InstallLogBox> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvasColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 160),
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              widget.log.join('\n'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 18 / 12,
              ).copyWith(color: palette.contentMutedColor),
            ),
          ),
        ),
      ),
    );
  }
}
