import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'feed.dart';
import 'route_styles.dart';
import 'scope.dart';
import 'screens.dart';

/// Library: artifacts nav (All/Documents/Web + Images/Videos/Podcasts),
/// artifact rows, system files + reflections.
///
/// The nav is a row of section pickers (Artifacts / Media / System files /
/// Reflections) above the list; the artifact detail and the system-file
/// Markdown editor open as dialogs.
class HermuseLibrary extends StatefulComponent {
  const HermuseLibrary({required this.instance, super.key});

  final HermesInstance instance;

  @override
  State<HermuseLibrary> createState() => _HermuseLibraryState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseRouteStyles,
    css('.hermuse-lib-nav').styles(
      display: .flex,
      flexDirection: .row,
      flexWrap: .wrap,
      gap: .all(8.px),
    ),
    css('.hermuse-lib-navitem').styles(
      height: 36.px,
      padding: .symmetric(horizontal: 16.px),
      radius: .circular(YsRadius.pill.px),
      display: .inlineFlex,
      alignItems: .center,
      color: .variable('--content-muted'),
      backgroundColor: .variable('--neutral-ambient'),
      cursor: .pointer,
      border: .none,
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
    ),
    css('.hermuse-lib-navitem-on').styles(
      color: .variable('--content'),
      backgroundColor: .variable('--neutral-film'),
    ),
    css('.hermuse-lib-row').styles(
      width: 100.percent,
      padding: .symmetric(vertical: 12.px, horizontal: 12.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(12.px),
      color: .variable('--content'),
      backgroundColor: Colors.transparent,
      cursor: .pointer,
      border: .none,
      textAlign: .left,
    ),
    css('.hermuse-lib-row:hover')
        .styles(backgroundColor: .variable('--neutral-film')),
    css('.hermuse-lib-icon').styles(
      width: 40.px,
      height: 40.px,
      radius: .circular(YsRadius.row.px),
      display: .flex,
      justifyContent: .center,
      alignItems: .center,
      color: .variable('--content-muted'),
      backgroundColor: .variable('--neutral-ambient'),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-lib-body').styles(
      flex: .grow(1),
      display: .flex,
      flexDirection: .column,
      gap: .all(2.px),
      raw: {'min-width': '0'},
    ),
    css('.hermuse-lib-title').styles(
      fontSize: 15.px,
      lineHeight: 20.px,
      fontWeight: .w600,
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap'},
    ),
    css('.hermuse-lib-sub').styles(
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap'},
    ),
    css('.hermuse-lib-left').styles(textAlign: .left),
    css('.hermuse-lib-file').styles(
      width: 100.percent,
      padding: .symmetric(vertical: 12.px, horizontal: 12.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(12.px),
      color: .variable('--content'),
      backgroundColor: Colors.transparent,
      cursor: .pointer,
      border: .none,
      textAlign: .left,
      fontSize: 15.px,
      lineHeight: 22.px,
      fontWeight: .w500,
    ),
    css('.hermuse-lib-file:hover')
        .styles(backgroundColor: .variable('--neutral-film')),
    css('.hermuse-lib-reflection').styles(
      padding: .symmetric(vertical: 16.px, horizontal: 16.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(8.px),
      backgroundColor: .variable('--paper'),
    ),
    css('.hermuse-lib-reflection-date').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
    ),
    css('.hermuse-lib-reflection-body').styles(
      margin: .zero,
      fontSize: 15.px,
      lineHeight: 24.px,
      color: .variable('--content-muted'),
      raw: {'white-space': 'pre-wrap', 'overflow-wrap': 'break-word'},
    ),
  ];
}

enum _LibrarySection { artifacts, media, systemFiles, reflections }

class _HermuseLibraryState extends State<HermuseLibrary> {
  var _section = _LibrarySection.artifacts;
  var _kindFilter = ''; // '' = all, else artifact kind.
  String? _detailId;
  String? _editingFile;

  @override
  Component build(BuildContext context) => HermusePluginGate(
    instance: component.instance,
    title: 'Library',
    child: HermuseWatch(
      provider: artifactsProvider(component.instance.id),
      builder: (context, artifacts) => _body(context, artifacts),
    ),
  );

  Component _body(BuildContext context, AsyncValue<List<Artifact>> artifacts) {
    final all = artifacts.value ?? const <Artifact>[];
    final detailId = _detailId;
    final detail = detailId == null
        ? null
        : all.where((row) => row.id == detailId).firstOrNull;
    return div(classes: 'hermuse-route', [
      div(classes: 'hermuse-route-column hermuse-route-wide', [
        div(classes: 'hermuse-route-head', [
          h1(classes: 'hermuse-route-title', [
            .text(switch (_section) {
              _LibrarySection.artifacts =>
                _kindFilter.isEmpty ? 'All artifacts' : _kindLabel(_kindFilter),
              _LibrarySection.media =>
                _kindFilter.isEmpty ? 'Media' : _kindLabel(_kindFilter),
              _LibrarySection.systemFiles => 'System files',
              _LibrarySection.reflections => 'Reflections',
            }),
          ]),
        ]),
        div(classes: 'hermuse-lib-nav', [
          _navButton(_LibrarySection.artifacts, 'Artifacts', ''),
          _navButton(_LibrarySection.artifacts, 'Documents', 'document'),
          _navButton(_LibrarySection.artifacts, 'Web artifacts', 'web'),
          _navButton(_LibrarySection.media, 'Images', 'image'),
          _navButton(_LibrarySection.media, 'Videos', 'video'),
          _navButton(_LibrarySection.media, 'Podcasts', 'podcast'),
          _navButton(_LibrarySection.systemFiles, 'System files', ''),
          _navButton(_LibrarySection.reflections, 'Reflections', ''),
        ]),
        switch (_section) {
          _LibrarySection.artifacts ||
          _LibrarySection.media => _artifactList(context, artifacts, all),
          _LibrarySection.systemFiles => _SystemFiles(
            instanceId: component.instance.id,
            onEdit: (name) => setState(() => _editingFile = name),
          ),
          _LibrarySection.reflections => _Reflections(
            instanceId: component.instance.id,
          ),
        },
      ]),
      if (detail != null)
        YsDialog(
          title: detail.title,
          onClose: () => setState(() => _detailId = null),
          child: .fragment([
            p(classes: 'hermuse-goals-event-at', [
              .text(
                [
                  _kindLabel(detail.kind),
                  if (detail.createdAt.isNotEmpty) detail.createdAt,
                  if (detail.size > 0) _formatSize(detail.size),
                ].join(' · '),
              ),
            ]),
            if (detail.tags.isNotEmpty)
              p(classes: 'hermuse-goals-event-at', [
                .text(detail.tags.join(' · ')),
              ]),
            p(classes: 'hermuse-card-body hermuse-lib-left', [
              .text(detail.file),
            ]),
          ]),
        ),
      if (_editingFile case final name?)
        _SystemFileEditor(
          instanceId: component.instance.id,
          name: name,
          onClose: () => setState(() => _editingFile = null),
        ),
    ]);
  }

  Component _navButton(_LibrarySection section, String label, String kind) {
    final selected = _section == section && _kindFilter == kind;
    return YsPressable(
      onPressed: () => setState(() {
        _section = section;
        _kindFilter = kind;
      }),
      label: label,
      classes: selected
          ? 'hermuse-lib-navitem hermuse-lib-navitem-on'
          : 'hermuse-lib-navitem',
      builder: (context, press) => span([.text(label)]),
    );
  }

  Component _artifactList(
    BuildContext context,
    AsyncValue<List<Artifact>> artifacts,
    List<Artifact> all,
  ) {
    if (artifacts.isLoading && artifacts.value == null) {
      return p(classes: 'hermuse-route-sub', [.text('Loading artifacts…')]);
    }
    if (artifacts.hasError && artifacts.value == null) {
      return p(classes: 'hermuse-route-error', [
        .text('Artifacts failed: ${artifacts.error}'),
      ]);
    }
    final rows = [
      for (final artifact in all)
        if (_kindFilter.isEmpty || artifact.kind == _kindFilter) artifact,
    ];
    if (rows.isEmpty) {
      return div(classes: 'hermuse-route-empty', [
        YsIconView(YsIcon.library, size: 26),
        p(classes: 'hermuse-route-empty-title', [.text('No artifacts yet')]),
        p(classes: 'hermuse-route-empty-body', [
          .text('Ask your Hermes to build something for you.'),
        ]),
      ]);
    }
    return div(classes: 'hermuse-route-section', [
      for (final artifact in rows)
        YsPressable(
          key: ValueKey(artifact.id),
          onPressed: () => setState(() => _detailId = artifact.id),
          label: 'Open ${artifact.title}',
          classes: 'hermuse-lib-row',
          builder: (context, press) => .fragment([
            div(classes: 'hermuse-lib-icon', [
              YsIconView(_kindIcon(artifact.kind), size: 18),
            ]),
            div(classes: 'hermuse-lib-body', [
              span(classes: 'hermuse-lib-title', [.text(artifact.title)]),
              span(classes: 'hermuse-lib-sub', [
                .text(
                  [
                    _kindLabel(artifact.kind),
                    if (artifact.createdAt.isNotEmpty) artifact.createdAt,
                  ].join(' · '),
                ),
              ]),
            ]),
          ]),
        ),
    ]);
  }

  static String _kindLabel(String kind) => switch (kind) {
    'document' => 'Documents',
    'web' => 'Web artifacts',
    'image' => 'Images',
    'video' => 'Videos',
    'podcast' => 'Podcasts',
    'other' => 'Other',
    '' => 'All artifacts',
    _ => kind,
  };

  static YsIcon _kindIcon(String kind) => switch (kind) {
    'web' => YsIcon.webSearch,
    'image' => YsIcon.ideas,
    'video' => YsIcon.upcoming,
    'podcast' => YsIcon.mic,
    _ => YsIcon.library,
  };

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// System files list: the plugin allow-list (preferences served separately).
class _SystemFiles extends StatelessComponent {
  const _SystemFiles({required this.instanceId, required this.onEdit});

  final String instanceId;
  final ValueChanged<String> onEdit;

  @override
  Component build(BuildContext context) =>
      div(classes: 'hermuse-route-section', [
        for (final name in hermuseManagedFiles)
          YsPressable(
            key: ValueKey(name),
            onPressed: () => onEdit(name),
            label: 'Edit $name',
            classes: 'hermuse-lib-file',
            builder: (context, press) => span([.text(name)]),
          ),
        p(classes: 'hermuse-route-sub', [
          .text(
            'SOUL, USER, MEMORY and AGENTS live in the Hermes dashboard file '
            'browser; the plugin exposes the files Hermuse manages.',
          ),
        ]),
      ]);
}

/// One managed system file in a Markdown editor dialog.
class _SystemFileEditor extends StatefulComponent {
  const _SystemFileEditor({
    required this.instanceId,
    required this.name,
    required this.onClose,
  });

  final String instanceId;
  final String name;
  final VoidCallback onClose;

  @override
  State<_SystemFileEditor> createState() => _SystemFileEditorState();
}

class _SystemFileEditorState extends State<_SystemFileEditor> {
  var _draft = '';
  var _loaded = false;
  var _busy = false;
  String? _error;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: systemFileProvider(component.instanceId, component.name),
    builder: (context, file) {
      final content = file.value?.content;
      if (!_loaded && content != null) {
        _loaded = true;
        _draft = content;
      }
      return YsDialog(
        title: component.name,
        onClose: component.onClose,
        wide: true,
        child: .fragment([
          if (file.isLoading && file.value == null)
            p(classes: 'hermuse-route-sub', [.text('Loading…')])
          else if (file.hasError && file.value == null)
            p(classes: 'hermuse-route-error', [.text('${file.error}')])
          else
            YsTextBox(
              value: _draft,
              onChanged: (v) => setState(() => _draft = v),
              label: component.name,
            ),
          if (_error case final error?)
            p(classes: 'hermuse-route-error', [.text(error)]),
        ]),
        actions: [
          YsButton.neutral(label: 'Close', onPressed: component.onClose),
          YsButton.primary(
            label: _busy ? 'Saving…' : 'Save',
            onPressed: _busy || file.value == null
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await context.container
                          .read(
                            systemFileProvider(
                              component.instanceId,
                              component.name,
                            ).notifier,
                          )
                          .save(_draft);
                      if (mounted) component.onClose();
                    } on Object catch (e) {
                      if (mounted) setState(() => _error = '$e');
                    }
                    if (mounted) setState(() => _busy = false);
                  },
          ),
        ],
      );
    },
  );
}

/// Reflections list, newest first.
class _Reflections extends StatelessComponent {
  const _Reflections({required this.instanceId});

  final String instanceId;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: reflectionsProvider(instanceId),
    builder: (context, reflections) {
      final all = reflections.value ?? const <Reflection>[];
      if (reflections.isLoading && reflections.value == null) {
        return p(classes: 'hermuse-route-sub', [.text('Loading reflections…')]);
      }
      if (reflections.hasError && reflections.value == null) {
        return p(classes: 'hermuse-route-error', [
          .text('Reflections failed: ${reflections.error}'),
        ]);
      }
      if (all.isEmpty) {
        return div(classes: 'hermuse-route-empty', [
          YsIconView(YsIcon.upcoming, size: 26),
          p(classes: 'hermuse-route-empty-title', [
            .text('No reflections yet'),
          ]),
          p(classes: 'hermuse-route-empty-body', [
            .text('The nightly reflection appears here each morning.'),
          ]),
        ]);
      }
      return div(classes: 'hermuse-route-section', [
        for (final reflection in all)
          div(
            key: ValueKey(reflection.date),
            classes: 'hermuse-lib-reflection',
            [
              p(classes: 'hermuse-lib-reflection-date', [
                .text(reflection.date),
              ]),
              p(classes: 'hermuse-lib-reflection-body', [
                .text(reflection.body),
              ]),
            ],
          ),
      ]);
    },
  );
}
