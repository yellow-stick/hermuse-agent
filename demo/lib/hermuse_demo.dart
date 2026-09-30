/// Read-only demo of the Hermuse web app: fictional Hermes instances, chats
/// and plugin data answered in the browser, so the app runs on a plain
/// static host without a relay or a Hermes instance.
///
/// Built into `apps/hermuse_web` with `--dart-define=HERMUSE_DEMO=true`
/// (see `demo/README.md`).
library;

export 'src/content.dart' show DemoChat, DemoInstance, DemoRow, demoInstances;
export 'src/plugin_api.dart' show demoPluginClient;
export 'src/setup.dart' show demoOverrides, seedDemo;
export 'src/transport.dart' show DemoTransport, demoReadOnlyMessage;
