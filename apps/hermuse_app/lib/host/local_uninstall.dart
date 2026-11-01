import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart' show Scrollbar, SelectableText;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:path/path.dart' as p;
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/local_host.dart';
import '../shell/screens.dart';
import 'linux_setup.dart';
import 'setup_view.dart';

sealed class LocalRemovalState {
  const LocalRemovalState();
}

final class LocalRemovalInspecting extends LocalRemovalState {
  const LocalRemovalInspecting();
}

final class LocalRemovalReview extends LocalRemovalState {
  const LocalRemovalReview(this.inventory, {this.notice});
  final String? notice;
  final RemoteUninstallInventory inventory;
}

final class LocalRemovalRunning extends LocalRemovalState {
  const LocalRemovalRunning(this.lines);
  final List<String> lines;
}

final class LocalRemovalFailed extends LocalRemovalState {
  const LocalRemovalFailed(this.message);
  final String message;
}

final class LocalRemovalFinished extends LocalRemovalState {
  const LocalRemovalFinished(this.outcome, {this.registrationError});
  final RemoteUninstallOutcome outcome;
  final String? registrationError;
}

/// Inspects first, then quiesces and reverts only the reviewed installation.
///
/// The host stays suspended until this controller is disposed, including on
/// partial failure. An unexpected disposal cannot restart it during removal.
final class LocalUninstallController extends ChangeNotifier {
  LocalUninstallController({
    required this.inspectInstallation,
    required this.prepare,
    required this.removeInstallation,
    required this.forgetRegistration,
    required this.release,
  });

  final Future<RemoteUninstallInventory> Function() inspectInstallation;
  final Future<void> Function() prepare;
  final Future<RemoteUninstallOutcome> Function(
    RemoteUninstallInventory inventory, {
    required bool purge,
    void Function(String line)? onLog,
  })
  removeInstallation;
  final Future<void> Function(bool purge) forgetRegistration;
  final VoidCallback release;

  LocalRemovalState _state = const LocalRemovalInspecting();
  LocalRemovalState get state => _state;
  bool get busy => _state is LocalRemovalRunning;
  var _disposed = false;
  var _suspended = false;
  var _inspecting = false;

  final List<String> _log = [];
  List<String> _publishedLog = const [];
  List<String> get log => _publishedLog;

  void _publish(LocalRemovalState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<void> inspect() async {
    if (_disposed || busy || _inspecting) return;
    _inspecting = true;
    _publish(const LocalRemovalInspecting());
    try {
      _publish(LocalRemovalReview(await inspectInstallation()));
    } on Object catch (error) {
      _publish(
        LocalRemovalFailed('Could not inspect this installation: $error'),
      );
    } finally {
      _inspecting = false;
    }
  }

  Future<void> uninstall({required bool purge}) async {
    final current = _state;
    if (_disposed || current is! LocalRemovalReview) return;
    final inventory = current.inventory;
    if (inventory.transactionActive) return;
    if (!inventory.resources.any(
      (resource) => resource.removable && (purge || !resource.purgeOnly),
    )) {
      return;
    }
    _log.clear();
    _publishedLog = const [];
    _publish(const LocalRemovalRunning([]));
    try {
      _suspended = true;
      await prepare();
      final refreshed = await inspectInstallation();
      if (refreshed.revision != inventory.revision ||
          refreshed.transactionActive) {
        _publish(
          LocalRemovalReview(
            refreshed,
            notice:
                'The inventory changed while stopping local processes. '
                'Review this updated inventory and confirm again. Local '
                'processes remain stopped until you leave this page.',
          ),
        );
        return;
      }
      final outcome = await removeInstallation(
        inventory,
        purge: purge,
        onLog: (line) {
          _log.add(line);
          if (_log.length > 200) _log.removeAt(0);
          _publishedLog = List.unmodifiable(_log);
          _publish(LocalRemovalRunning(_publishedLog));
        },
      );
      String? registrationError;
      if (outcome.complete) {
        try {
          await forgetRegistration(purge);
        } on Object catch (error) {
          registrationError =
              'Installation removal finished, but its saved '
              'local connection or credentials could not be removed: $error';
        }
      }
      _publish(
        LocalRemovalFinished(outcome, registrationError: registrationError),
      );
    } on Object catch (error) {
      _publish(
        LocalRemovalFailed(
          'Removal did not finish: $error. Resources already removed are not '
          'restored. Inspect again to review what remains. The saved local '
          'connection was not intentionally removed.',
        ),
      );
    } finally {
      if (_disposed) _release();
    }
  }

  void _release() {
    if (!_suspended) return;
    _suspended = false;
    release();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!busy) _release();
    super.dispose();
  }
}

/// Forgets only the local target's registration and its own saved credentials.
///
/// App-wide subscription bridge keys have no per-install ownership evidence.
/// They stay in secure storage even after a purge and even with no remote
/// registrations; an independently managed bridge may still depend on them.
Future<void> forgetLocalInstallationRegistration(
  HermesRegistry registry,
) async {
  final selected = registry.byId(localInstanceId);
  if (selected != null && selected.kind == InstanceKind.remote) {
    throw StateError('Refusing to remove a remote registration');
  }
  await registry.remove(localInstanceId);
}

/// Native Linux target rollback; never uninstalls the Hermuse application.
final class LocalUninstallScreen extends ConsumerStatefulWidget {
  const LocalUninstallScreen({
    required this.host,
    required this.onClose,
    super.key,
  });

  final LocalHermesHost host;
  final VoidCallback onClose;

  @override
  ConsumerState<LocalUninstallScreen> createState() =>
      _LocalUninstallScreenState();
}

final class _LocalUninstallScreenState
    extends ConsumerState<LocalUninstallScreen>
    with WidgetsBindingObserver {
  late LocalUninstallController _controller;
  final _confirmation = TextEditingController();
  final _resourcesScroll = ScrollController();
  var _purge = false;
  var _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final container = ProviderScope.containerOf(context, listen: false);
    final host = widget.host;
    const root = String.fromEnvironment('HERMUSE_WORKSPACE_ROOT');
    final installer = LinuxServiceInstaller.system(
      workspaceRoot: root.isEmpty ? null : root,
    );
    _controller = LocalUninstallController(
      inspectInstallation: () async {
        if (!Platform.isLinux || !host.canonicalService) {
          throw StateError('Local installation rollback is unavailable here');
        }
        final registry = await container.read(registryProvider.future);
        final selected = registry.byId(localInstanceId);
        if (selected != null && selected.kind == InstanceKind.remote) {
          throw StateError('The selected instance is not local');
        }
        return installer.inspectUninstall();
      },
      prepare: () async {
        await container.read(linuxSetupProvider.notifier).stopAndWait();
        await host.prepareForUninstall();
        // Closing the transport cancels its reconnect timer. Invalidation
        // releases only this target's providers; host boot is already blocked.
        final connection = container.read(connectionProvider(localInstanceId));
        await connection.value?.transport.close();
        container.invalidate(connectionProvider(localInstanceId));
      },
      removeInstallation: (inventory, {required purge, onLog}) async {
        RemoteUninstallOutcome? outcome;
        await for (final event in installer.uninstall(
          inspection: inventory,
          deleteAll: purge,
        )) {
          switch (event) {
            case RemoteUninstallLog(:final line):
              onLog?.call(line);
            case RemoteUninstallCompleted(outcome: final result):
              outcome = result;
            case RemoteUninstallStepStarted() || RemoteUninstallStepFinished():
              break;
          }
        }
        return outcome ??
            (throw StateError('Removal ended before verification.'));
      },
      forgetRegistration: (_) async {
        final registry = await container.read(registryProvider.future);
        // Only target-scoped credentials are owned by this registration.
        final showingLocal =
            container.read(activeThreadProvider).value?.instanceId ==
            localInstanceId;
        await forgetLocalInstallationRegistration(registry);
        if (showingLocal) {
          final next = registry.primary;
          if (next == null) {
            container.invalidate(activeThreadProvider);
          } else {
            await container
                .read(activeThreadProvider.notifier)
                .openInstance(next.id);
          }
        }
      },
      release: host.finishUninstall,
    );
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_reviewChanged);
    unawaited(_controller.inspect());
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async =>
      _controller.busy ? AppExitResponse.cancel : AppExitResponse.exit;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _confirmation.dispose();
    _resourcesScroll.dispose();
    super.dispose();
  }

  void _reviewChanged() {
    if (_controller.state is LocalRemovalReview) _confirmation.clear();
  }

  void _inspect() {
    _confirmation.clear();
    unawaited(_controller.inspect());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final state = _controller.state;
      return PopScope(
        canPop: !_controller.busy,
        child: SetupOperationFrame(
          busy: _controller.busy,
          log: _controller.log,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: YsSpace.xs,
            children: [
              Text(
                'Uninstall from this computer',
                style: YsType.title.flutter.copyWith(
                  color: YsTheme.of(context).contentColor,
                ),
              ),
              _text(Platform.localHostname),
              SelectableText(
                widget.host.hermesHome,
                maxLines: 1,
                style: YsType.body.flutter.copyWith(
                  color: YsTheme.of(context).contentMutedColor,
                ),
              ),
              _text(
                'Hermuse Agent stays installed. Only proven, target-owned '
                'resources can be reverted. No force deletion.',
              ),
            ],
          ),
          content: Scrollbar(
            controller: _resourcesScroll,
            thumbVisibility: true,
            child: ListView(
              controller: _resourcesScroll,
              padding: const EdgeInsets.only(right: YsSpace.md),
              children: switch (state) {
                LocalRemovalInspecting() => [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: YsSpinner(size: YsLayout.inlineIcon),
                  ),
                  _text('Reading installation ownership… Nothing is changed.'),
                ],
                LocalRemovalReview(:final inventory, :final notice) => [
                  if (notice != null) YsDialogError(notice),
                  ..._review(inventory),
                ],
                LocalRemovalRunning() => [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: YsSpinner(size: YsLayout.inlineIcon),
                  ),
                  _heading('Removing selected resources'),
                  _text(
                    'Keep Hermuse open until removal finishes. '
                    'Live technical output appears in the log below.',
                  ),
                ],
                LocalRemovalFailed(:final message) => [
                  _heading('Removal could not finish'),
                  YsDialogError(message),
                ],
                LocalRemovalFinished() => _result(state),
              },
            ),
          ),
          footer: _footer(state),
        ),
      );
    },
  );

  Widget _text(String text) => Text(
    text,
    style: YsType.body.flutter.copyWith(
      color: YsTheme.of(context).contentMutedColor,
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: YsSpace.sm),
    child: Text(
      text,
      style: YsType.heading.flutter.copyWith(
        color: YsTheme.of(context).contentColor,
      ),
    ),
  );

  List<Widget> _review(RemoteUninstallInventory inventory) {
    final selected = <RemoteUninstallResource>[];
    final preserved = <RemoteUninstallResource>[];
    for (final resource in inventory.resources) {
      (resource.removable && (_purge || !resource.purgeOnly)
              ? selected
              : preserved)
          .add(resource);
    }
    return [
      _text(
        'Read-only inventory. Shared, pre-existing, changed and unproven '
        'resources stay in place. Expand a row for its full path and reason.',
      ),
      if (inventory.transactionActive)
        const YsDialogError(
          'Another setup or removal is active. Wait for it to finish, then inspect again.',
        ),
      if (inventory.resources.isEmpty)
        _text(
          'No owned resources found. Legacy or unrecorded installations '
          'cannot be safely removed here.',
        ),
      _heading('Remove or restore · ${selected.length}'),
      for (final resource in selected) _resourceRow(resource),
      if (selected.isEmpty) _text('Nothing eligible for this choice.'),
      _heading('Preserve · ${preserved.length}'),
      for (final resource in preserved) _resourceRow(resource),
      _heading('Connection and credentials'),
      _text(
        'The selected local connection and its credentials are forgotten '
        'only after all selected operations finish. Other saved connections, '
        'app storage and shared subscription bridge keys are preserved.',
      ),
    ];
  }

  Widget _resourceRow(RemoteUninstallResource resource) => Padding(
    key: ValueKey(resource.id),
    padding: const EdgeInsets.symmetric(vertical: YsSpace.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: YsSpace.xs,
      children: [
        Text(
          p.posix.basename(resource.label),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: YsType.label.flutter.copyWith(
            color: YsTheme.of(context).contentColor,
          ),
        ),
        _text(
          '${resource.kind}'
          '${resource.purgeOnly ? ' · Data / cache' : ''}',
        ),
        Text(
          resource.removable && resource.purgeOnly && !_purge
              ? 'Kept by your data choice. ${resource.reason}'
              : resource.reason,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: YsType.body.flutter.copyWith(
            color: YsTheme.of(context).contentMutedColor,
          ),
        ),
        YsDisclosure(
          label: 'Path and reason',
          openLabel: 'Hide details',
          child: SelectableText(
            '${resource.label}\n\n${resource.reason}',
            style: YsType.body.flutter.copyWith(
              color: YsTheme.of(context).contentColor,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _footer(LocalRemovalState state) {
    if (state is LocalRemovalRunning) {
      return _text('Removal in progress. Closing is disabled for safety.');
    }
    final canRemove =
        state is LocalRemovalReview &&
        !state.inventory.transactionActive &&
        state.inventory.resources.any(
          (resource) => resource.removable && (_purge || !resource.purgeOnly),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: YsSpace.sm,
      children: [
        if (state is LocalRemovalReview) ...[
          Wrap(
            spacing: YsSpace.sm,
            runSpacing: YsSpace.sm,
            children: [
              YsButton.neutral(
                label: _purge ? 'Keep data' : 'Keep data (selected)',
                onPressed: () => setState(() {
                  _purge = false;
                  _confirmation.clear();
                }),
              ),
              YsButton.neutral(
                label: _purge ? 'Purge data (selected)' : 'Purge data',
                onPressed: () => setState(() {
                  _purge = true;
                  _confirmation.clear();
                }),
              ),
            ],
          ),
          _text(
            _purge
                ? 'Permanently delete eligible data and caches. Cannot be undone.'
                : 'Keep settings, conversations and caches where permitted. '
                      'You can review a purge later.',
          ),
          if (canRemove)
            YsInputBox(
              controller: _confirmation,
              placeholder: 'Type UNINSTALL to confirm',
              semanticLabel: 'Type UNINSTALL to confirm local removal',
              onChanged: (_) => setState(() {}),
            )
          else
            _text(
              'Nothing eligible. Preserved resources and the saved '
              'connection remain unchanged.',
            ),
        ],
        Wrap(
          spacing: YsSpace.sm,
          runSpacing: YsSpace.sm,
          children: [
            if (canRemove)
              YsButton.destructive(
                label: _purge
                    ? 'Uninstall and purge data'
                    : 'Uninstall and keep data',
                onPressed: _confirmation.text == 'UNINSTALL'
                    ? () => unawaited(_controller.uninstall(purge: _purge))
                    : null,
              ),
            if (state is! LocalRemovalInspecting)
              YsButton.neutral(
                label: state is LocalRemovalFinished
                    ? 'Inspect remaining resources'
                    : 'Inspect again',
                onPressed: _inspect,
              ),
            YsButton.neutral(label: 'Close', onPressed: widget.onClose),
          ],
        ),
      ],
    );
  }

  List<Widget> _result(LocalRemovalFinished result) => [
    _heading(
      result.outcome.complete && result.registrationError == null
          ? 'Selected removal completed'
          : 'Removal partially completed',
    ),
    _text(
      'Hermuse stays installed. The ownership audit is retained for later '
      'review; this is not a trace-free uninstall.',
    ),
    if (!result.outcome.complete)
      _text(
        'Some operations did not finish. The saved local connection is kept. '
        'Inspect remaining resources before retrying.',
      ),
    if (result.registrationError case final error?) YsDialogError(error),
    _heading('Removed or restored · ${result.outcome.removed.length}'),
    for (final removed in result.outcome.removed) _resultRow(removed),
    _heading('Retained · ${result.outcome.preserved.length}'),
    for (final retained in result.outcome.preserved) _resourceRow(retained),
    for (final warning in result.outcome.warnings) YsDialogError(warning),
    _heading('Also preserved'),
    _text(
      'Shared subscription bridge keys in secure storage. Their ownership '
      'cannot be attributed to this installation.',
    ),
  ];

  Widget _resultRow(String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: YsSpace.sm),
    child: SelectableText(
      detail,
      style: YsType.body.flutter.copyWith(
        color: YsTheme.of(context).contentColor,
      ),
    ),
  );
}
