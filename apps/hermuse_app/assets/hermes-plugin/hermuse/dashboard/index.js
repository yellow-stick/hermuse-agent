/* Hermuse dashboard plugin — API-only stub.
 *
 * The Hermuse surfaces (Feed, Ideas, Goals, Library, Reflections) are rendered by
 * the Hermuse app, which talks to this plugin's backend routes mounted at
 * /api/plugins/hermuse/. The manifest marks this plugin's tab hidden, but the
 * dashboard still loads the entry bundle for every installed plugin, so this
 * stub registers a placeholder component to keep the host's plugin registry
 * consistent (no LOAD_FAILED / NO_REGISTER error state).
 */
(function () {
  var host = window.__HERMES_PLUGINS__;
  if (!host || typeof host.register !== "function") {
    return;
  }
  function HermusePlaceholder() {
    return null;
  }
  host.register("hermuse", HermusePlaceholder);
})();
