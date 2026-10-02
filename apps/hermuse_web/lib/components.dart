import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'scope.dart';
import 'screens.dart';

/// "What's on `label`": the component checklist of a Hermes reached
/// through the relay ([remoteSetupProvider]). Each part Hermuse needs there
/// (Hermes itself, the Hermuse plugin, its jobs, Docker, the agent's
/// computer, a model) shows found, missing, waiting on another or being
/// installed, with its action; what only the server can do comes with the
/// command to copy and Check again. The ring counts the parts in place and
/// plays its ready moment once all are.
///
/// Shown once a Hermes is added and from its Instances row. Continue opens
/// the chat ([onChat]) once a model answers, else the onboarding
/// ([onSetUpModel]); it waits while a look or an install runs. Desktop
/// parity: `ComponentsScreen`.
class HermuseComponents extends StatelessComponent {
  const HermuseComponents({
    required this.instance,
    required this.onChat,
    required this.onSetUpModel,
    super.key,
  });

  final HermesInstance instance;
  final VoidCallback onChat;
  final VoidCallback onSetUpModel;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: remoteSetupProvider(instance.id),
    builder: (context, state) => _body(state),
  );

  RemoteSetup get _setup =>
      HermuseScope.container.read(remoteSetupProvider(instance.id).notifier);

  Component _body(RemoteSetupState state) {
    final phase = state.phase;
    final total = state.parts.length;
    final unreachable = phase == RemoteSetupPhase.unreachable;
    // A look or an install runs: what depends on its outcome waits for it.
    final working = _working(state);
    // Busy, every other action waits: nothing is installable then. Installs
    // need the Hermes to answer.
    final everything = !unreachable && state.installable.length >= 2;
    final onContinue = working
        ? null
        : state[RemotePart.model].status.settled
        ? onChat
        : onSetUpModel;
    return div(classes: 'hermuse-screen hermuse-screen-top', [
      div(classes: 'hermuse-list-card hermuse-parts', [
        // Reaching out while it looks or installs, unplugged when the Hermes
        // does not answer or an install failed, ready once all is in place.
        HermuseDialogHead(
          art: switch (phase) {
            RemoteSetupPhase.unreachable ||
            RemoteSetupPhase.failed => YsArt.unreachable,
            RemoteSetupPhase.ready => YsArt.ready,
            _ => YsArt.remote,
          },
          busy:
              phase == RemoteSetupPhase.checking ||
              phase == RemoteSetupPhase.installing,
          title: "What's on ${instance.label}",
          helper: state.headline,
          live: true,
          trailing: YsProgressRing(
            value: total == 0 ? 0 : state.settled / total,
            label: '${state.settled}/$total',
            complete: phase == RemoteSetupPhase.ready,
          ),
        ),
        if (state.unreachable case final reason?) HermuseErrorNotice(reason),
        YsChecklist(items: [for (final row in state.parts) _item(row)]),
        // One main action: the installs when offered, else reaching the
        // Hermes again when it does not answer, else Continue.
        div(classes: 'hermuse-parts-actions', [
          if (everything)
            YsButton.primary(
              label: 'Install everything missing',
              onPressed: working
                  ? null
                  : () => unawaited(_setup.installEverything()),
            ),
          if (unreachable)
            YsButton.primary(
              label: working ? 'Checking…' : 'Check again',
              onPressed: working ? null : () => unawaited(_setup.checkAgain()),
            ),
          if (everything || unreachable)
            YsButton.neutral(label: 'Continue', onPressed: onContinue)
          else
            YsButton.primary(label: 'Continue', onPressed: onContinue),
        ]),
      ]),
    ]);
  }

  /// Whether a look or an install of [state] runs: Continue, "Install
  /// everything missing" and "Check again" wait for it.
  static bool _working(RemoteSetupState state) =>
      state.busy ||
      state.parts.any(
        (row) =>
            row.status == RemotePartStatus.checking ||
            row.status == RemotePartStatus.installing,
      );

  YsChecklistItem _item(RemotePartState row) => YsChecklistItem(
    id: row.part.name,
    icon: switch (row.part) {
      RemotePart.hermes => YsIcon.bot,
      RemotePart.plugin => YsIcon.puzzle,
      RemotePart.jobs => YsIcon.upcoming,
      RemotePart.docker => YsIcon.container,
      RemotePart.computer => YsIcon.monitor,
      RemotePart.model => YsIcon.sparkles,
    },
    title: row.part.title,
    state: switch (row.status) {
      RemotePartStatus.checking => YsStepState.checking,
      RemotePartStatus.present => YsStepState.found,
      RemotePartStatus.installed => YsStepState.done,
      RemotePartStatus.missing ||
      RemotePartStatus.needsUser => YsStepState.needsAction,
      RemotePartStatus.blocked => YsStepState.pending,
      RemotePartStatus.installing => YsStepState.working,
      RemotePartStatus.failed => YsStepState.failed,
    },
    status: row.summary,
    notes: [
      for (final note in row.notes)
        YsChecklistNote(
          note,
          tone: row.alert ? YsNoteTone.alert : YsNoteTone.muted,
        ),
    ],
    actions: [
      // Hermes' own words under the notes: they scroll past a log's height.
      if (row.report case final report?)
        pre(
          classes: 'hermuse-parts-report',
          attributes: const {'tabindex': '0'},
          [.text(report)],
        ),
      if (row.command case final command?)
        _Command(key: ValueKey(command), command: command),
      if (row.action case final action?)
        YsButton.neutral(
          label: action.label,
          onPressed: row.enabled ? () => _act(row.part, action) : null,
        ),
    ],
  );

  void _act(RemotePart part, RemoteAction action) {
    switch (action) {
      case RemoteAction.setUpModel:
        onSetUpModel();
      case RemoteAction.checkAgain:
        unawaited(_setup.checkAgain());
      case _:
        unawaited(_setup.run(part));
    }
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseScreenStyles,
    css('.hermuse-parts', [
      // The head lines up with the rows' badges.
      css('> .hermuse-head')
          .styles(padding: .symmetric(horizontal: YsSpace.sm.px)),
      // Full-width buttons under the checklist, one per line.
      css('.hermuse-parts-actions').styles(
        display: .flex,
        margin: .only(top: YsSpace.sm.px),
        flexDirection: .column,
        gap: .all(YsSpace.sm.px),
      ),
      css('.hermuse-parts-actions > .ys-btn-filled').styles(width: 100.percent),
      css('.hermuse-parts-command').styles(
        display: .flex,
        padding: .only(
          left: YsSpace.md.px,
          top: YsSpace.xs.px,
          right: YsSpace.xs.px,
          bottom: YsSpace.xs.px,
        ),
        radius: .circular(YsRadius.row.px),
        alignItems: .center,
        gap: .all(YsSpace.sm.px),
        backgroundColor: .variable('--canvas'),
        raw: {'min-width': '0'},
      ),
      css('.hermuse-parts-command-text, .hermuse-parts-report').styles(
        fontSize: YsType.code.size.px,
        lineHeight: YsType.code.lineHeight.px,
        raw: {
          'font-family': YsType.monoFamily,
          'overflow-wrap': 'anywhere',
          'white-space': 'pre-wrap',
        },
      ),
      css('.hermuse-parts-command-text').styles(
        color: .variable('--content'),
        raw: {'min-width': '0', 'user-select': 'all'},
      ),
      css('.hermuse-parts-report').styles(
        width: 100.percent,
        maxHeight: YsLayout.logMaxHeight.px,
        padding: .symmetric(vertical: YsSpace.sm.px, horizontal: YsSpace.md.px),
        margin: .zero,
        boxSizing: .borderBox,
        radius: .circular(YsRadius.row.px),
        overflow: .only(y: .auto),
        color: .variable('--content-muted'),
        backgroundColor: .variable('--canvas'),
      ),
    ]),
  ];
}

/// A command to run on the server: selected whole on a click, or copied in
/// one ("Copied" for a moment).
class _Command extends StatefulComponent {
  const _Command({required this.command, super.key});

  final String command;

  @override
  State<_Command> createState() => _CommandState();
}

class _CommandState extends State<_Command> {
  var _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    if (kIsWeb) web.window.navigator.clipboard.writeText(component.command);
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Component build(BuildContext context) =>
      div(classes: 'hermuse-parts-command', [
        code(classes: 'hermuse-parts-command-text', [.text(component.command)]),
        YsButton.pill(
          icon: _copied ? YsIcon.check : YsIcon.copy,
          label: _copied ? 'Copied' : 'Copy',
          onPressed: _copy,
          small: true,
        ),
      ]);
}
