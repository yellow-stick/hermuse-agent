import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'plugin_gate.dart';
import 'route.dart';
import 'widgets.dart';

/// Library: artifact filters (Artifacts / Documents / Web / Images / Videos /
/// Podcasts), system files editor and reflections.
final class LibraryScreen extends StatelessWidget {
  const LibraryScreen({required this.instance, super.key});

  final HermesInstance instance;

  @override
  Widget build(BuildContext context) => PluginGate(
    instance: instance,
    title: 'Library',
    child: _Library(instanceId: instance.id),
  );
}

enum _Section { artifacts, systemFiles, reflections }

/// Nav pill → (section, artifact kind filter).
const _nav = [
  ('Artifacts', _Section.artifacts, ''),
  ('Documents', _Section.artifacts, 'document'),
  ('Web artifacts', _Section.artifacts, 'web'),
  ('Images', _Section.artifacts, 'image'),
  ('Videos', _Section.artifacts, 'video'),
  ('Podcasts', _Section.artifacts, 'podcast'),
  ('System files', _Section.systemFiles, ''),
  ('Reflections', _Section.reflections, ''),
];

String _kindLabel(String kind) => switch (kind) {
  'document' => 'Documents',
  'web' => 'Web artifacts',
  'image' => 'Images',
  'video' => 'Videos',
  'podcast' => 'Podcasts',
  'other' => 'Other',
  '' => 'All artifacts',
  _ => kind,
};

YsIcon _kindIcon(String kind) => switch (kind) {
  'web' => YsIcon.webSearch,
  'image' => YsIcon.ideas,
  'video' => YsIcon.upcoming,
  'podcast' => YsIcon.mic,
  _ => YsIcon.library,
};

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

final class _Library extends ConsumerStatefulWidget {
  const _Library({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_Library> createState() => _LibraryState();
}

final class _LibraryState extends ConsumerState<_Library> {
  var _section = _Section.artifacts;
  var _kind = '';
  String? _detailId;
  String? _editing;

  @override
  Widget build(BuildContext context) {
    final artifacts = ref.watch(artifactsProvider(widget.instanceId));
    final all = artifacts.value ?? const <Artifact>[];
    final detail = all.where((a) => a.id == _detailId).firstOrNull;
    final editing = _editing;
    return Stack(
      children: [
        HermuseRoute(
          wide: true,
          title: switch (_section) {
            _Section.artifacts => _kindLabel(_kind),
            _Section.systemFiles => 'System files',
            _Section.reflections => 'Reflections',
          },
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, section, kind) in _nav)
                  ProductPill(
                    label: label,
                    on: _section == section && _kind == kind,
                    onPressed: () => setState(() {
                      _section = section;
                      _kind = kind;
                    }),
                  ),
              ],
            ),
            switch (_section) {
              _Section.artifacts => _artifactList(artifacts, all),
              _Section.systemFiles => _SystemFiles(
                onEdit: (name) => setState(() => _editing = name),
              ),
              _Section.reflections => _Reflections(
                instanceId: widget.instanceId,
              ),
            },
          ],
        ),
        if (detail != null)
          Positioned.fill(
            child: YsDialog(
              title: detail.title,
              onClose: () => setState(() => _detailId = null),
              child: _ArtifactDetail(artifact: detail),
            ),
          ),
        if (editing != null)
          Positioned.fill(
            child: _SystemFileEditor(
              instanceId: widget.instanceId,
              name: editing,
              onClose: () => setState(() => _editing = null),
            ),
          ),
      ],
    );
  }

  Widget _artifactList(
    AsyncValue<List<Artifact>> artifacts,
    List<Artifact> all,
  ) {
    if (artifacts.isLoading && artifacts.value == null) {
      return const HermuseRouteSub('Loading artifacts…');
    }
    if (artifacts.hasError && artifacts.value == null) {
      return HermuseRouteError('Artifacts failed: ${artifacts.error}');
    }
    final rows = [
      for (final artifact in all)
        if (_kind.isEmpty || artifact.kind == _kind) artifact,
    ];
    if (rows.isEmpty) {
      return const HermuseRouteEmpty(
        icon: YsIcon.library,
        title: 'No artifacts yet',
        body: 'Ask your Hermes to build something for you.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final artifact in rows)
          _ArtifactRow(
            key: ValueKey(artifact.id),
            artifact: artifact,
            onPressed: () => setState(() => _detailId = artifact.id),
          ),
      ],
    );
  }
}

final class _ArtifactRow extends StatelessWidget {
  const _ArtifactRow({
    required this.artifact,
    required this.onPressed,
    super.key,
  });

  final Artifact artifact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: onPressed,
      semanticLabel: 'Open ${artifact.title}',
      builder: (context, state) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: YsLayout.activityTileSize,
              height: YsLayout.activityTileSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.paperColor,
                borderRadius: BorderRadius.circular(YsRadius.option),
              ),
              child: YsIconWidget(
                _kindIcon(artifact.kind),
                size: 18,
                color: palette.contentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artifact.title,
                    style: YsType.navRow.flutter.copyWith(
                      color: palette.contentColor,
                    ),
                  ),
                  Text(
                    [
                      _kindLabel(artifact.kind),
                      if (artifact.createdAt.isNotEmpty) artifact.createdAt,
                    ].join(' · '),
                    style: YsType.small.flutter.copyWith(
                      color: palette.contentMutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ArtifactDetail extends StatelessWidget {
  const _ArtifactDetail({required this.artifact});

  final Artifact artifact;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final subtle = YsType.caption.flutter.copyWith(
      color: palette.contentSubtleColor,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          [
            _kindLabel(artifact.kind),
            if (artifact.createdAt.isNotEmpty) artifact.createdAt,
            if (artifact.size > 0) _formatSize(artifact.size),
          ].join(' · '),
          style: subtle,
        ),
        if (artifact.tags.isNotEmpty)
          Text(artifact.tags.join(' · '), style: subtle),
        const SizedBox(height: 12),
        Text(
          artifact.file,
          style: YsType.body.flutter.copyWith(color: palette.contentColor),
        ),
      ],
    );
  }
}

/// The plugin's managed files (Hermes' own SOUL/USER/MEMORY/AGENTS are
/// edited from the Hermes dashboard).
final class _SystemFiles extends StatelessWidget {
  const _SystemFiles({required this.onEdit});

  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in hermuseManagedFiles)
          YsPressable(
            key: ValueKey(name),
            onPressed: () => onEdit(name),
            semanticLabel: 'Edit $name',
            builder: (context, state) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                name,
                style: YsType.navRow.flutter.copyWith(
                  color: palette.contentColor,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const HermuseRouteSub(
          'SOUL, USER, MEMORY and AGENTS live in the Hermes dashboard file '
          'browser; the plugin exposes the files Hermuse manages.',
        ),
      ],
    );
  }
}

final class _SystemFileEditor extends ConsumerStatefulWidget {
  const _SystemFileEditor({
    required this.instanceId,
    required this.name,
    required this.onClose,
  });

  final String instanceId;
  final String name;
  final VoidCallback onClose;

  @override
  ConsumerState<_SystemFileEditor> createState() => _SystemFileEditorState();
}

final class _SystemFileEditorState extends ConsumerState<_SystemFileEditor> {
  final _draft = TextEditingController();
  var _loaded = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(systemFileProvider(widget.instanceId, widget.name).notifier)
          .save(_draft.text);
      if (mounted) widget.onClose();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final file = ref.watch(systemFileProvider(widget.instanceId, widget.name));
    final content = file.value?.content;
    if (!_loaded && content != null) {
      _loaded = true;
      _draft.text = content;
    }
    return YsDialog(
      title: widget.name,
      wide: true,
      onClose: widget.onClose,
      actions: [
        YsButton.neutral(label: 'Close', onPressed: widget.onClose),
        YsButton.primary(
          label: _busy ? 'Saving…' : 'Save',
          onPressed: _busy || file.value == null
              ? null
              : () => unawaited(_save()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (file.isLoading && file.value == null)
            const HermuseRouteSub('Loading…')
          else if (file.hasError && file.value == null)
            HermuseRouteError('${file.error}')
          else
            YsTextBox(controller: _draft, semanticLabel: widget.name),
          if (_error case final error?) HermuseRouteError(error),
        ],
      ),
    );
  }
}

final class _Reflections extends ConsumerWidget {
  const _Reflections({required this.instanceId});

  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final reflections = ref.watch(reflectionsProvider(instanceId));
    final all = reflections.value ?? const <Reflection>[];
    if (reflections.isLoading && reflections.value == null) {
      return const HermuseRouteSub('Loading reflections…');
    }
    if (reflections.hasError && reflections.value == null) {
      return HermuseRouteError('Reflections failed: ${reflections.error}');
    }
    if (all.isEmpty) {
      return const HermuseRouteEmpty(
        icon: YsIcon.upcoming,
        title: 'No reflections yet',
        body: 'The nightly reflection appears here each morning.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final reflection in all)
          Padding(
            key: ValueKey(reflection.date),
            padding: const EdgeInsets.only(bottom: 12),
            child: ProductCard(
              children: [
                Text(
                  reflection.date,
                  style: YsType.label.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                ),
                Text(
                  reflection.body,
                  style: YsType.agentBubble.flutter.copyWith(
                    color: palette.contentColor,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
