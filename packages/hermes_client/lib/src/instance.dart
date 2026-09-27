/// Where a Hermes instance runs relative to this device.
enum InstanceKind {
  /// Installed and supervised by Hermuse on this desktop.
  local,

  /// Reached over the network (VPS, another machine, a tunnel).
  remote,
}

/// How Hermuse authenticates against an instance's dashboard.
enum AuthMethod {
  /// Loopback backend spawned by Hermuse: `X-Hermes-Session-Token` + `?token=`.
  loopbackToken,

  /// Dashboard password provider (`POST /auth/password-login`, cookie session).
  password,

  /// Native RFC 8252 PKCE sign-in (Nous Portal and friends).
  nativeOAuth,
}

/// One Hermes backend the user registered. Never carries secrets: those live
/// in a `SecretStore` keyed by [id].
final class HermesInstance {
  HermesInstance({
    required this.id,
    required this.label,
    required this.kind,
    required this.baseUrl,
    required this.auth,
    this.profile,
  }) {
    if (label.trim().isEmpty || label.length > maxLabelLength) {
      throw ArgumentError.value(label, 'label', '1–$maxLabelLength chars');
    }
    if (!baseUrl.hasScheme ||
        !const {'http', 'https'}.contains(baseUrl.scheme) ||
        baseUrl.host.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'http(s) URL with host');
    }
  }

  factory HermesInstance.fromJson(Map<String, Object?> json) => HermesInstance(
    id: json['id'] as String,
    label: json['label'] as String,
    kind: InstanceKind.values.byName(json['kind'] as String),
    baseUrl: Uri.parse(json['base_url'] as String),
    auth: AuthMethod.values.byName(json['auth'] as String),
    profile: json['profile'] as String?,
  );

  static const maxLabelLength = 64;

  /// Stable identifier (UUID v4); half of every `(instanceId, sessionId)` key.
  final String id;

  /// User-facing name, unique case-insensitively across instances.
  final String label;
  final InstanceKind kind;

  /// Dashboard origin, normalised (see [normalizeBaseUrl]).
  final Uri baseUrl;
  final AuthMethod auth;

  /// Hermes profile to scope to; null = the instance default.
  final String? profile;

  HermesInstance copyWith({
    String? label,
    Uri? baseUrl,
    AuthMethod? auth,
    String? Function()? profile,
  }) => HermesInstance(
    id: id,
    label: label ?? this.label,
    kind: kind,
    baseUrl: baseUrl ?? this.baseUrl,
    auth: auth ?? this.auth,
    profile: profile == null ? this.profile : profile(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'base_url': baseUrl.toString(),
    'auth': auth.name,
    if (profile != null) 'profile': profile,
  };

  @override
  bool operator ==(Object other) =>
      other is HermesInstance &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.baseUrl == baseUrl &&
      other.auth == auth &&
      other.profile == profile;

  @override
  int get hashCode => Object.hash(id, label, kind, baseUrl, auth, profile);
}

/// Trims, lowercases scheme/host, drops query/fragment and trailing `/`.
Uri normalizeBaseUrl(String input) {
  final raw = input.trim();
  final uri = Uri.parse(raw.contains('://') ? raw : 'https://$raw');
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
}
