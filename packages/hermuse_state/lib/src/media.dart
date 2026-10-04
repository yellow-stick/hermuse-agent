import 'dart:async';
import 'dart:typed_data';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart' show customAvatarStates;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'onboarding.dart' show restClientProvider;
import 'product.dart' show hermusePluginRoute;

part 'media.g.dart';

const _mediaRoute = '$hermusePluginRoute/media';
const _avatarRoute = '$hermusePluginRoute/avatar';

Duration? _noRetry(int retryCount, Object error) => null;

/// The image/video generation service the plugin drives (server-wide).
/// Shape: `{provider, endpoint, has_token, image_model, video_model,
/// feed_fallback, from_env}`.
final class MediaConfig {
  const MediaConfig({
    required this.provider,
    required this.endpoint,
    required this.hasToken,
    required this.imageModel,
    required this.videoModel,
    required this.feedFallback,
    required this.fromEnv,
  });

  factory MediaConfig.fromJson(Map<String, Object?> json) => MediaConfig(
    provider: json['provider'] as String? ?? 'contentflow',
    endpoint: json['endpoint'] as String? ?? '',
    hasToken: json['has_token'] == true,
    imageModel: json['image_model'] as String? ?? '',
    videoModel: json['video_model'] as String? ?? '',
    feedFallback: json['feed_fallback'] == true,
    fromEnv: json['from_env'] == true,
  );

  /// Only `contentflow` for now.
  final String provider;

  /// Base URL of the service; empty when generation is off.
  final String endpoint;

  /// Whether a token is stored (the token itself is never returned).
  final bool hasToken;
  final String imageModel;
  final String videoModel;

  /// Whether Feed posts without an image get a generated illustration.
  final bool feedFallback;

  /// Set by `HERMUSE_MEDIA_ENDPOINT` / `HERMUSE_MEDIA_TOKEN` on the server;
  /// those override what is saved here.
  final bool fromEnv;

  bool get configured => endpoint.isNotEmpty;
}

/// Reachability of the generation service. Shape: `{configured, reachable,
/// credits, video_cost, error}`.
final class MediaStatus {
  const MediaStatus({
    required this.configured,
    required this.reachable,
    this.credits,
    this.videoCost,
    this.error,
  });

  factory MediaStatus.fromJson(Map<String, Object?> json) => MediaStatus(
    configured: json['configured'] == true,
    reachable: json['reachable'] == true,
    credits: (json['credits'] as num?)?.toInt(),
    videoCost: (json['video_cost'] as num?)?.toInt(),
    error: json['error'] as String?,
  );

  final bool configured;
  final bool reachable;

  /// Credits left on the service's account, when it says.
  final int? credits;

  /// Credits one animation clip costs with the configured video model.
  final int? videoCost;

  /// Why the service is not reachable.
  final String? error;
}

/// Credits animating [states] costs, or null when the price is unknown.
int? animationCost(Iterable<String> states, MediaStatus? status) {
  final cost = status?.videoCost;
  return cost == null ? null : states.length * cost;
}

/// The cost line under Animate: `4 animations · 28 credits`, without the
/// price when it is unknown.
String animationCostLine(Iterable<String> states, MediaStatus? status) {
  final count = states.length;
  final animations = '$count animation${count == 1 ? '' : 's'}';
  final cost = animationCost(states, status);
  if (cost == null) return animations;
  return '$animations · $cost credit${cost == 1 ? '' : 's'}';
}

/// The generation service settings of [instanceId]'s server (stored by the
/// default profile, shared by every agent).
@Riverpod(name: 'mediaConfigProvider', retry: _noRetry)
class MediaConfigState extends _$MediaConfigState {
  @override
  Future<MediaConfig> build(String instanceId) async {
    final rest = await ref.watch(restClientProvider(instanceId).future);
    return MediaConfig.fromJson(await rest.getJson('$_mediaRoute/config'));
  }

  /// Saves the settings; an empty [endpoint] turns generation off. [token]
  /// null keeps the stored one, `''` clears it; null models and
  /// [feedFallback] keep their values. Refreshes [mediaStatusProvider].
  Future<MediaConfig> save({
    required String endpoint,
    String? token,
    String? imageModel,
    String? videoModel,
    bool? feedFallback,
  }) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final config = MediaConfig.fromJson(
      await rest.putJson('$_mediaRoute/config', {
        'endpoint': endpoint.trim(),
        'token': ?token,
        'image_model': ?imageModel,
        'video_model': ?videoModel,
        'feed_fallback': ?feedFallback,
      }),
    );
    if (ref.mounted) state = AsyncData(config);
    ref.invalidate(mediaStatusProvider(instanceId));
    return config;
  }
}

/// Whether the generation service answers, its credits and the price of
/// an animation clip (Settings' Test; the editor's cost line).
@Riverpod(name: 'mediaStatusProvider', retry: _noRetry)
class MediaStatusState extends _$MediaStatusState {
  @override
  Future<MediaStatus> build(String instanceId) async {
    final rest = await ref.watch(restClientProvider(instanceId).future);
    return MediaStatus.fromJson(await rest.getJson('$_mediaRoute/status'));
  }

  /// Probes the service again (the previous status stays the value while
  /// loading); throws what the probe throws.
  Future<MediaStatus> refresh() async {
    state = const AsyncLoading();
    try {
      final rest = await ref.read(restClientProvider(instanceId).future);
      final status = MediaStatus.fromJson(
        await rest.getJson('$_mediaRoute/status'),
      );
      if (ref.mounted) state = AsyncData(status);
      return status;
    } on Object catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      rethrow;
    }
  }
}

enum AvatarJobKind { portrait, animate }

enum AvatarJobStatus { running, done, failed }

enum AvatarStateStatus { queued, running, done, failed }

/// A generation run. Shape: `{id, kind, status, candidates: [url],
/// states: {state: status}, error, started_at, finished_at}`.
final class AvatarJob {
  const AvatarJob({
    required this.id,
    required this.kind,
    required this.status,
    this.candidates = const [],
    this.states = const {},
    this.error,
    this.startedAt,
    this.finishedAt,
  });

  factory AvatarJob.fromJson(Map<String, Object?> json) => AvatarJob(
    id: '${json['id']}',
    kind: AvatarJobKind.values.asNameMap()[json['kind']] ?? .portrait,
    status: AvatarJobStatus.values.asNameMap()[json['status']] ?? .failed,
    candidates: [
      for (final url in (json['candidates'] as List?) ?? const []) '$url',
    ],
    states: {
      for (final MapEntry(:key, :value)
          in ((json['states'] as Map?) ?? const {}).entries)
        '$key': AvatarStateStatus.values.asNameMap()[value] ?? .failed,
    },
    error: json['error'] as String?,
    startedAt: _time(json['started_at']),
    finishedAt: _time(json['finished_at']),
  );

  final String id;
  final AvatarJobKind kind;
  final AvatarJobStatus status;

  /// Portrait candidates (URLs for [AgentAvatarState.candidateBytes]); the
  /// index is what [AgentAvatarState.select] takes.
  final List<String> candidates;

  /// Per-state progress of an animation run, in generation order.
  final Map<String, AvatarStateStatus> states;
  final String? error;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get running => status == AvatarJobStatus.running;
}

/// A profile's generated portrait and animations. Shape:
/// `{portrait_url, states: {state: url}, job, updated_at}`.
final class Avatar {
  const Avatar({
    this.portraitUrl,
    this.states = const {},
    this.job,
    this.updatedAt,
  });

  factory Avatar.fromJson(Map<String, Object?> json) => Avatar(
    portraitUrl: json['portrait_url'] as String?,
    states: {
      for (final MapEntry(:key, :value)
          in ((json['states'] as Map?) ?? const {}).entries)
        '$key': '$value',
    },
    job: switch (json['job']) {
      final Map<String, Object?> job => AvatarJob.fromJson(job),
      _ => null,
    },
    updatedAt: _time(json['updated_at']),
  );

  /// Square portrait URL; null before a candidate was selected.
  final String? portraitUrl;

  /// Animated WebP URL of each generated state.
  final Map<String, String> states;

  /// The current or last generation run.
  final AvatarJob? job;
  final DateTime? updatedAt;

  bool get hasPortrait => portraitUrl != null;

  Avatar withJob(AvatarJob? job) => Avatar(
    portraitUrl: portraitUrl,
    states: states,
    job: job,
    updatedAt: updatedAt,
  );
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// How often a running avatar job is polled.
@Riverpod(keepAlive: true)
Duration avatarJobPollInterval(Ref ref) => const Duration(seconds: 3);

/// The generated portrait and animations of [profile] on [instanceId].
///
/// While a job runs it is polled every [avatarJobPollIntervalProvider] and
/// the avatar follows it (new clips appear as they finish); polling stops
/// when the job ends or the provider is disposed. A failed poll keeps the
/// avatar as the error's value and polls again. Actions throw
/// [HermesHttpError] with the server's reason ([hermesReason]): 409 while
/// a job runs, 422 without a portrait, 502 when the service refused.
@Riverpod(name: 'agentAvatarProvider', retry: _noRetry)
class AgentAvatarState extends _$AgentAvatarState {
  Timer? _poll;

  /// Image bytes by `url` (candidates) or `url#updatedAt` (portrait,
  /// states).
  final _bytes = <String, Future<Uint8List>>{};

  @override
  Future<Avatar> build(String instanceId, {String profile = 'default'}) async {
    ref.onDispose(() {
      _poll?.cancel();
      _poll = null;
    });
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
    final avatar = Avatar.fromJson(await rest.getJson(_avatarRoute));
    _follow(avatar.job);
    return avatar;
  }

  Future<HermesRestClient> _rest() =>
      ref.read(restClientProvider(instanceId, profile: profile).future);

  /// Reloads the avatar from the server.
  Future<Avatar> reload() async {
    final avatar = Avatar.fromJson(await (await _rest()).getJson(_avatarRoute));
    _set(avatar);
    _follow(avatar.job);
    return avatar;
  }

  /// Starts generating [count] portrait candidates from [description]
  /// (1..1000 characters); the job is followed until its candidates are in.
  Future<AvatarJob> generatePortraits(String description, {int count = 4}) =>
      _start('$_avatarRoute/portrait', {
        'description': description.trim(),
        'count': count,
      });

  /// Keeps the finished portrait job's [candidate] as the portrait (old
  /// animations are dropped).
  Future<Avatar> select(int candidate) async {
    final avatar = Avatar.fromJson(
      await (await _rest()).postJson('$_avatarRoute/select', {
        'candidate': candidate,
      }),
    );
    _set(avatar.job == null ? avatar.withJob(state.value?.job) : avatar);
    return avatar;
  }

  /// Starts animating [states] (default [customAvatarStates]) from the
  /// portrait; each clip costs [MediaStatus.videoCost] credits.
  Future<AvatarJob> animate({List<String>? states}) =>
      _start('$_avatarRoute/animate', {'states': ?states});

  /// Deletes the generated portrait and animations; save the agent with a
  /// bundled avatar too.
  Future<void> clear() async {
    await (await _rest()).delete(_avatarRoute);
    _poll?.cancel();
    _poll = null;
    _set(const Avatar());
  }

  /// The square portrait (JPEG); throws [StateError] without one.
  Future<Uint8List> portraitBytes() {
    final avatar = state.value;
    final url = avatar?.portraitUrl;
    if (url == null) throw StateError('this agent has no generated portrait');
    return _load(url, version: _version(avatar));
  }

  /// The looping animated WebP of [state]; throws [StateError] when the
  /// agent has no clip for it.
  Future<Uint8List> stateBytes(String state) {
    final avatar = this.state.value;
    final url = avatar?.states[state];
    if (url == null) throw StateError('no "$state" animation for this agent');
    return _load(url, version: _version(avatar));
  }

  /// [stateBytes] of [state], or [portraitBytes] when it is null (the result
  /// of `customAvatarState`).
  Future<Uint8List> imageBytes(String? state) =>
      state == null ? portraitBytes() : stateBytes(state);

  /// A portrait candidate (JPEG) of [AvatarJob.candidates].
  Future<Uint8List> candidateBytes(String url) => _load(url);

  Future<AvatarJob> _start(String path, Map<String, Object?> body) async {
    final job = AvatarJob.fromJson(await (await _rest()).postJson(path, body));
    _set((state.value ?? const Avatar()).withJob(job));
    _follow(job);
    return job;
  }

  void _follow(AvatarJob? job) {
    _poll?.cancel();
    _poll = null;
    if (job == null || !job.running || !ref.mounted) return;
    _poll = Timer(ref.read(avatarJobPollIntervalProvider), () => _tick(job));
  }

  Future<void> _tick(AvatarJob previous) async {
    _poll = null;
    try {
      final rest = await _rest();
      final job = AvatarJob.fromJson(
        await rest.getJson(
          '$_avatarRoute/jobs/${Uri.encodeComponent(previous.id)}',
        ),
      );
      if (!ref.mounted) return;
      if (!job.running || _done(job) > _done(previous)) {
        // New clips (or the end of the run): fetch their URLs.
        final fresh = Avatar.fromJson(await rest.getJson(_avatarRoute));
        if (!ref.mounted) return;
        _set(
          fresh.job == null || fresh.job!.id == job.id
              ? fresh.withJob(job)
              : fresh,
        );
      } else {
        _set((state.value ?? const Avatar()).withJob(job));
      }
      _follow(state.value?.job);
    } on HermesHttpError catch (error, stack) {
      if (!ref.mounted) return;
      if (error.statusCode == 404) {
        // The job is gone (plugin restarted): show what the server has.
        unawaited(reload().then((_) {}, onError: (Object _) {}));
        return;
      }
      state = AsyncError(error, stack);
      _follow(previous);
    } on Object catch (error, stack) {
      if (!ref.mounted) return;
      state = AsyncError(error, stack);
      _follow(previous);
    }
  }

  static int _done(AvatarJob job) =>
      job.states.values.where((s) => s == AvatarStateStatus.done).length;

  void _set(Avatar avatar) {
    if (!ref.mounted) return;
    final version = _version(avatar);
    _bytes.removeWhere((key, _) {
      final at = key.lastIndexOf('#');
      return at >= 0 && key.substring(at + 1) != version;
    });
    state = AsyncData(avatar);
  }

  static String _version(Avatar? avatar) =>
      avatar?.updatedAt?.toIso8601String() ?? '';

  Future<Uint8List> _load(String url, {String? version}) {
    final key = version == null ? url : '$url#$version';
    final cached = _bytes[key];
    if (cached != null) return cached;
    Future<Uint8List> fetch() async {
      try {
        // Plugin URLs are paths on the dashboard (`/api/plugins/hermuse/…`),
        // fetched with the client's auth and profile scope.
        final uri = Uri.parse(url);
        final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
        return await (await _rest()).getBytes(
          path,
          uri.hasQuery ? uri.queryParameters : null,
        );
      } catch (_) {
        _bytes.remove(key);
        rethrow;
      }
    }

    return _bytes[key] = fetch();
  }
}
