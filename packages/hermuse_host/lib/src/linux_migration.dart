import 'dart:convert';

/// A read-only legacy inventory whose revision authorizes one exact snapshot.
final class LegacyHermesMigration {
  const LegacyHermesMigration({
    required this.sourceHome,
    required this.revision,
    required this.summary,
  });

  factory LegacyHermesMigration.fromJson(Map<String, dynamic> json) =>
      LegacyHermesMigration(
        sourceHome: json['sourceHome'] as String,
        revision: json['revision'] as String,
        summary: json['summary'] as String,
      );

  final String sourceHome;
  final String revision;
  final String summary;

  Map<String, dynamic> toJson() => {
    'sourceHome': sourceHome,
    'revision': revision,
    'summary': summary,
  };
}

/// Inspects without importing or executing any legacy installation code.
String inspectLegacyHermesScript(String sourceHome) =>
    _script({'sourceHome': sourceHome, 'operation': 'inspect'});

/// Copies only the explicitly confirmed snapshot, retaining a verified backup.
///
/// The caller must hold the provisioning operation lock and create the dedicated
/// hermes account first. Paths and account identity are fixed in the helper.
String migrateLegacyHermesScript(LegacyHermesMigration inventory) =>
    _script({...inventory.toJson(), 'operation': 'migrate'});

String _script(Map<String, dynamic> request) {
  final encoded = base64Encode(utf8.encode(jsonEncode(request)));
  return "set -eu\n/usr/bin/python3 -I - '$encoded' <<'HERMUSE_MIGRATION_PY'\n"
      '$_python\nHERMUSE_MIGRATION_PY\n';
}

const _python = r'''
import base64, fcntl, hashlib, json, os, pwd, re, secrets, shutil, stat, sys

R = json.loads(base64.b64decode(sys.argv[1]))
DEST = '/home/hermes/.hermes'
STATE = '/var/lib/hermuse-provision'
PROC = '/proc'
ACCOUNT = 'hermes'
ROOT_UID = 0
SOURCE = R['sourceHome']
RUNTIMES = ('hermes-agent', 'runtime', 'bin', 'node', 'plugins/hermuse', 'hermuse/bridge/bin')

class Refusal(Exception):
    pass

def refuse(message):
    raise Refusal(message)

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def stamp(info):
    return [info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_nlink]

def directory(path):
    # Resolve every component with O_NOFOLLOW, including ancestors.
    if not os.path.isabs(path) or os.path.normpath(path) != path or path == '/':
        refuse('An absolute normalized data directory is required.')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.split('/')[1:]:
            next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise

def trusted_directory(path):
    # Every ancestor must protect its children's names. A root-owned sticky
    # ancestor is safe only because every opened child is also root-owned.
    if not os.path.isabs(path) or os.path.normpath(path) != path:
        refuse('An absolute normalized private directory is required.')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        components = path.split('/')[1:]
        for component in components:
            info = os.fstat(fd)
            if info.st_uid not in (0, ROOT_UID) or (info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX):
                refuse('Migration requires root-protected directory ancestors.')
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        info = os.fstat(fd)
        if info.st_uid not in (0, ROOT_UID) or info.st_mode & 0o022:
            refuse('Migration requires a root-protected private directory.')
        return fd
    except BaseException:
        os.close(fd)
        raise

def runtime(name):
    return any(name == item or name.startswith(item + '/') for item in RUNTIMES)

def snapshot(path, copy_to=None, expected_uid=None, root_fd=None):
    root = directory(path) if root_fd is None else os.dup(root_fd)
    identity, content = {}, {}
    try:
        root_stat = os.fstat(root)
        owner = root_stat.st_uid if expected_uid is None else expected_uid
        def walk(fd, relative):
            info = os.fstat(fd)
            directory_info = info
            check(info, relative, directory_entry=True)
            record(relative, info, 'directory', None)
            if copy_to is not None:
                target = os.path.join(copy_to, relative)
                os.makedirs(target, mode=0o700, exist_ok=True)
            for name in sorted(os.listdir(fd)):
                child = relative + '/' + name if relative else name
                # Reproducible executable trees are neither read nor copied.
                # Their original remains in place; every other tree, including
                # model caches and OAuth credentials, stays in the snapshot.
                if runtime(child):
                    continue
                before = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISDIR(before.st_mode):
                    sub = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                    try:
                        if (before.st_dev, before.st_ino) != (os.fstat(sub).st_dev, os.fstat(sub).st_ino):
                            refuse('Legacy data changed while being read.')
                        walk(sub, child)
                    finally:
                        os.close(sub)
                elif stat.S_ISREG(before.st_mode):
                    stream = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                    try:
                        info = os.fstat(stream)
                        check(info, child)
                        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                            refuse('Hard-linked or special legacy files cannot be migrated safely.')
                        hasher = hashlib.sha256()
                        output = None
                        if copy_to is not None:
                            output = open(os.path.join(copy_to, child), 'xb')
                        try:
                            while True:
                                chunk = os.read(stream, 1024 * 1024)
                                if not chunk:
                                    break
                                hasher.update(chunk)
                                if output is not None:
                                    output.write(chunk)
                            if output is not None:
                                output.flush()
                                os.fsync(output.fileno())
                        finally:
                            if output is not None:
                                output.close()
                        if stamp(info) != stamp(os.fstat(stream)) or stamp(before) != stamp(info):
                            refuse('Legacy data changed while being read.')
                        record(child, info, 'file', hasher.hexdigest())
                        if copy_to is not None:
                            os.chmod(os.path.join(copy_to, child), stat.S_IMODE(info.st_mode))
                    finally:
                        os.close(stream)
                elif stat.S_ISLNK(before.st_mode):
                    # Links are recorded and copied, never dereferenced.
                    check(before, child, link=True)
                    target = os.readlink(name, dir_fd=fd)
                    record(child, before, 'link', target)
                    if copy_to is not None:
                        os.symlink(target, os.path.join(copy_to, child))
                else:
                    refuse('Special legacy files require manual migration.')
            if stamp(directory_info) != stamp(os.fstat(fd)):
                refuse('Legacy directories changed while being read.')
            if copy_to is not None:
                os.chmod(os.path.join(copy_to, relative), stat.S_IMODE(directory_info.st_mode))
        def check(info, name, directory_entry=False, link=False):
            if info.st_uid != owner:
                refuse('Legacy data contains files owned by another account.')
            if not link and info.st_mode & 0o022:
                refuse('Group/world-writable legacy data must be secured before migration.')
            if not link and info.st_mode & 0o7000:
                refuse('Special permission bits require manual migration.')
        def record(name, info, kind, value):
            content[name] = [kind, stat.S_IMODE(info.st_mode), value]
            identity[name] = [info.st_dev, info.st_ino, info.st_uid, info.st_gid,
                              info.st_size, info.st_mtime_ns, info.st_ctime_ns]
        walk(root, '')
        for name, item in content.items():
            if item[0] != 'link':
                continue
            target = internal_link(name, item[2])
            if target not in content or content[target][0] == 'link' or runtime(target):
                refuse('Broken, chained, or runtime-linked profile symlinks require manual migration.')
        return {'content': content, 'identity': identity}
    finally:
        os.close(root)

def internal_link(name, target):
    if os.path.isabs(target):
        if not target.startswith(SOURCE + '/'):
            refuse('A profile symlink escapes the approved legacy home; resolve it before migration.')
        target = os.path.normpath(target[len(SOURCE) + 1:])
    else:
        target = os.path.normpath(os.path.join(os.path.dirname(name), target))
    if target == '..' or target.startswith('../'):
        refuse('A profile symlink escapes the approved legacy home; resolve it before migration.')
    return target

def idle(path, uid):
    own = os.getpid()
    for name in os.listdir(PROC):
        if not name.isdigit() or int(name) == own:
            continue
        process = os.path.join(PROC, name)
        try:
            if os.stat(process).st_uid != uid:
                continue
            for field in ('cwd', 'exe'):
                value = os.readlink(os.path.join(process, field))
                if value == path or value.startswith(path + '/'):
                    refuse('Stop processes using the legacy or canonical Hermes home before migration.')
            with open(os.path.join(process, 'cmdline'), 'rb') as stream:
                command = stream.read()
            with open(os.path.join(process, 'environ'), 'rb') as stream:
                environment = stream.read()
            if path.encode() in command or path.encode() in environment:
                refuse('Stop processes using the legacy or canonical Hermes home before migration.')
            for handle in os.listdir(os.path.join(process, 'fd')):
                value = os.readlink(os.path.join(process, 'fd', handle))
                if value == path or value.startswith(path + '/'):
                    refuse('Stop processes with open Hermes data before migration.')
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            refuse('Process usage cannot be verified; migration requires privileged inspection.')

def inventory():
    if SOURCE == DEST:
        refuse('Only a distinct per-user Hermes directory can be migrated.')
    try:
        parent = directory(os.path.dirname(SOURCE))
        try:
            owner = os.fstat(parent).st_uid
        finally:
            os.close(parent)
        source_fd = directory(SOURCE)
        os.close(source_fd)
    except FileNotFoundError:
        return None, None, None
    caller = os.environ.get('PKEXEC_UID')
    if caller is not None:
        if not caller.isdigit() or owner != int(caller):
            refuse('Legacy data does not belong to the authenticated calling account.')
    elif os.geteuid() != ROOT_UID and owner != os.getuid():
        refuse('Legacy data does not belong to the calling account.')
    # A disappearing entry during the snapshot is an error, not an empty home.
    data = snapshot(SOURCE, expected_uid=owner)
    meaningful = [name for name, item in data['content'].items() if name and item[0] != 'directory']
    if not meaningful:
        return None, None, owner
    revision = digest({'source': SOURCE, 'snapshot': data})
    files = sum(item[0] == 'file' for item in data['content'].values())
    summary = (str(files) + ' files, including profiles, conversations, configuration, secrets and schedules. '
        'The original remains untouched and a verified private user-data backup is retained. '
        'The backup excludes only reproducible executable trees: ' + ', '.join(RUNTIMES) + '. '
        'Those original trees stay in place; their runtimes are reinstalled, not copied. '
        'All other data, model caches and credentials inside this home are backed up. '
        'Configuration paths within this home are relocated; desktop subscription auth and API keys '
        'are preserved with a new server management key. External user paths and existing Docker '
        'computer references require manual resolution: original volumes are untouched, not copied.')
    return {'sourceHome': SOURCE, 'revision': revision, 'summary': summary}, data, owner

def private_state():
    if os.geteuid() != ROOT_UID:
        refuse('Migration must run through the privileged helper.')
    parent = trusted_directory(os.path.dirname(STATE))
    try:
        try:
            os.mkdir(os.path.basename(STATE), 0o700, dir_fd=parent)
        except FileExistsError:
            pass
        fd = os.open(os.path.basename(STATE), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    finally:
        os.close(parent)
    info = os.fstat(fd)
    if info.st_uid != ROOT_UID or info.st_mode & 0o022:
        os.close(fd)
        refuse('Migration state must be root-owned and not writable by other accounts.')
    return fd

def save_receipt(path, value):
    temp = path + '.new'
    if os.path.lexists(temp):
        info = os.lstat(temp)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != ROOT_UID or info.st_nlink != 1:
            refuse('Untrusted interrupted migration receipt.')
        os.unlink(temp)
    with open(temp, 'x') as stream:
        json.dump(value, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)
    fd = directory(os.path.dirname(path))
    os.fsync(fd)
    os.close(fd)

def bridge_keys(stage):
    ports = set()
    for root, dirs, files in os.walk(stage):
        if os.path.basename(root) != 'cliproxy':
            continue
        config = os.path.join(root, 'config.yaml')
        if not os.path.isfile(config):
            if dirs or files:
                refuse('Desktop subscription auth has no complete configuration; restore config.yaml before migration.')
            continue
        # Parse only the emitted desktop schema, never arbitrary YAML tags.
        with open(config) as stream:
            text = stream.read()
        values = {}
        section = None
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line in ('api-keys:', 'remote-management:', 'discovery:'):
                section = line[:-1]
                continue
            if line.startswith('- ') and section == 'api-keys':
                if 'api_key' in values:
                    refuse('Multiple desktop bridge API keys require manual migration.')
                values['api_key'] = scalar(line[2:])
                continue
            if ':' not in line:
                refuse('Unsupported desktop bridge configuration; manual migration required.')
            key, value = line.split(':', 1)
            if key not in ('host', 'port', 'auth-dir', 'allow-remote', 'secret-key', 'disable-control-panel', 'enabled'):
                refuse('Custom desktop bridge configuration requires manual migration.')
            if key in values:
                refuse('Duplicate desktop bridge settings require manual migration.')
            values[key] = scalar(value.strip())
        source_auth = os.path.join(SOURCE, os.path.relpath(root, stage), 'auth')
        port = values.get('port')
        if (values.get('host') != '127.0.0.1' or not isinstance(port, int) or
                isinstance(port, bool) or not 1024 <= port <= 65535 or
                values.get('auth-dir') != source_auth or values.get('allow-remote') is not False or
                not isinstance(values.get('api_key'), str) or not values['api_key']):
            refuse('Incomplete or nonlocal desktop bridge settings require manual migration.')
        auth = os.path.join(root, 'auth')
        if not os.path.isdir(auth) or os.path.islink(auth):
            refuse('Desktop bridge authentication directory is missing; restore it before migration.')
        bridge = os.path.join(os.path.dirname(root), 'hermuse', 'bridge')
        if os.path.exists(bridge) and os.listdir(bridge):
            refuse('Both desktop and server subscription bridges contain data; migration never merges them.')
        os.makedirs(bridge, mode=0o700, exist_ok=True)
        shutil.copytree(auth, os.path.join(bridge, 'auth'), symlinks=True)
        keys = {'port': port, 'api_key': values['api_key'], 'management_key': secrets.token_urlsafe(32)}
        target_auth = os.path.join(DEST, os.path.relpath(bridge, stage), 'auth')
        config_text = ('host: "127.0.0.1"\nport: ' + str(port) + '\nauth-dir: ' + json.dumps(target_auth) +
            '\napi-keys:\n  - ' + json.dumps(keys['api_key']) + '\nremote-management:\n  allow-remote: false\n  secret-key: ' +
            json.dumps(keys['management_key']) + '\n  disable-control-panel: true\ndiscovery:\n  enabled: false\n')
        for name, contents in (('keys.json', json.dumps(keys)), ('config.yaml', config_text)):
            with open(os.path.join(bridge, name), 'x') as stream:
                stream.write(contents)
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(os.path.join(bridge, name), 0o600)
        ports.add(port)
    for root, dirs, files in os.walk(stage):
        if root.endswith('/hermuse/bridge') and 'keys.json' in files:
            with open(os.path.join(root, 'keys.json')) as stream:
                keys = json.load(stream)
            if (not isinstance(keys, dict) or not isinstance(keys.get('port'), int) or
                    isinstance(keys['port'], bool) or not 1024 <= keys['port'] <= 65535 or
                    not all(isinstance(keys.get(key), str) and keys[key] for key in ('api_key', 'management_key'))):
                refuse('Incomplete server bridge credentials require manual migration.')
            ports.add(keys['port'])
    return ports

def scalar(value):
    if value.startswith('\"') or value in ('true', 'false') or re.fullmatch('[0-9]+', value):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    if re.fullmatch(r'[A-Za-z0-9_./:$-]+', value):
        return value
    refuse('Unsupported desktop bridge scalar; manual migration required.')

def relocate_paths(text, old, new):
    # Match path components, not siblings such as ".hermes-workspace" or
    # substrings embedded in a different absolute path.
    endings = r"""[\s"'`,;\])}]"""
    suffix = r"""[^\s"'`,;\])}]*"""
    pattern = r'(?<![^\s"\'`=:\[({,;])' + re.escape(old) + r'(?:/' + suffix + r')?(?=$|' + endings + r')'
    def replace(match):
        path = match.group()
        normalized = os.path.normpath(path)
        if normalized != old and not normalized.startswith(old + '/'):
            refuse('Configuration references external user paths; resolve them before migration.')
        return new + path[len(old):]
    return re.sub(pattern, replace, text)

def prepare(stage):
    # Convert approved links to relative paths before touching configuration.
    for root, dirs, files in os.walk(stage):
        for name in dirs + files:
            path = os.path.join(root, name)
            relative = os.path.relpath(path, stage)
            if os.path.islink(path) and not runtime(relative):
                target = internal_link(relative, os.readlink(path))
                os.unlink(path)
                os.symlink(os.path.relpath(os.path.join(stage, target), root), path)
    ports = bridge_keys(stage)
    for root, dirs, files in os.walk(stage):
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                continue
            configuration = (name in ('.env', 'config', 'config.yaml', 'config.yml', 'config.json',
                             'settings.json', 'profiles.json', 'jobs.json', 'cliproxy.json') or
                             name.endswith(('.yaml', '.yml', '.toml', '.env')))
            if not configuration:
                continue
            with open(path, 'rb') as stream:
                raw = stream.read()
            try:
                text = raw.decode('utf-8')
            except UnicodeDecodeError:
                refuse('Non-text configuration requires manual migration.')
            for port in re.findall(r'(?:localhost|127\.0\.0\.1):([0-9]+)\b', text):
                if int(port) not in ports:
                    refuse('A local model endpoint has no preserved server bridge credentials; configure it before migration.')
            text = relocate_paths(text, SOURCE, DEST)
            # External account paths and runtime sockets cannot be transferred to
            # another uid safely. Never silently retain a now-inaccessible path.
            if re.search(r'/(?:home|Users|root|run/user|tmp)/', relocate_paths(text, DEST, 'HERMES_HOME')):
                refuse('Configuration references external user paths; resolve them before migration.')
            if text.encode() != raw:
                with open(path, 'wb') as stream:
                    stream.write(text.encode())
                    stream.flush()
                    os.fsync(stream.fileno())

def migrate():
    state = private_state()
    lock = os.open('migration.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600, dir_fd=state)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current, data, owner = inventory()
        if current is None or not re.fullmatch(r'[0-9a-f]{64}', R.get('revision', '')) or current['revision'] != R['revision']:
            refuse('Legacy data changed; inspect and explicitly confirm the new revision.')
        empty_runtime = {hashlib.sha256(value).hexdigest() for value in (b'', b'{}', b'null', b'{}\n', b'null\n')}
        for name, item in data['content'].items():
            if name.endswith(('computer/runtime.json', 'computer/config.json')) and (item[0] != 'file' or item[2] not in empty_runtime):
                refuse('Existing computer runtime references block automatic migration; Docker data is untouched. Stop the old computer and export its persistent /home/hermuse volume. Container and volume names may be shared with the canonical instance: use a separately verified canonical restore, not automatic reassignment or deletion.')
        account = pwd.getpwnam(ACCOUNT)
        idle(SOURCE, owner)
        idle(DEST, account.pw_uid)
        home = os.path.dirname(DEST)
        home_parent = trusted_directory(os.path.dirname(home))
        target_parent = os.open(os.path.basename(home), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=home_parent)
        target_info = os.fstat(target_parent)
        if target_info.st_uid not in (ROOT_UID, account.pw_uid) or target_info.st_mode & 0o022:
            refuse('Canonical home has unsafe ownership or permissions.')
        if target_info.st_dev != os.fstat(home_parent).st_dev:
            refuse('Canonical home is a separate mount; migration requires private staging on the same filesystem.')
        staging_name = '.hermuse-migrations'
        try:
            os.mkdir(staging_name, 0o700, dir_fd=home_parent)
        except FileExistsError:
            pass
        staging_parent = os.open(staging_name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=home_parent)
        staging_info = os.fstat(staging_parent)
        if staging_info.st_uid != ROOT_UID or staging_info.st_mode & 0o077 or staging_info.st_dev != target_info.st_dev:
            refuse('Migration staging must be private, root-owned and on the canonical filesystem.')
        transaction = os.path.join(STATE, 'migration-' + current['revision'])
        receipt_path = os.path.join(transaction, 'receipt.json')
        backup = os.path.join(transaction, 'backup')
        stage = os.path.join(os.path.dirname(home), staging_name, current['revision'])
        receipt = None
        if os.path.exists(transaction):
            fd = directory(transaction)
            info = os.fstat(fd)
            os.close(fd)
            if info.st_uid != ROOT_UID or info.st_mode & 0o077:
                refuse('Untrusted migration transaction; no files changed.')
            if not os.path.isfile(receipt_path) or os.path.islink(receipt_path):
                refuse('Interrupted backup has no ownership receipt; retained for manual recovery.')
            with open(receipt_path) as stream:
                receipt = json.load(stream)
            if receipt.get('revision') != current['revision'] or receipt.get('source') != SOURCE:
                refuse('Migration receipt does not match confirmed data.')
            if snapshot(backup, expected_uid=ROOT_UID)['content'] != data['content']:
                refuse('The retained backup no longer matches the confirmed data.')
            if receipt.get('phase') in ('ready', 'complete') and os.path.lexists(DEST):
                fd = os.open(os.path.basename(DEST), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=target_parent)
                try:
                    info = os.fstat(fd)
                    proven = info.st_uid == account.pw_uid and [info.st_dev, info.st_ino] == receipt.get('stageIdentity')
                    # Check the pinned inode, never a replacement pathname.
                    # A complete cutover may have been extended by its user.
                    if proven and (receipt['phase'] == 'complete' or snapshot(DEST, expected_uid=account.pw_uid, root_fd=fd)['content'] == receipt.get('installed')):
                        present = os.stat(os.path.basename(DEST), dir_fd=target_parent, follow_symlinks=False)
                        if (present.st_dev, present.st_ino) != (info.st_dev, info.st_ino):
                            refuse('Canonical home changed during migration recovery.')
                        if receipt['phase'] != 'complete':
                            receipt['phase'] = 'complete'
                            save_receipt(receipt_path, receipt)
                        print(json.dumps({'migrated': True, 'backup': backup, 'reused': True}))
                        return
                finally:
                    os.close(fd)
        if os.path.lexists(DEST):
            fd = os.open(os.path.basename(DEST), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=target_parent)
            try:
                if os.listdir(fd):
                    refuse('Canonical Hermes data already exists; migration never merges installations.')
                if os.fstat(fd).st_uid not in (ROOT_UID, account.pw_uid):
                    refuse('Canonical home has unexpected ownership.')
            finally:
                os.close(fd)
        if receipt is None:
            os.mkdir(transaction, 0o700)
            os.mkdir(backup, 0o700)
            copied = snapshot(SOURCE, copy_to=backup, expected_uid=owner)
            if copied != data or snapshot(backup, expected_uid=ROOT_UID)['content'] != data['content']:
                refuse('Backup verification failed; original and backup retained.')
            receipt = {'revision': current['revision'], 'source': SOURCE, 'phase': 'backed-up'}
            save_receipt(receipt_path, receipt)
        if os.path.lexists(stage):
            info = os.lstat(stage)
            if receipt.get('stageIdentity') != [info.st_dev, info.st_ino] or not stat.S_ISDIR(info.st_mode):
                refuse('An unproven staging directory exists; nothing was removed.')
            shutil.rmtree(stage)
        os.mkdir(stage, 0o700)
        info = os.stat(stage)
        receipt.update(phase='copying', stageIdentity=[info.st_dev, info.st_ino])
        save_receipt(receipt_path, receipt)
        try:
            snapshot(backup, copy_to=stage, expected_uid=ROOT_UID)
            prepare(stage)
            installed = snapshot(stage, expected_uid=ROOT_UID)['content']
            if inventory()[0] != current:
                refuse('Legacy data changed during migration; inspect and confirm again.')
            idle(SOURCE, owner)
            idle(DEST, account.pw_uid)
            receipt.update(phase='ready', installed=installed)
            save_receipt(receipt_path, receipt)
            for root, dirs, files in os.walk(stage):
                for name in dirs + files:
                    os.chown(os.path.join(root, name), account.pw_uid, account.pw_gid, follow_symlinks=False)
                os.chown(root, account.pw_uid, account.pw_gid)
            # POSIX rename atomically replaces only an empty directory, refusing
            # a competing nonempty installation or symlink without merging.
            os.rename(current['revision'], os.path.basename(DEST), src_dir_fd=staging_parent, dst_dir_fd=target_parent)
            os.fsync(target_parent)
            os.fsync(staging_parent)
            receipt['phase'] = 'complete'
            save_receipt(receipt_path, receipt)
        except BaseException:
            if os.path.isdir(stage) and not os.path.islink(stage):
                info = os.stat(stage)
                if [info.st_dev, info.st_ino] == receipt['stageIdentity']:
                    shutil.rmtree(stage)
            raise
        print(json.dumps({'migrated': True, 'backup': backup, 'reused': False}))
    finally:
        os.close(lock)
        os.close(state)
        for name in ('staging_parent', 'target_parent', 'home_parent'):
            if name in locals():
                os.close(locals()[name])

try:
    if R['operation'] == 'inspect':
        print(json.dumps(inventory()[0]))
    else:
        migrate()
except (Refusal, OSError, ValueError, KeyError, TypeError, AttributeError):
    error = sys.exc_info()[1]
    # OS exceptions may contain paths or secret-bearing names. Only deliberate,
    # fixed refusal messages are emitted across the privilege boundary.
    print(str(error) if isinstance(error, Refusal) else 'Migration could not safely access the installation; no source data was removed.', file=sys.stderr)
    sys.exit(1)
''';
