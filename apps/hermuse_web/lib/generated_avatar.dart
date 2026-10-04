import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hermes_client/hermes_client.dart' show HermesException;
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:riverpod/riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'scope.dart';
import 'screens.dart';

/// What a failed generation action says to a person: the server's detail
/// ([hermesReason]) or the validation message, never a raw exception.
String hermuseMediaErrorText(Object error) => switch (error) {
  HermesException() => hermesReason(error),
  AgentWriteException(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => 'Something went wrong. Please try again.',
};

/// An image URL for [bytes]: a blob URL in the browser (revoke it with
/// [_revokeImageUrl]), a data URL elsewhere (component tests on the VM).
String _imageUrl(Uint8List bytes, String type) => kIsWeb
    ? web.URL.createObjectURL(
        web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type)),
      )
    : 'data:$type;base64,${base64Encode(bytes)}';

void _revokeImageUrl(String? url) {
  if (kIsWeb && url != null && url.startsWith('blob:')) {
    web.URL.revokeObjectURL(url);
  }
}

/// One image loaded from the plugin, shown through an object URL.
///
/// [want] a new key starts loading it while the previous image stays on
/// screen; the new URL replaces it (and the old one is revoked) only once
/// its bytes arrived, so a state change never flickers.
final class _ImageSlot {
  _ImageSlot(this._type, this._changed);

  final String _type;
  final void Function() _changed;
  String? _wanted;
  bool _disposed = false;

  /// The URL of the image on screen.
  String? src;

  /// Whether the last wanted image failed to load.
  bool failed = false;

  void want(String? key, Future<Uint8List> Function() fetch) {
    if (key == _wanted) return;
    _wanted = key;
    failed = false;
    if (key == null) {
      _revokeImageUrl(src);
      src = null;
      return;
    }
    unawaited(
      Future.sync(fetch).then(
        (bytes) {
          if (_disposed || _wanted != key) return;
          final old = src;
          src = _imageUrl(bytes, _type);
          _revokeImageUrl(old);
          _changed();
        },
        onError: (Object _) {
          if (_disposed || _wanted != key) return;
          failed = true;
          _changed();
        },
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _revokeImageUrl(src);
    src = null;
  }
}

/// A generated (custom) agent's portrait, animated with its state clips.
///
/// The clip of [customAvatarState] for [chat] is a `<source>` limited to
/// `prefers-reduced-motion: no-preference`; the `<img>` is the static
/// portrait, so reduced motion keeps the portrait. Without a portrait (or
/// while it loads the first time) the bundled stand-in shows.
class HermuseCustomAvatarImage extends StatelessComponent {
  const HermuseCustomAvatarImage({
    required this.instanceId,
    required this.profile,
    required this.size,
    this.chat,
    this.alt = '',
    super.key,
  });

  final String instanceId;
  final String profile;
  final double size;
  final ChatState? chat;
  final String alt;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: agentAvatarProvider(instanceId, profile: profile),
    builder: (context, avatar) => _CustomAvatarPicture(
      instanceId: instanceId,
      profile: profile,
      avatar: avatar.value,
      chat: chat,
      size: size,
      alt: alt,
    ),
  );
}

class _CustomAvatarPicture extends StatefulComponent {
  const _CustomAvatarPicture({
    required this.instanceId,
    required this.profile,
    required this.avatar,
    required this.chat,
    required this.size,
    required this.alt,
  });

  final String instanceId;
  final String profile;
  final Avatar? avatar;
  final ChatState? chat;
  final double size;
  final String alt;

  @override
  State<_CustomAvatarPicture> createState() => _CustomAvatarPictureState();
}

class _CustomAvatarPictureState extends State<_CustomAvatarPicture> {
  late final _portrait = _ImageSlot('image/jpeg', _changed);
  late final _clip = _ImageSlot('image/webp', _changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  AgentAvatarState get _notifier => context.readProvider(
    agentAvatarProvider(
      component.instanceId,
      profile: component.profile,
    ).notifier,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateComponent(covariant _CustomAvatarPicture oldComponent) {
    super.didUpdateComponent(oldComponent);
    _sync();
  }

  void _sync() {
    final avatar = component.avatar;
    final version = avatar?.updatedAt?.toIso8601String() ?? '';
    final portrait = avatar?.portraitUrl;
    _portrait.want(
      portrait == null ? null : '$portrait#$version',
      () => _notifier.portraitBytes(),
    );
    // The browser picks the clip only when motion is welcome (`<source
    // media>`), so the state is computed as if animation were allowed.
    final state = avatar == null || portrait == null
        ? null
        : customAvatarState(
            avatar.states.keys,
            chat: component.chat,
            animate: true,
          );
    _clip.want(
      state == null ? null : '${avatar!.states[state]}#$version',
      () => _notifier.stateBytes(state!),
    );
  }

  @override
  void dispose() {
    _portrait.dispose();
    _clip.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) => .element(
    tag: 'picture',
    children: [
      if (_clip.src case final clip?)
        source(
          attributes: {
            'media': '(prefers-reduced-motion: no-preference)',
            'srcset': clip,
          },
        ),
      img(
        classes: 'ys-avatar-img',
        src: _portrait.src ?? '/images/${AgentAvatar.custom.assetPath}',
        alt: component.alt,
        width: component.size.round(),
        height: component.size.round(),
        attributes: {'decoding': 'async'},
      ),
    ],
  );
}

/// A portrait candidate of a generation run (JPEG from the plugin).
class _CandidateImage extends StatefulComponent {
  const _CandidateImage({
    required this.instanceId,
    required this.profile,
    required this.url,
  });

  final String instanceId;
  final String profile;
  final String url;

  @override
  State<_CandidateImage> createState() => _CandidateImageState();
}

class _CandidateImageState extends State<_CandidateImage> {
  late final _image = _ImageSlot('image/jpeg', () {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _image.want(
      component.url,
      () => context
          .readProvider(
            agentAvatarProvider(
              component.instanceId,
              profile: component.profile,
            ).notifier,
          )
          .candidateBytes(component.url),
    );
  }

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    if (_image.failed) {
      return span(classes: 'hermuse-avatar-gen-candidate-missing', [
        .text('Could not load'),
      ]);
    }
    final src = _image.src;
    if (src == null) {
      return span(classes: 'hermuse-avatar-gen-candidate-missing', []);
    }
    return img(classes: 'hermuse-avatar-gen-candidate-img', src: src, alt: '');
  }
}

const _stateLabels = {
  'idle': 'Idle',
  'thinking': 'Thinking',
  'replying': 'Replying',
  'working': 'Working',
};

String _stateStatusLabel(AvatarStateStatus status) => switch (status) {
  AvatarStateStatus.queued => 'Queued',
  AvatarStateStatus.running => 'Generating…',
  AvatarStateStatus.done => 'Done',
  AvatarStateStatus.failed => 'Failed',
};

/// The agent editor's Generate view: description → portrait candidates →
/// pick one → animate its states, against the agent's [profile].
///
/// A new agent has no profile yet: the first Generate asks
/// [onEnsureProfile] to create it. Picking a candidate selects it on the
/// server, then [onPicked] saves the agent with the generated portrait.
/// Without an image service only the setup line shows, with
/// [onOpenSettings].
class HermuseAvatarGenerator extends StatefulComponent {
  const HermuseAvatarGenerator({
    required this.instanceId,
    required this.profile,
    required this.onEnsureProfile,
    required this.onPicked,
    required this.onOpenSettings,
    this.disabled = false,
    super.key,
  });

  final String instanceId;

  /// The agent's profile; null until a new agent was created.
  final String? profile;

  /// Creates the agent's profile; null when it could not (the editor shows
  /// why).
  final Future<String?> Function() onEnsureProfile;
  final Future<void> Function() onPicked;
  final VoidCallback? onOpenSettings;
  final bool disabled;

  @override
  State<HermuseAvatarGenerator> createState() => _HermuseAvatarGeneratorState();

  @css
  static List<StyleRule> get styles => [
    css(
      '.hermuse-avatar-gen',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.md.px)),
    css('.hermuse-avatar-gen-row').styles(
      display: .flex,
      flexWrap: .wrap,
      alignItems: .center,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-avatar-gen-line').styles(
      margin: .zero,
      color: .variable('--content-muted'),
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
    ),
    css('.hermuse-avatar-gen-error').styles(
      margin: .zero,
      color: .variable('--error'),
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
    ),
    css('.hermuse-avatar-gen-grid').styles(
      display: .grid,
      gap: .all(YsSpace.sm.px),
      raw: {'grid-template-columns': 'repeat(4, minmax(0, 1fr))'},
    ),
    css('.hermuse-avatar-gen-candidate').styles(
      padding: .zero,
      overflow: .hidden,
      border: .all(color: .variable('--line'), width: ysHairline.px),
      radius: .circular(YsRadius.option.px),
      cursor: .pointer,
      backgroundColor: .variable('--avatar-surface'),
      raw: {'aspect-ratio': '1'},
    ),
    css(
      '.hermuse-avatar-gen-candidate[aria-pressed="true"], .hermuse-avatar-gen-candidate:focus-visible',
    ).styles(
      raw: {
        'outline': '2px solid var(--primary)',
        'outline-offset': '${YsSpace.xxs}px',
      },
    ),
    css('.hermuse-avatar-gen-candidate-img').styles(
      display: .block,
      width: 100.percent,
      height: 100.percent,
      raw: {'object-fit': 'cover'},
    ),
    css('.hermuse-avatar-gen-candidate-missing').styles(
      display: .flex,
      width: 100.percent,
      height: 100.percent,
      justifyContent: .center,
      alignItems: .center,
      color: .variable('--content-muted'),
      fontSize: YsType.caption.size.px,
    ),
    css('.hermuse-avatar-gen-states').styles(
      margin: .zero,
      padding: .zero,
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.xxs.px),
      listStyle: .none,
    ),
    css('.hermuse-avatar-gen-state').styles(
      display: .flex,
      justifyContent: .spaceBetween,
      gap: .all(YsSpace.md.px),
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
    ),
    css('.hermuse-avatar-gen-state-status')
        .styles(color: .variable('--content-muted')),
    css('.hermuse-avatar-gen-state-failed .hermuse-avatar-gen-state-status')
        .styles(color: .variable('--error')),
    css('.hermuse-avatar-gen-animate').styles(
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.sm.px),
      flex: .grow(1),
    ),
  ];
}

class _HermuseAvatarGeneratorState extends State<HermuseAvatarGenerator> {
  String _description = '';
  bool _busy = false;
  String? _error;

  /// Candidate picked in this editor (the server does not say which).
  int? _picked;

  AgentAvatarState _notifier(String profile) => context.readProvider(
    agentAvatarProvider(component.instanceId, profile: profile).notifier,
  );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = hermuseMediaErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() => _run(() async {
    final profile = component.profile ?? await component.onEnsureProfile();
    if (profile == null) return;
    _picked = null;
    await _notifier(profile).generatePortraits(_description);
  });

  Future<void> _pick(String profile, int candidate) => _run(() async {
    await _notifier(profile).select(candidate);
    if (mounted) setState(() => _picked = candidate);
    await component.onPicked();
  });

  Future<void> _animate(String profile, List<String>? states) =>
      _run(() async => _notifier(profile).animate(states: states));

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: mediaConfigProvider(component.instanceId),
    builder: (context, config) => HermuseWatch(
      provider: mediaStatusProvider(component.instanceId),
      builder: (context, status) {
        final configValue = config.value;
        if (configValue == null) {
          return div(classes: 'hermuse-avatar-gen', [
            if (config.hasError)
              p(
                classes: 'hermuse-avatar-gen-error',
                attributes: {'role': 'alert'},
                [
                  .text(
                    'Could not check the image service: '
                    '${hermuseMediaErrorText(config.error!)}',
                  ),
                ],
              )
            else
              p(
                classes: 'hermuse-avatar-gen-line',
                attributes: {'role': 'status'},
                [.text('Checking the image service…')],
              ),
          ]);
        }
        if (!configValue.configured || status.value?.configured == false) {
          return div(classes: 'hermuse-avatar-gen', [
            p(classes: 'hermuse-avatar-gen-line', [
              .text(
                'Portrait generation needs an image service. Set it up in '
                'Settings → Image generation.',
              ),
            ]),
            if (component.onOpenSettings case final open?)
              div(classes: 'hermuse-avatar-gen-row', [
                YsButton.neutral(label: 'Open Settings', onPressed: open),
              ]),
          ]);
        }
        final profile = component.profile;
        if (profile == null) {
          return _view(context, profile: null, avatar: null, status: null);
        }
        return HermuseWatch(
          provider: agentAvatarProvider(component.instanceId, profile: profile),
          builder: (context, avatar) => _view(
            context,
            profile: profile,
            avatar: avatar,
            status: status.value,
          ),
        );
      },
    ),
  );

  Component _view(
    BuildContext context, {
    required String? profile,
    required AsyncValue<Avatar>? avatar,
    required MediaStatus? status,
  }) {
    final value = avatar?.value;
    final job = value?.job;
    final running = job?.running ?? false;
    final locked = component.disabled || _busy;
    final portraitJob = job?.kind == AvatarJobKind.portrait ? job : null;
    final animateJob = job?.kind == AvatarJobKind.animate ? job : null;
    final candidates = portraitJob?.status == AvatarJobStatus.done
        ? portraitJob!.candidates
        : const <String>[];
    final failedStates = [
      if (animateJob != null && !animateJob.running)
        for (final MapEntry(:key, :value) in animateJob.states.entries)
          if (value == AvatarStateStatus.failed) key,
    ];
    final allClips = customAvatarStates.every(
      (state) => value?.states.containsKey(state) ?? false,
    );
    final toAnimate = failedStates.isNotEmpty
        ? failedStates
        : customAvatarStates;
    return div(classes: 'hermuse-avatar-gen', [
      YsField(
        label: 'Generate a portrait',
        child: YsTextBox(
          value: _description,
          label: 'Describe your agent',
          placeholder:
              'A cheerful plush fox with round glasses and a green scarf',
          minHeight: 80,
          onChanged: (text) => setState(() => _description = text),
        ),
      ),
      div(classes: 'hermuse-avatar-gen-row', [
        YsButton.primary(
          label: portraitJob?.running ?? false
              ? 'Generating…'
              : 'Generate portraits',
          onPressed: locked || running || _description.trim().isEmpty
              ? null
              : () => unawaited(_generate()),
        ),
      ]),
      if (portraitJob?.running ?? false)
        p(
          classes: 'hermuse-avatar-gen-line',
          attributes: {'role': 'status'},
          [.text('Generating portraits… about 15 seconds')],
        ),
      if (portraitJob case AvatarJob(
        status: AvatarJobStatus.failed,
        :final error,
      ))
        p(
          classes: 'hermuse-avatar-gen-error',
          attributes: {'role': 'alert'},
          [.text(error ?? 'The image service could not draw portraits.')],
        ),
      if (profile != null && candidates.isNotEmpty)
        YsField(
          label: 'Pick a portrait',
          child: div(classes: 'hermuse-avatar-gen-grid', [
            for (final (index, url) in candidates.indexed)
              YsPressable(
                key: ValueKey('candidate:$url'),
                label: 'Portrait ${index + 1}',
                classes: 'hermuse-avatar-gen-candidate',
                attributes: {'aria-pressed': '${_picked == index}'},
                onPressed: locked || running
                    ? null
                    : () => unawaited(_pick(profile, index)),
                builder: (context, press) => _CandidateImage(
                  instanceId: component.instanceId,
                  profile: profile,
                  url: url,
                ),
              ),
          ]),
        ),
      if (profile != null && value != null && value.hasPortrait)
        div(classes: 'hermuse-avatar-gen-row', [
          div(
            classes: 'ys-avatar',
            styles: Styles(width: 100.px, height: 100.px),
            [
              HermuseCustomAvatarImage(
                instanceId: component.instanceId,
                profile: profile,
                size: 100,
                alt: 'Generated portrait',
              ),
            ],
          ),
          div(classes: 'hermuse-avatar-gen-animate', [
            div(classes: 'hermuse-avatar-gen-row', [
              YsButton.neutral(
                label: failedStates.isNotEmpty
                    ? 'Retry failed animations'
                    : allClips
                    ? 'Animate again'
                    : 'Animate',
                onPressed: locked || running
                    ? null
                    : () => unawaited(
                        _animate(
                          profile,
                          failedStates.isNotEmpty ? failedStates : null,
                        ),
                      ),
              ),
              span(classes: 'hermuse-avatar-gen-line', [
                .text(animationCostLine(toAnimate, status)),
              ]),
            ]),
            if (animateJob != null) ...[
              ul(
                classes: 'hermuse-avatar-gen-states',
                attributes: {'aria-label': 'Animations'},
                [
                  for (final MapEntry(key: state, value: progress)
                      in animateJob.states.entries)
                    li(
                      classes: progress == AvatarStateStatus.failed
                          ? 'hermuse-avatar-gen-state hermuse-avatar-gen-state-failed'
                          : 'hermuse-avatar-gen-state',
                      [
                        span([.text(_stateLabels[state] ?? state)]),
                        span(classes: 'hermuse-avatar-gen-state-status', [
                          .text(_stateStatusLabel(progress)),
                        ]),
                      ],
                    ),
                ],
              ),
              if (animateJob.running)
                p(classes: 'hermuse-avatar-gen-line', [
                  .text(
                    'You can save the agent now; the animations keep going '
                    'on the server.',
                  ),
                ]),
              if (animateJob.error case final error? when !animateJob.running)
                p(
                  classes: 'hermuse-avatar-gen-error',
                  attributes: {'role': 'alert'},
                  [.text(error)],
                ),
            ],
          ]),
        ]),
      if (avatar != null && avatar.hasError)
        p(
          classes: 'hermuse-avatar-gen-error',
          attributes: {'role': 'status'},
          [.text(hermuseMediaErrorText(avatar.error!))],
        ),
      if (_error case final error?)
        p(
          classes: 'hermuse-avatar-gen-error',
          attributes: {'role': 'alert'},
          [.text(error)],
        ),
    ]);
  }
}
