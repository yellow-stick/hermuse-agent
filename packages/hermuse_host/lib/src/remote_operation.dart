import 'dart:async';
import 'dart:math';

import 'errors.dart';
import 'remote_scripts.dart';
import 'remote_shell.dart';

/// Holds a shared attempt lock after an exclusive setup admission check.
///
/// Mutator watchdogs inherit their own shared descriptor. Cancellation cannot
/// admit another setup/uninstall until all mutating process groups have exited.
final class RemoteOperationLock {
  RemoteOperationLock._(this._cancellation);

  final RemoteCancellation _cancellation;
  final _nonce =
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(1 << 32)}';
  bool _released = false;
  Object? _failure;

  static Future<RemoteOperationLock> acquire(
    RemoteShell shell, {
    required bool root,
    required RemoteCancellation cancellation,
  }) async {
    final lock = RemoteOperationLock._(cancellation);
    final ready = Completer<void>();
    final command =
        '${root ? '' : 'sudo -n '}'
        'bash -euo pipefail -c '
        '${shellQuote(supervisedCommand(_holder(lock._nonce), 86400))}';
    unawaited(() async {
      try {
        void onLine(String line) {
          if (line == 'HERMUSE_OPERATION_LOCKED_V1' && !ready.isCompleted) {
            ready.complete();
          }
        }

        final result = await (shell is RemoteOperationHolderShell
            ? shell.holdOperation(
                command,
                timeout: const Duration(hours: 24, seconds: 15),
                onLine: onLine,
              )
            : shell.run(
                command,
                timeout: const Duration(hours: 24, seconds: 15),
                onLine: onLine,
              ));
        if (!lock._released) {
          lock._failure = RemoteInstallFailed(
            'preflight',
            'The server setup lock could not be held. Another setup or '
                'uninstall may be running. ${result.stderr.trim()}',
          );
        }
      } catch (error) {
        if (!lock._released) lock._failure = error;
      } finally {
        if (!ready.isCompleted) {
          ready.completeError(lock._failure ?? const RemoteInstallCancelled());
        } else if (!lock._released) {
          cancellation.cancel();
        }
      }
    }());
    await cancellation.bind(ready.future.timeout(const Duration(seconds: 20)));
    lock.check();
    return lock;
  }

  void check() {
    if (_failure case final error?) throw error;
    _cancellation.check();
  }

  /// Retains a child lock until the command exits, even if its holder disappears.
  ///
  /// Local package transactions must finish before cancellation or timeout is
  /// reported. Only SSH commands use a force-killing process-group watchdog.
  String supervise(String script, int seconds, {required bool interruptible}) {
    check();
    return '$_prepareLock'
        'flock -n -s 7 || exit 1\n'
        'expected=${shellQuote(_nonce)}\n'
        '$_verifyHolder\n'
        '${interruptible ? supervisedCommand(script, seconds) : script}';
  }

  /// Marks transport shutdown as intentional; the caller then closes its shell.
  void release() => _released = true;
}

String _holder(String nonce) =>
    '$_prepareLock'
    'flock -n -x 7 || { echo "Another server setup or uninstall is running." >&2; exit 1; }\n'
    'setup_nonce=${shellQuote(nonce)}\n'
    r'''
owner=/var/lib/hermuse-provision/operation.owner
[ ! -L "$owner" ] || exit 1
if [ -e "$owner" ]; then
  [ -f "$owner" ] && [ "$(stat -c %u "$owner")" = 0 ] &&
  [ $((8#$(stat -c %a "$owner") & 0022)) = 0 ] || exit 1
fi
read -ra fields < "/proc/$BASHPID/stat"
printf '%s %s %s\n' "$setup_nonce" "$BASHPID" "${fields[21]}" > "$owner"
chmod 0600 "$owner"
trap 'if [ "$(cut -d" " -f1 "$owner" 2>/dev/null || true)" = "$setup_nonce" ]; then rm -f -- "$owner"; fi' EXIT
trap 'exit 0' TERM INT HUP
flock -s 7
printf 'HERMUSE_OPERATION_LOCKED_V1\n'
while :; do sleep 2; done
''';

/// Holds exclusive admission outside the watchdog for a whole removal command.
String exclusiveRemoteOperationCommand(String script, int seconds) =>
    '$_prepareLock'
    'flock -n -x 7 || { echo "A server setup or uninstall is already running; nothing was removed." >&2; exit 1; }\n'
    'export HERMUSE_OPERATION_FD=7\n'
    '${supervisedCommand(script, seconds)}';

const _verifyHolder = r'''
owner=/var/lib/hermuse-provision/operation.owner
[ ! -L "$owner" ] && [ -f "$owner" ] || exit 1
read -r setup_nonce setup_pid setup_started < "$owner"
[ "$setup_nonce" = "$expected" ] && [[ "$setup_pid" =~ ^[0-9]+$ ]] || exit 1
kill -0 "$setup_pid" 2>/dev/null || exit 1
read -ra fields < "/proc/$setup_pid/stat"
[ "${fields[21]}" = "$setup_started" ] && [ "${fields[2]}" != Z ] || exit 1
''';

const _prepareLock = r'''
for path in /var /var/lib /var/lib/hermuse-provision; do
  [ ! -L "$path" ] || { echo 'Unsafe operation lock path.' >&2; exit 1; }
  if [ -e "$path" ]; then
    [ -d "$path" ] && [ "$(stat -c %u "$path")" = 0 ] &&
    [ $((8#$(stat -c %a "$path") & 0022)) = 0 ] || exit 1
  fi
done
install -d -m 0711 /var/lib/hermuse-provision
lock=/var/lib/hermuse-provision/operation.lock
[ ! -L "$lock" ] || exit 1
if [ -e "$lock" ]; then
  [ -f "$lock" ] && [ "$(stat -c %u "$lock")" = 0 ] &&
  [ $((8#$(stat -c %a "$lock") & 0022)) = 0 ] || exit 1
fi
umask 077
exec 7<>"$lock"
''';
