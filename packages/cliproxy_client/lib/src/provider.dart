/// Subscription-OAuth providers exposed by the CLIProxyAPI management API.
///
/// Route names are the exact `GET /v0/management/<route>` segments from
/// CLIProxyAPI v7.3.18 `internal/api/server_management.go`.
enum CliproxyProvider {
  /// Claude Pro/Max subscription OAuth.
  anthropic('anthropic-auth-url', 'Anthropic (Claude Pro/Max)'),

  /// ChatGPT/Codex subscription OAuth.
  codex('codex-auth-url', 'Codex (ChatGPT)'),

  /// Meta subscription OAuth; device-code flow.
  meta('meta-auth-url', 'Meta'),

  /// Google Antigravity subscription OAuth.
  antigravity('antigravity-auth-url', 'Antigravity'),

  /// xAI subscription OAuth; device-code flow.
  xai('xai-auth-url', 'xAI'),

  /// Kimi (.com) subscription OAuth; device-code flow.
  kimi('kimi-auth-url', 'Kimi'),

  /// Kimi.ai subscription OAuth; device-code flow.
  kimiAi('kimi-ai-auth-url', 'Kimi.ai'),

  /// Devin subscription OAuth.
  devin('devin-auth-url', 'Devin');

  const CliproxyProvider(this.route, this.label);

  /// The exact `/v0/management/<route>` path segment.
  final String route;

  /// Human-facing provider name for bridge cards.
  final String label;
}
