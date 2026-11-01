import 'dart:convert';

import 'installer.dart';
import 'remote_operation.dart';
import 'remote_scripts.dart';

/// Rejects unknown source directories without journaling or importing plugins.
String get remoteOwnershipPreflightScript =>
    '''
if command -v python3 >/dev/null; then
  ${_recipe({'mode': 'preflight'})}
elif [ -e ${shellQuote(remoteCheckout)} ] || [ -L ${shellQuote(remoteCheckout)} ]; then
  echo 'Existing Hermes source cannot be proven without Python; no setup changes were made.' >&2
  exit 1
fi
''';

/// Captures immutable absence/preexistence before the first setup mutation.
/// A server without Python can still prepare it, but its package origin cannot
/// be reconstructed later and those system packages are deliberately retained.
String get remoteOwnershipCaptureScript =>
    '''
if command -v python3 >/dev/null; then
  ${_recipe({'mode': 'capture'})}
else
  echo 'Python is not installed; system dependency provenance is unavailable and those packages will be preserved during uninstall.'
fi
''';

/// Binds newly created resources to their post-install identities, without
/// claiming resources present in the original read-only baseline.
String get remoteOwnershipCheckpointScript => _recipe({'mode': 'checkpoint'});

/// Journals a specific mutation before it starts; status-only retries cannot
/// silently claim replacement directories or Docker assets.
String remoteOwnershipMutationScript(
  Set<String> paths, {
  bool account = false,
  bool computer = false,
  bool web = false,
  bool caddy = false,
}) => _recipe({
  'mode': 'mutation',
  'paths': paths.toList()..sort(),
  'account': account,
  'computer': computer,
  'web': web,
  'caddy': caddy,
});

/// Inspects the real Docker store after daemon startup, before creating assets.
String get recordRemoteDockerBaselineScript =>
    _recipe({'mode': 'dockerBaseline'});

/// Records exact installer-added UFW commands after the firewall is committed.
String recordRemoteFirewallOwnershipScript(Set<int> sshPorts) =>
    _recipe({'mode': 'firewall', 'sshPorts': sshPorts.toList()..sort()});

String get remoteUninstallInventoryScript => _recipe({'mode': 'inspect'});

String remoteUninstallScript(String revision, {required bool purge}) =>
    exclusiveRemoteOperationCommand(
      _recipe({'mode': 'remove', 'revision': revision, 'purge': purge}),
      1800,
    );

String _recipe(Map<String, Object?> request) =>
    'python3 -I -B -c ${shellQuote(_program)} ${shellQuote(jsonEncode({
      ...request,
      'dashboardService': '$dashboardService\n',
      'gatewayService': '$gatewayService\n',
      'releaseCommit': hermesReleaseCommit,
      'installerHash': hermesInstallShSha256,
      'packages': [...prerequisitePackages, 'ufw', 'docker.io', 'caddy'],
    }))}';

// No installed Python/plugin modules are imported. All deletion is descriptor-
// relative with O_NOFOLLOW; directory symlinks are unlinked, never traversed.
const _program = r'''
import collections, contextlib, fcntl, hashlib, json, os, pwd, re, secrets, shlex, shutil, stat, subprocess, sys

REQUEST = json.loads(sys.argv[1])
ROOT = "/var/lib/hermuse-provision"
JOURNAL = ROOT + "/ownership.json"
LOCK = ROOT + "/operation.lock"
HOME = "/home/hermes"
HERMES = HOME + "/.hermes"
CHECKOUT = HERMES + "/hermes-agent"
PLUGIN = HERMES + "/plugins/hermuse"
SERVICE = "/etc/systemd/system/hermuse-dashboard.service"
GATEWAY = "/etc/systemd/system/hermuse-gateway.service"
CADDY = "/etc/caddy/Caddyfile"
SITE = "/etc/caddy/hermuse-remote.caddy"
IMPORT = "import /etc/caddy/hermuse-remote.caddy"
CONTAINER = "hermuse-computer-hermes"
VOLUME = CONTAINER + "-home"
COMPUTER_IMAGE = r"(?:ghcr\.io/yellow-stick/)?hermuse-computer:[a-zA-Z0-9_.-]+"
WEB_CONTAINER = "hermuse-web"
WEB_LABEL = ("org.hermuse.remote-installer", "web-v1")
WEB_IMAGE = r"ghcr\.io/yellow-stick/hermuse-web:[a-zA-Z0-9_.-]+"
RUNTIME_PATHS = [HOME + "/.local/bin/hermes", HOME + "/.local/bin/hermes-agent", HOME + "/.local/bin/hermes-acp",
                 HOME + "/.local/bin/node", HOME + "/.local/bin/npm", HOME + "/.local/bin/npx", PLUGIN, CHECKOUT,
                 HERMES + "/bin", HERMES + "/node", HERMES + "/runtime", HOME + "/.local/share/uv",
                 ROOT + "/dashboard.env"]
CACHE_PATHS = [HOME + "/.cache/uv", HOME + "/.cache/pip", HOME + "/.cache/npm",
               HOME + "/.cache/ms-playwright", HOME + "/.npm"]
PATH_KINDS = {**{path: "runtime" for path in RUNTIME_PATHS},
              **{path: "cache" for path in CACHE_PATHS}, HERMES: "data"}
DEFAULTS = [".bashrc", ".profile", ".bash_logout"]
O_DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
ROOT_UID = 0
LAST_OBSERVED = {}

class UnsafePath(Exception):
    pass

@contextlib.contextmanager
def parent(path):
    if not path.startswith("/") or any(part in (".", "..") for part in path.split("/")):
        raise UnsafePath("Unsafe resource path: " + path)
    parts = [part for part in path.split("/") if part]
    fd = os.open("/", O_DIRECTORY)
    try:
        for part in parts[:-1]:
            try:
                child = os.open(part, O_DIRECTORY, dir_fd=fd)
            except FileNotFoundError:
                yield None, parts[-1]
                return
            except OSError as error:
                raise UnsafePath("Refusing a symlink/non-directory ancestor of " + path) from error
            os.close(fd)
            fd = child
        yield fd, parts[-1]
    finally:
        os.close(fd)

def info(path, digest=False):
    try:
        with parent(path) as (fd, name):
            if fd is None:
                return None
            try:
                value = os.stat(name, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                return None
            result = {"dev": value.st_dev, "ino": value.st_ino, "uid": value.st_uid, "gid": value.st_gid,
                      "mode": value.st_mode, "size": value.st_size, "mtime": value.st_mtime_ns}
            if stat.S_ISLNK(value.st_mode):
                result["link"] = os.readlink(name, dir_fd=fd)
            elif digest and stat.S_ISREG(value.st_mode):
                result["sha256"] = hashlib.sha256(read(path)).hexdigest()
            return result
    except UnsafePath:
        return {"unsafe": True}

def read(path):
    with parent(path) as (fd, name):
        if fd is None:
            raise FileNotFoundError(path)
        handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
        try:
            value = os.fstat(handle)
            if not stat.S_ISREG(value.st_mode) or value.st_size > 4 * 1024 * 1024:
                raise UnsafePath("Not a bounded regular file: " + path)
            data = bytearray()
            while True:
                chunk = os.read(handle, 65536)
                if not chunk:
                    return bytes(data)
                data.extend(chunk)
                if len(data) > 4 * 1024 * 1024:
                    raise UnsafePath("Oversized resource file: " + path)
        finally:
            os.close(handle)

def text(path):
    return read(path).decode("utf-8")

def write(path, data, metadata=None):
    with parent(path) as (fd, name):
        if fd is None:
            raise UnsafePath("Missing resource parent: " + path)
        current = info(path)
        if current and (current.get("unsafe") or not stat.S_ISREG(current["mode"])):
            raise UnsafePath("Refusing to replace a symlink/non-file: " + path)
        previous = metadata or current
        temporary = ".hermuse-write-" + secrets.token_hex(12)
        handle = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
        try:
            with os.fdopen(handle, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
                if previous:
                    os.fchown(stream.fileno(), previous["uid"], previous["gid"])
                    os.fchmod(stream.fileno(), stat.S_IMODE(previous["mode"]))
            os.rename(temporary, name, src_dir_fd=fd, dst_dir_fd=fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=fd)
            except FileNotFoundError:
                pass

def root_file(path):
    value = info(path)
    return bool(value and not value.get("unsafe") and stat.S_ISREG(value["mode"])
                and value["uid"] == ROOT_UID and value["mode"] & 0o022 == 0)

def same_identity(left, right):
    return bool(left and right and not right.get("unsafe") and all(
        left.get(key) == right.get(key) for key in ("dev", "ino", "uid"))
        and stat.S_IFMT(left.get("mode", 0)) == stat.S_IFMT(right.get("mode", 0))
        and left.get("link") == right.get("link"))

def command(args, required=True, timeout=30):
    result = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            timeout=timeout, env={**os.environ, "LC_ALL": "C"})
    if required and result.returncode:
        raise RuntimeError(args[0] + " failed: " + result.stderr.strip()[:1000])
    return result

def active(unit):
    return bool(shutil.which("systemctl") and command(
        ["systemctl", "is-active", "--quiet", unit], required=False).returncode == 0)

def account():
    try:
        value = pwd.getpwnam("hermes")
        return {"uid": value.pw_uid, "gid": value.pw_gid, "home": value.pw_dir, "shell": value.pw_shell}
    except KeyError:
        return None

def owned_user():
    user = account()
    home = info(HOME)
    return bool(user and user["uid"] != 0 and user["home"] == HOME and root_file(ROOT + "/owns-hermes")
                and home and not home.get("unsafe") and stat.S_ISDIR(home["mode"])
                and home["uid"] == user["uid"])

def journal():
    if not info(JOURNAL):
        return {}, None
    if not root_file(JOURNAL):
        return {}, "The ownership journal is not a trusted root-owned regular file."
    try:
        value = json.loads(read(JOURNAL))
        if value.get("schemaVersion") != 1 or not isinstance(value.get("paths"), dict):
            raise ValueError()
        return value, None
    except (ValueError, TypeError, AttributeError, UnsafePath):
        return {}, "The ownership journal is invalid; historical ownership cannot be reconstructed safely."

def ensure_root():
    with parent(ROOT) as (fd, name):
        if fd is None:
            raise UnsafePath("Missing /var/lib for installer ownership.")
        try:
            os.mkdir(name, 0o711, dir_fd=fd)
        except FileExistsError:
            pass
        handle = os.open(name, O_DIRECTORY, dir_fd=fd)
        try:
            value = os.fstat(handle)
            if value.st_uid != ROOT_UID or value.st_mode & 0o022:
                raise UnsafePath("Installer ownership directory must be root-owned and not writable by others.")
        finally:
            os.close(handle)

def save(value):
    ensure_root()
    write(JOURNAL, (json.dumps(value, sort_keys=True) + "\n").encode())

def firewall():
    if not shutil.which("ufw"):
        return {"available": False, "active": False, "rules": []}
    result = command(["ufw", "show", "added"], required=False)
    status = command(["ufw", "status"], required=False)
    if result.returncode or status.returncode:
        return {"available": True, "error": "UFW could not be inspected without changing it."}
    return {"available": True, "active": status.stdout.startswith("Status: active"),
            "rules": [line.strip() for line in result.stdout.splitlines() if line.strip().startswith("ufw ")],
            "files": {path: info(path, digest=True) for path in (
                "/etc/ufw/user.rules", "/etc/ufw/user6.rules", "/etc/default/ufw", "/etc/ufw/ufw.conf")}}

def installed_packages():
    if not shutil.which("dpkg-query"):
        return []
    return [package for package in REQUEST["packages"] if command(
        ["dpkg-query", "-W", "-f=${db:Status-Status}", package], required=False).stdout.strip() == "installed"]

def docker_inspect(kind, name):
    result = command(["docker", "inspect", "--type", kind, name], required=False)
    if result.returncode:
        if "No such" in result.stderr or "not found" in result.stderr:
            return None
        raise RuntimeError("Docker inspection is unavailable; existing resources were preserved.")
    value = json.loads(result.stdout)
    if not isinstance(value, list) or len(value) != 1:
        raise RuntimeError("Docker returned an ambiguous resource identity.")
    item = value[0]
    if kind == "container":
        return {"id": item["Id"], "image": item.get("Config", {}).get("Image", ""),
                "imageId": item.get("Image"), "mounts": item.get("Mounts", []),
                "ports": item.get("HostConfig", {}).get("PortBindings", {}),
                "name": item.get("Name", ""), "labels": item.get("Config", {}).get("Labels") or {}}
    if kind == "image":
        return {"id": item["Id"], "tags": item.get("RepoTags", [])}
    return {"name": item.get("Name"), "created": item.get("CreatedAt"), "labels": item.get("Labels")}

def docker():
    if not shutil.which("docker"):
        return {"available": False}
    try:
        container = docker_inspect("container", CONTAINER)
        volume = docker_inspect("volume", VOLUME)
        tags = command(["docker", "image", "ls", "--format", "{{.Repository}}:{{.Tag}}"], required=False)
        if tags.returncode:
            raise RuntimeError("Docker daemon is unavailable; computer assets cannot be inspected.")
        images = {tag: docker_inspect("image", tag) for tag in tags.stdout.splitlines()
                  if re.fullmatch(COMPUTER_IMAGE, tag)}
        refs = command(["docker", "ps", "-a", "--filter", "volume=" + VOLUME,
                        "--format", "{{.ID}}"], required=True).stdout.splitlines() if volume else []
        return {"available": True, "container": container, "volume": volume,
                "images": images, "volumeReferences": refs}
    except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired):
        return {"available": True, "error": "Docker is unavailable or ambiguous; no Docker resources will be changed."}

def web_docker():
    if not shutil.which("docker"):
        return {"available": False}
    try:
        container = docker_inspect("container", WEB_CONTAINER)
        tags = command(["docker", "image", "ls", "--format", "{{.Repository}}:{{.Tag}}"], required=False)
        if tags.returncode:
            raise RuntimeError("Docker daemon is unavailable; web app assets cannot be inspected.")
        images = {tag: docker_inspect("image", tag) for tag in tags.stdout.splitlines()
                  if re.fullmatch(WEB_IMAGE, tag)}
        return {"available": True, "container": container, "images": images}
    except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired):
        return {"available": True, "error": "Docker is unavailable or ambiguous; no web app Docker resources will be changed."}

def web_complete(value):
    return (value.get("available") is True and not value.get("error")
            and all(key in value for key in ("container", "images")))

def web_labelled(container):
    return bool(container) and (container.get("labels") or {}).get(WEB_LABEL[0]) == WEB_LABEL[1]

def created_image(value, tag):
    return value.get("webImagesCreated" if re.fullmatch(WEB_IMAGE, tag) else "imagesCreated", {}).get(tag)

def import_count():
    try:
        return sum(line == IMPORT for line in text(CADDY).splitlines())
    except (OSError, UnicodeError, UnsafePath):
        return None

def installer_assets():
    result = {}
    if not info(ROOT):
        return result
    allowed = {
        "installer": {"install.sh", "install.sh.partial"},
        "firewall": {"lock", "previous", "ufw.tar", "rollback.sh", "armed", "committed", "restored"},
        "caddy": {"lock", "Caddyfile", "site", "was-active", "was-enabled", "rollback.sh", "armed", "committed", "restored"},
    }
    try:
        with parent(ROOT + "/placeholder") as (fd, _):
            if fd is None:
                return result
            names = os.listdir(fd)
        for name in names:
            if not re.fullmatch(r"[a-zA-Z0-9]{20}", name):
                continue
            path = ROOT + "/" + name
            identity = info(path)
            if not identity or identity.get("unsafe") or not stat.S_ISDIR(identity["mode"]) or identity["uid"] != ROOT_UID:
                result[path] = None
                continue
            safe = True
            with parent(path + "/placeholder") as (fd, _):
                if fd is None:
                    continue
                children = os.listdir(fd)
            for child in children:
                if child not in allowed:
                    safe = False
                    break
                with parent(path + "/" + child + "/placeholder") as (fd, _):
                    if fd is None:
                        safe = False
                        break
                    entries = os.listdir(fd)
                if set(entries) - allowed[child] or any(not root_file(path + "/" + child + "/" + entry) for entry in entries):
                    safe = False
                    break
            result[path] = identity if safe else None
    except (OSError, UnsafePath):
        return result
    return result

def plugin_assets():
    result = []
    try:
        with parent(PLUGIN) as (fd, _):
            if fd is None:
                return result
            for name in os.listdir(fd):
                if re.fullmatch(r"hermuse\.(?:next|previous)-[a-zA-Z0-9]{20}", name):
                    result.append(HERMES + "/plugins/" + name)
    except (OSError, UnsafePath):
        pass
    return result

def capture():
    previous, error = journal()
    if error:
        raise RuntimeError(error)
    if previous:
        # New canonical resources get a baseline before their first mutation;
        # an already-present unrecorded token is never silently claimed.
        added = False
        if previous.pop("connectionOnly", False):
            # Connection grants only a credential. Establish other baselines
            # now, at the first actual provisioning attempt, never retroactively.
            previous["firewallBefore"] = firewall()
            previous["dockerBefore"] = docker()
            previous["packagesBefore"] = installed_packages()
            previous["assetsBefore"] = list(installer_assets())
            previous["assetsCreated"] = {}
            previous["configBeforeAbsent"] = info(HERMES + "/config.yaml") is None
            previous["caddy"] = {"importBefore": import_count(), "siteBefore": info(SITE, digest=True)}
            added = True
        for path, kind in PATH_KINDS.items():
            if path not in previous["paths"]:
                previous["paths"][path] = {"created": info(path) is None, "kind": kind, "identity": None}
                added = True
        if added:
            save(previous)
        return previous
    ensure_root()
    user = account()
    value = {"schemaVersion": 1, "legacy": owned_user(),
             "user": {"created": user is None, "identity": None, "defaults": {}},
             "paths": {path: {"created": info(path) is None, "kind": kind, "identity": None}
                       for path, kind in PATH_KINDS.items()},
             "caddy": {"importBefore": import_count(), "siteBefore": info(SITE, digest=True)},
             "firewallBefore": firewall(), "dockerBefore": docker(), "packagesBefore": installed_packages(),
             "assetsBefore": list(installer_assets()), "assetsCreated": {},
             "configBeforeAbsent": info(HERMES + "/config.yaml") is None}
    save(value)
    return value

def docker_complete(value):
    return (value.get("available") is True and not value.get("error")
            and all(key in value for key in ("container", "volume", "images", "volumeReferences")))

def docker_baseline():
    value = capture()
    current = docker()
    if not docker_complete(current):
        raise RuntimeError("Docker assets could not be inventoried before creation; no ownership was assumed.")
    if "computerBefore" not in value:
        value["computerBefore"] = current
    save(value)

def current_attempt():
    owner = ROOT + "/operation.owner"
    if not root_file(owner):
        raise RuntimeError("No trusted setup admission receipt exists for this mutation.")
    fields = text(owner).split()
    if len(fields) != 3 or not re.fullmatch(r"[0-9]+-[0-9]+", fields[0]) or not all(
            field.isdecimal() for field in fields[1:]):
        raise RuntimeError("The setup admission receipt is invalid.")
    try:
        with open("/proc/" + fields[1] + "/stat") as handle:
            process = handle.read().rsplit(") ", 1)[1].split()
        inherited = os.fstat(7)
        lock = info(LOCK)
        if process[0] == "Z" or process[19] != fields[2] or not root_file(LOCK) or (
                inherited.st_dev, inherited.st_ino) != (lock["dev"], lock["ino"]):
            raise RuntimeError("The admitted setup attempt is no longer live.")
        fcntl.flock(7, fcntl.LOCK_SH | fcntl.LOCK_NB)
    except (OSError, IndexError) as error:
        raise RuntimeError("The admitted setup attempt or inherited lock is unavailable.") from error
    return fields

def mutation():
    value = capture()
    attempt = current_attempt()
    pending = value.get("pending", {})
    if pending.get("attempt") != attempt:
        pending = {"attempt": attempt, "paths": {}, "assetsBefore": list(installer_assets())}
        value["pending"] = pending
    for path in REQUEST["paths"]:
        if path not in PATH_KINDS:
            raise UnsafePath("Unsupported ownership mutation path.")
        entry = value["paths"][path]
        current = info(path, digest=True)
        expected = entry.get("identity")
        if expected and current and not same_identity(expected, current):
            raise UnsafePath("An owned resource was replaced outside setup; it was not claimed or modified: " + path)
        if path == CHECKOUT and current and not setup_checkout_owned(value):
            raise UnsafePath("Existing Hermes source ownership is unproven; it was not modified.")
        if entry["created"] and expected is None and current and path not in pending["paths"] and (
                path in RUNTIME_PATHS and path != HOME + "/.local/share/uv" or path == HERMES):
            raise UnsafePath("An unbound resource appeared outside this admitted attempt; it was not claimed or modified: " + path)
        if entry["created"] and (expected or current is None or path in pending["paths"]):
            pending["paths"].setdefault(path, current)
    if REQUEST["account"] and value["user"]["created"] and value["user"]["identity"] is None and account() is None:
        pending["account"] = True
    if REQUEST["computer"]:
        current = docker()
        if not docker_complete(current):
            raise RuntimeError("The real Docker store cannot be inspected before computer mutation.")
        expected = value.get("dockerAfter", {})
        if value.get("containerCreated") and current.get("container") and (expected.get("container") or {}).get("id") != current["container"]["id"]:
            raise RuntimeError("The owned computer was replaced; no new container ownership was claimed.")
        if value.get("volumeCreated") and current.get("volume") and current["volume"] != expected.get("volume"):
            raise RuntimeError("The owned computer volume identity changed; it was not claimed.")
        for tag, image in value.get("imagesCreated", {}).items():
            if tag in current["images"] and image.get("id") != current["images"][tag].get("id"):
                raise RuntimeError("An owned computer image tag was replaced; it was not claimed.")
        pending["computer"] = current
    if REQUEST["web"]:
        current = web_docker()
        if not web_complete(current):
            raise RuntimeError("The real Docker store cannot be inspected before web app mutation.")
        pending["web"] = current
    if REQUEST["caddy"]:
        expected = value.get("caddy", {}).get("siteAfter")
        current = info(SITE, digest=True)
        if expected and current and not same_identity(expected, current):
            raise RuntimeError("The recorded Caddy fragment inode was replaced outside setup; it was not claimed.")
        pending["caddy"] = True
    save(value)

def checkpoint():
    value = capture()
    pending = value.pop("pending", {})
    if pending.get("attempt") != current_attempt():
        pending = {}
    user = value["user"]
    if pending.get("account") and user["identity"] is None and owned_user():
        user["identity"] = account()
        user["defaults"] = {name: info(HOME + "/" + name, digest=True) for name in DEFAULTS}
    for path in pending.get("paths", {}):
        entry = value["paths"][path]
        current = info(path, digest=True)
        if entry["created"] and current and not current.get("unsafe"):
            entry["identity"] = current
            entry["removed"] = False
    if pending.get("caddy"):
        count = import_count()
        value["caddy"]["importAdded"] = value["caddy"].get("importBefore") == 0 and count == 1
        if root_file(SITE):
            value["caddy"]["siteAfter"] = info(SITE, digest=True)
    before = pending.get("computer")
    if before:
        current = docker()
        if docker_complete(before) and docker_complete(current):
            prior = value.setdefault("dockerAfter", {})
            if before.get("container") is None or value.get("containerCreated"):
                if current.get("container"):
                    prior["container"] = current["container"]
                    value["containerCreated"] = True
            if before.get("volume") is None and current.get("volume"):
                prior["volume"] = current["volume"]
                value["volumeCreated"] = True
            images = value.setdefault("imagesCreated", {})
            for tag, item in current.get("images", {}).items():
                if tag not in before["images"] or tag in images and images[tag].get("id") == before["images"][tag].get("id"):
                    images[tag] = item
    web_before = pending.get("web")
    if web_before:
        current = web_docker()
        if web_complete(web_before) and web_complete(current):
            after = value.setdefault("webAfter", {})
            recorded = (after.get("container") or {}).get("id")
            prior = web_before.get("container")
            created = current.get("container")
            # Only a labelled container replacing nothing, or replacing the
            # recorded one, is claimed; an unrecorded predecessor stays unproven.
            if web_labelled(created) and (prior is None or recorded and prior["id"] == recorded):
                after["container"] = created
                value["webContainerCreated"] = True
            images = value.setdefault("webImagesCreated", {})
            for tag, item in current["images"].items():
                previous = web_before["images"].get(tag)
                if previous is None or tag in images and images[tag].get("id") == previous.get("id"):
                    images[tag] = item
    if pending.get("caddy"):
        for path, identity in installer_assets().items():
            if identity and path not in pending["assetsBefore"] and path not in value.get("assetsBefore", []):
                value.setdefault("assetsCreated", {}).setdefault(path, identity)
    if PLUGIN in pending.get("paths", {}) or before:
        value["configRemoved"] = False
    value["packagesAdded"] = [package for package in installed_packages()
                               if package not in value.get("packagesBefore", [])]
    save(value)
    return value

def record_firewall():
    value = capture()
    before = value.get("firewallBefore", {})
    after = firewall()
    known = not before.get("error") and isinstance(before.get("rules"), list) and not after.get("error")
    difference = collections.Counter(after.get("rules", [])) - collections.Counter(before.get("rules", [])) if known else {}
    value["firewall"] = {"before": before, "after": after, "unknown": not known,
                         "added": list(difference.elements()) if known else [], "sshPorts": REQUEST["sshPorts"]}
    save(value)

def lock_file(create=False):
    if create:
        ensure_root()
    with parent(LOCK) as (fd, name):
        if fd is None or (not create and not info(LOCK)):
            return None
        value = info(LOCK)
        if value and not root_file(LOCK):
            raise UnsafePath("The operation lock is not a trusted root-owned regular file.")
        return os.open(name, os.O_RDWR | os.O_NOFOLLOW | (os.O_CREAT if create else 0), 0o600, dir_fd=fd)

def transaction_active(own_lock=False):
    if not own_lock:
        handle = lock_file()
        if handle is not None:
            try:
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    return True
            finally:
                os.close(handle)
    return any(active(unit + suffix) for unit in ("hermuse-firewall-rollback", "hermuse-caddy-rollback")
               for suffix in (".timer", ".service"))

def legacy_checkout():
    user = account()
    directory = info(CHECKOUT)
    marker_path = CHECKOUT + "/.hermes-bootstrap-complete"
    marker_info = info(marker_path)
    if not owned_user() or not user or not directory or directory.get("unsafe") or not stat.S_ISDIR(
            directory["mode"]) or directory["uid"] != user["uid"] or not marker_info or marker_info.get(
            "unsafe") or not stat.S_ISREG(marker_info["mode"]) or marker_info["uid"] != user["uid"]:
        return False
    try:
        marker = json.loads(read(marker_path))
        if marker.get("schemaVersion") != 1 or marker.get("pinnedCommit") != REQUEST["releaseCommit"]:
            return False
        for relative in ("hermes_cli/main.py", "run_agent.py", "pyproject.toml"):
            item = info(CHECKOUT + "/" + relative)
            if not item or item.get("unsafe") or not stat.S_ISREG(item["mode"]) or item["uid"] != user["uid"]:
                return False
        origin = command(["runuser", "-u", "hermes", "--", "git", "-C", CHECKOUT,
                          "remote", "get-url", "origin"], required=False)
        return origin.returncode == 0 and origin.stdout.strip() in (
            "https://github.com/NousResearch/hermes-agent.git", "git@github.com:NousResearch/hermes-agent.git")
    except (OSError, ValueError, AttributeError, UnsafePath):
        return False

def setup_checkout_owned(value):
    entry = value.get("paths", {}).get(CHECKOUT, {})
    if path_owned(CHECKOUT, value):
        return True
    if entry.get("identity") or entry.get("created"):
        return False
    return legacy_checkout()

def setup_preflight():
    value, problem = journal()
    if problem:
        raise UnsafePath(problem)
    current = info(CHECKOUT)
    if current and (current.get("unsafe") or not setup_checkout_owned(value)):
        raise UnsafePath("Existing Hermes source is not an identified installer checkout or proven official legacy source; no setup changes were made.")

def path_owned(path, value):
    item = info(path)
    entry = value.get("paths", {}).get(path, {})
    if not item or item.get("unsafe"):
        return False
    if entry.get("created") and same_identity(entry.get("identity"), item):
        return True
    approved = value.get("legacyRemovablePaths", {}).get(path)
    if approved and same_identity(approved, item):
        return True
    if entry or value.get("connectionOnly"):
        return False
    if path == PLUGIN or path in plugin_assets():
        marker = info(path + "/.hermuse-remote-managed")
        user = account()
        return (owned_user() and user and item["uid"] == user["uid"] and stat.S_ISDIR(item["mode"])
                and marker and not marker.get("unsafe") and stat.S_ISREG(marker["mode"]) and marker["uid"] == user["uid"])
    if path == CHECKOUT:
        return legacy_checkout()
    if path in [HOME + "/.local/bin/" + name for name in ("hermes", "hermes-agent", "hermes-acp")] and legacy_checkout() and stat.S_ISREG(item["mode"]):
        try:
            body = text(path)
            return CHECKOUT in body and "hermes" in body and len(body) < 4096
        except (OSError, UnsafePath, UnicodeError):
            return False
    return False
def data_root_safe(value, usage=None):
    usage = usage or service_usage()
    if usage["account"] or usage["runtime"]:
        return False, usage["reason"]
    for path in [*RUNTIME_PATHS, *plugin_assets()]:
        if path.startswith(HERMES + "/") and info(path) and not path_owned(path, value):
            return False, "Purge preserves this parent because a descendant is unowned or replaced: " + path
    known = {"hermes-agent", "bin", "node", "runtime", "plugins", "cron", "sessions", "logs", "pairing", "hooks",
             "image_cache", "audio_cache", "memories", "skills", "hermuse", "config.yaml", ".env", "SOUL.md",
             ".no-bundled-skills", "auth.json", "state.db", "state.db-wal", "state.db-shm", "sessions.db",
             "sessions.db-wal", "sessions.db-shm", "cache", "credentials.json"}
    try:
        with parent(HERMES + "/placeholder") as (fd, _):
            if fd is None:
                return False, "The data root is unavailable."
            extras = set(os.listdir(fd)) - known
            if extras:
                return False, "Purge preserves unknown data-root entries: " + ", ".join(sorted(extras))
        with parent(PLUGIN) as (fd, _):
            if fd is not None:
                for name in os.listdir(fd):
                    path = HERMES + "/plugins/" + name
                    if path != PLUGIN and path not in plugin_assets():
                        return False, "Purge preserves an unrelated plugin: " + path
    except (OSError, UnsafePath):
        return False, "A data-root descendant cannot be safely inspected."
    return True, None


def site_text(value):
    expected = value.get("caddy", {}).get("siteAfter")
    current = info(SITE, digest=True)
    if not root_file(SITE) or not expected or not current or expected.get("sha256") != current.get("sha256"):
        return None
    try:
        return text(SITE)
    except (OSError, UnsafePath, UnicodeError):
        return None

# Exactly the dashboard site, optionally followed by the web app site on the
# derived app.<dashboard> host; nothing else.
SITE_PATTERN = (r"# Managed by Hermuse remote installer\n"
                r"([a-zA-Z0-9.-]+) \{\n  vars hermuse_remote_installer v1\n  reverse_proxy 127\.0\.0\.1:9119\n\}\n"
                r"(app\.\1 \{\n  vars hermuse_remote_installer v1\n  reverse_proxy 127\.0\.0\.1:9120\n\}\n)?")

def site_owned(value):
    body = site_text(value)
    return bool(body is not None and re.fullmatch(SITE_PATTERN, body))

def site_publishes_web(value):
    body = site_text(value)
    match = re.fullmatch(SITE_PATTERN, body) if body is not None else None
    return bool(match and match[2])

def service_owned():
    if not root_file(SERVICE):
        return False
    try:
        expected = REQUEST["dashboardService"]
        previous = expected.replace("EnvironmentFile=-/var/lib/hermuse-provision/dashboard.env\n", "")
        if text(SERVICE).rstrip("\n") not in (expected.rstrip("\n"), previous.rstrip("\n")):
            return False
        if shutil.which("systemctl"):
            result = command(["systemctl", "show", "hermuse-dashboard.service", "--property=DropInPaths", "--value"], required=False)
            if result.returncode or result.stdout.strip():
                return False
        return True
    except (OSError, UnsafePath, UnicodeError):
        return False

def gateway_owned():
    if not root_file(GATEWAY):
        return False
    try:
        if text(GATEWAY).rstrip("\n") != REQUEST["gatewayService"].rstrip("\n"):
            return False
        if shutil.which("systemctl"):
            result = command(["systemctl", "show", "hermuse-gateway.service", "--property=DropInPaths", "--value"], required=False)
            if result.returncode or result.stdout.strip():
                return False
        return True
    except (OSError, UnsafePath, UnicodeError):
        return False

def caddy_source_safe():
    if not active("caddy"):
        return True
    result = command(["systemctl", "show", "caddy", "--property=ExecStart", "--value"], required=False)
    return result.returncode == 0 and CADDY in result.stdout

def service_usage():
    result = command(["systemctl", "list-unit-files", "--type=service", "--no-legend", "--no-pager"], required=False)
    if result.returncode:
        return {"account": True, "runtime": True, "reason": "Effective systemd dependencies could not be completely inspected."}
    loaded = command(["systemctl", "list-units", "--all", "--type=service", "--plain", "--no-legend", "--no-pager"], required=False)
    if loaded.returncode:
        return {"account": True, "runtime": True, "reason": "Loaded systemd dependencies could not be completely inspected."}
    user = account()
    used_account = False
    used_runtime = False
    identities = {"hermes", str(user["uid"]), str(user["gid"])} if user else {"hermes"}
    names = set()
    for line in (result.stdout + "\n" + loaded.stdout).splitlines():
        if not line.strip():
            continue
        name = line.split()[0] if line.split() else ""
        if not re.fullmatch(r"[a-zA-Z0-9_.@:-]+\.service", name):
            return {"account": True, "runtime": True, "reason": "Systemd returned an ambiguous unit inventory."}
        names.add(name)
    for name in sorted(names):
        if name == "hermuse-dashboard.service" and service_owned():
            continue
        if name == "hermuse-gateway.service" and gateway_owned():
            continue
        if name.endswith("@.service"):
            # Bare templates cannot be queried with `show`. Read all fragments
            # and drop-ins conservatively; instantiated units are checked below
            # with systemd's effective, expanded properties.
            template = command(["systemctl", "cat", name], required=False)
            if template.returncode:
                return {"account": True, "runtime": True, "reason": "A systemd template dependency could not be inspected."}
            if any(re.search(r"(?<![A-Za-z0-9_])" + re.escape(identity) + r"(?![A-Za-z0-9_])", template.stdout) for identity in identities):
                used_account = True
                used_runtime = True
            continue
        effective = command(["systemctl", "show", name, "--property=User,Group,ExecStart,Environment,WorkingDirectory"], required=False)
        if effective.returncode:
            return {"account": True, "runtime": True, "reason": "A stopped systemd dependency could not be inspected."}
        fields = dict(line.split("=", 1) for line in effective.stdout.splitlines() if "=" in line)
        if fields.get("User") in identities or fields.get("Group") in identities:
            used_account = True
        if any(path in effective.stdout for path in (CHECKOUT, HOME + "/.local/bin/hermes", HERMES + "/node")):
            used_runtime = True
    return {"account": used_account, "runtime": used_runtime,
            "reason": "Another installed systemd service uses the account/runtime, including stopped units and effective drop-ins."}

def external_runtime():
    usage = service_usage()
    return usage["account"] or usage["runtime"]

def resource(identifier, label, kind, removable, reason, purge=False, managed=True):
    return {"id": identifier, "label": label, "kind": kind, "removable": bool(removable),
            "purgeOnly": purge, "reason": reason, "managed": bool(managed)}

def user_safe(value, usage=None):
    entry = value.get("user", {})
    user = account()
    if not entry.get("created") or entry.get("identity") != user or not owned_user():
        return False, "The dedicated account's original UID/home identity is not proven; it will not be deleted."
    if mount_boundary(HOME):
        return False, "The account home contains a mount boundary; preserve the account and mounted files."
    groups = command(["id", "-Gn", "hermes"], required=False)
    if groups.returncode or set(groups.stdout.split()) - {"hermes", "docker"}:
        return False, "Account group membership is no longer exclusive to Hermuse; preserve the account."
    if info("/var/spool/cron/crontabs/hermes"):
        return False, "The account has an external crontab; preserve the account."
    usage = usage or service_usage()
    if usage["account"] or usage["runtime"]:
        return False, usage["reason"]
    allowed = {".hermes", ".local", ".cache", ".npm", *DEFAULTS}
    try:
        with parent(HOME + "/placeholder") as (fd, _):
            if fd is None:
                return False, "The account home could not be inspected."
            extras = set(os.listdir(fd)) - allowed
        if extras:
            return False, "Unrelated home entries must be preserved: " + ", ".join(sorted(extras))
        for directory, allowed_children in {
                HOME + "/.local": {"bin", "share"},
                HOME + "/.local/bin": {"hermes", "hermes-agent", "hermes-acp", "node", "npm", "npx"},
                HOME + "/.local/share": {"uv"},
                HOME + "/.cache": {"uv", "pip", "npm", "ms-playwright"}}.items():
            if not info(directory):
                continue
            with parent(directory + "/placeholder") as (fd, _):
                if fd is None or set(os.listdir(fd)) - allowed_children:
                    return False, "Unrelated files below " + directory + " require preserving the account and home."
            for child in allowed_children:
                candidate = directory + "/" + child
                if candidate in PATH_KINDS and info(candidate) and not path_owned(candidate, value):
                    return False, "An unproven runtime/cache below the home requires preserving the dedicated account."
        for name in DEFAULTS:
            current = info(HOME + "/" + name, digest=True)
            expected = entry.get("defaults", {}).get(name)
            if current and (not expected or current.get("sha256") != expected.get("sha256")):
                return False, "A shell startup file differs from the account's original default; the account and home will be preserved."
        return True, "Purge deletes this dedicated account only after its owned data is removed, no processes remain and the home is empty."
    except (OSError, UnsafePath):
        return False, "The dedicated home contains an unsafe or unreadable path."

def rule_port(rule):
    try:
        words = shlex.split(rule)
        if len(words) == 5 and words[:2] == ["ufw", "allow"] and words[3:] == ["comment", "Hermuse remote setup"]:
            match = re.fullmatch(r"([0-9]{1,5})/tcp", words[2])
            if match and 1 <= int(match[1]) <= 65535:
                return int(match[1])
    except ValueError:
        pass
    return None

def firewall_equal(left, right):
    def stable(value):
        return {"active": value.get("active"), "rules": value.get("rules"),
                "files": {path: item.get("sha256") if item and not item.get("unsafe") else None
                          for path, item in value.get("files", {}).items()}}
    return not left.get("error") and not right.get("error") and stable(left) == stable(right)

def shared_caddy():
    try:
        return bool("\n".join(line for line in text(CADDY).splitlines()
                    if line.strip() and not line.lstrip().startswith("#") and line != IMPORT))
    except (OSError, UnicodeError, UnsafePath):
        return True
def mount_boundary(path):
    try:
        with open("/proc/self/mountinfo") as stream:
            for line in stream:
                fields = line.split()
                if len(fields) < 5:
                    return True
                mount = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), fields[4])
                if mount == path or mount.startswith(path.rstrip("/") + "/"):
                    return True
    except OSError:
        return True
    return False

def mount_id(fd):
    with open("/proc/self/fdinfo/" + str(fd)) as stream:
        for line in stream:
            if line.startswith("mnt_id:"):
                return int(line.split(":", 1)[1])
    raise UnsafePath("The filesystem mount boundary could not be proven.")


def inventory(own_lock=False):
    value, problem = journal()
    resources = []
    observed = {path: info(path, digest=True) for path in [*PATH_KINDS, SERVICE, GATEWAY, SITE, CADDY, JOURNAL, ROOT + "/owns-hermes"]}
    usage = service_usage()
    observed["serviceUsage"] = usage
    if problem:
        resources.append(resource("ownership", JOURNAL, "ownership", False, problem))
    if info(SERVICE):
        removable = service_owned()
        resources.append(resource("dashboard", SERVICE, "service", removable,
            "Exact installer unit with no overrides; stop, disable and remove it." if removable else
            "Unit content, symlink ownership or drop-ins differ; the service will not be stopped or removed.",
            managed=bool(value or root_file(SERVICE))))
    if info(GATEWAY):
        removable = gateway_owned()
        resources.append(resource("scheduler", GATEWAY, "service", removable,
            "Exact installer scheduler unit with no overrides; stop, disable and remove it." if removable else
            "Unit content, symlink ownership or drop-ins differ; the scheduler service will not be stopped or removed.",
            managed=bool(value or root_file(GATEWAY))))
    for path, kind in PATH_KINDS.items():
        item = observed[path]
        if not item:
            continue
        owned = not problem and path_owned(path, value)
        if kind == "data" and not value.get("paths", {}).get(path, {}).get("created"):
            owned = False
        reason = None
        if kind == "runtime" and (usage["account"] or usage["runtime"]):
            owned = False
            reason = usage["reason"]
        if kind == "data" and owned:
            owned, reason = data_root_safe(value, usage)
        if mount_boundary(path):
            owned = False
            reason = "This resource contains a mount boundary; no mounted/shared files are deleted."
        resources.append(resource(path, path, kind, owned,
            reason or (("Keep until explicit purge; only this owned resource is removed." if kind != "runtime" else
             "Proven installer-owned runtime; data outside this path is retained.") if owned else
            "Ownership is absent, changed or predates precise provenance; cannot safely remove this resource."),
            purge=kind in ("data", "cache"), managed=bool(owned_user() or value)))
    jobs_path = HERMES + "/cron/jobs.json"
    if info(jobs_path):
        observed[jobs_path] = info(jobs_path, digest=True)
        try:
            data = json.loads(read(jobs_path))
            jobs = data["jobs"]
            if not isinstance(jobs, list):
                raise ValueError()
            matching = [job for job in jobs if isinstance(job, dict) and isinstance(job.get("origin"), dict)
                        and job["origin"].get("source") == "hermuse"]
            if matching:
                resources.append(resource("jobs", "Hermuse background jobs", "jobs", owned_user() and not problem and not value.get("connectionOnly"),
                    "Remove only jobs whose origin.source is hermuse; unrelated jobs remain."))
        except (OSError, UnsafePath, ValueError, KeyError, TypeError):
            resources.append(resource("jobs", jobs_path, "jobs", False, "Cron store is invalid or unsafe; no job records will be changed."))
    config_path = HERMES + "/config.yaml"
    if info(config_path) and not value.get("configRemoved") and (path_owned(PLUGIN, value) or value.get("paths", {}).get(PLUGIN, {}).get("identity")):
        observed[config_path] = info(config_path, digest=True)
        python = info(CHECKOUT + "/venv/bin/python")
        removable = owned_user() and python and not python.get("unsafe") and not problem
        resources.append(resource("plugin-config", "Hermuse plugin/computer configuration references", "runtime", removable,
            "Remove Hermuse enabled/disabled entries; restore known newly-created browser selections only, preserving all other config." if removable else
            "The owned Python runtime needed for safe YAML editing is unavailable; configuration references are preserved."))
    for path in plugin_assets():
        observed[path] = info(path)
        owned = path_owned(path, value)
        resources.append(resource(path, path, "runtime", owned,
            "Remove only this interrupted installer-owned plugin staging/backup directory." if owned else
            "The plugin staging directory has no safe ownership marker; preserve it."))
    for path, identity in installer_assets().items():
        observed[path] = identity
        owned = identity and same_identity(value.get("assetsCreated", {}).get(path), identity)
        resources.append(resource(path, path, "runtime", owned,
            "Remove this proven private installer/rollback asset directory; original system files remain untouched." if owned else
            "Installer assets predate provenance or contain unexpected files; their origin cannot safely be reversed."))
    current_docker = docker()
    observed["docker"] = current_docker
    if not docker_complete(current_docker):
        if value.get("containerCreated") or value.get("volumeCreated") or value.get("imagesCreated") or not value and owned_user():
            resources.append(resource("docker-unavailable", "Agent computer Docker assets", "container", False,
                current_docker.get("error", "The Docker CLI is unavailable; recorded persistent assets cannot be inspected or removed.")))
    else:
        container = current_docker.get("container")
        own_container = False
        if container:
            original = value.get("dockerAfter", {}).get("container", {}) or {}
            recorded = value.get("containerCreated") and original.get("id") == container["id"]
            legacy = not value and owned_user() and container["image"].startswith("hermuse-computer:") and any(
                mount.get("Type") == "volume" and mount.get("Name") == VOLUME and mount.get("Destination") == "/home/hermuse"
                for mount in container["mounts"])
            own_container = recorded or legacy
            resources.append(resource("computer", CONTAINER, "container", not problem and (recorded or legacy),
                "Remove this identified Hermuse computer container only; never prune Docker." if recorded or legacy else
                "A name alone is not ownership; this container is preserved.", managed=bool(recorded or legacy)))
        volume = current_docker.get("volume")
        if volume:
            expected = value.get("dockerAfter", {}).get("volume")
            refs = current_docker.get("volumeReferences", [])
            shared = any(not own_container or not container or not container["id"].startswith(reference) for reference in refs)
            owned = value.get("volumeCreated") and volume == expected and not shared and not problem
            resources.append(resource("computer-home", VOLUME, "volume", owned,
                "Keep computer logins/files normally; purge only this proven unshared named volume." if owned else
                "Volume creation/identity is unproven or another container uses it; preserve it even during purge.", purge=True,
                managed=bool(value.get("volumeCreated") or value.get("legacy") or not value and owned_user())))
        for tag, image in current_docker.get("images", {}).items():
            expected = value.get("imagesCreated", {}).get(tag)
            owned = not problem and expected and expected.get("id") == image.get("id")
            resources.append(resource("image:" + tag, tag, "image", owned,
                "Remove only this newly installed tag, without force; a used/shared image stays." if owned else
                "The image tag was preexisting or its creation/identity is unproven; preserve it.", managed=bool(owned)))
    current_web = web_docker()
    observed["web"] = current_web
    if not web_complete(current_web):
        if value.get("webContainerCreated") or value.get("webImagesCreated"):
            resources.append(resource("web-unavailable", "Web app Docker assets", "container", False,
                current_web.get("error", "The Docker CLI is unavailable; recorded web app assets cannot be inspected or removed.")))
    else:
        container = current_web.get("container")
        if container:
            original = value.get("webAfter", {}).get("container") or {}
            recorded = bool(value.get("webContainerCreated") and original.get("id") == container["id"]
                            and web_labelled(container))
            resources.append(resource("web", WEB_CONTAINER, "container", not problem and recorded,
                "Stop and remove this identified Hermuse web app container only; never prune Docker." if recorded else
                "A name or label alone is not ownership; this container is preserved.", managed=recorded))
        for tag, image in current_web.get("images", {}).items():
            expected = created_image(value, tag)
            owned = bool(not problem and expected and expected.get("id") == image.get("id"))
            resources.append(resource("image:" + tag, tag, "image", owned,
                "Remove only this newly installed web app tag, without force; a used/shared image stays." if owned else
                "The web app image tag was preexisting or its creation/identity is unproven; preserve it.", managed=owned))
    if info(SITE):
        removable = not problem and site_owned(value) and shutil.which("caddy") and root_file(CADDY) and caddy_source_safe()
        empty_site = root_file(SITE) and read(SITE) == b"# Managed by Hermuse remote installer; route removed, import retained\n"
        if not empty_site:
            routes = "dashboard and web app routes" if site_publishes_web(value) else "dashboard route"
            resources.append(resource("caddy-route", SITE, "network", removable,
                "Remove only the exact dedicated " + routes + "; validate/reload Caddy, preserving all other sites." if removable else
                "The dedicated routes lack matching manifest/source proof, were modified, or Caddy's active config cannot be safely validated; they are preserved.",
                managed=bool(value or site_owned(value))))
        elif import_count():
            resources.append(resource("caddy-import", IMPORT, "network", False,
                "The exact import existed before recorded provenance; an empty owned site keeps Caddy valid.",
                managed=bool(value.get("legacy") or not value)))
    if shutil.which("caddy"):
        resources.append(resource("caddy-service", "System Caddy service and certificate storage", "service", False,
            "This potentially shared system installation and its activation/certificates are retained; only the proven Hermuse route/import is removed.", managed=False))
    current_firewall = firewall()
    observed["firewall"] = current_firewall
    provenance = value.get("firewall", {})
    before = provenance.get("before", {})
    after = provenance.get("after", {})
    can_disable = bool(provenance and before.get("active") is False and firewall_equal(current_firewall, after))
    rules = current_firewall.get("rules", [])
    if provenance and (current_firewall.get("error") or not current_firewall.get("available") and provenance.get("added")):
        resources.append(resource("firewall-unavailable", "UFW additions", "network", False,
            current_firewall.get("error", "The UFW CLI is unavailable; recorded additions cannot be safely inspected or reverted.")))
    for rule in dict.fromkeys(provenance.get("added", [])):
        if rule not in rules:
            continue
        port = rule_port(rule)
        unique = port is not None and rules.count(rule) == 1 and before.get("rules", []).count(rule) == 0
        safe = unique and not problem
        reason = "Delete only this exact proven added rule; never reset UFW or restore an old ruleset."
        if current_firewall.get("active") and not can_disable and port in provenance.get("sshPorts", []):
            safe = False
            reason = "Preserve active SSH ingress: an independent alternative login rule is not proven."
        elif port in (80, 443) and shared_caddy():
            safe = False
            reason = "Other Caddy configuration shares HTTP/HTTPS ingress; preserve this firewall rule."
        if not unique:
            reason = "The rule is duplicated/modified or preexisting; its exact addition cannot safely be reversed."
        resources.append(resource("firewall:" + rule, rule, "network", safe, reason))
    if provenance and current_firewall.get("active") and before.get("active") is False:
        resources.append(resource("firewall-state", "UFW activation", "network", can_disable,
            "Restore the proven previous inactive state only while the committed firewall is unchanged." if can_disable else
            "Firewall configuration changed since installation; preserve current activation rather than overwrite another administrator's changes."))
    if (not provenance or provenance.get("unknown")) and any("Hermuse remote setup" in rule for rule in rules):
        resources.append(resource("legacy-firewall", "Legacy Hermuse UFW rules", "network", False,
            "This install predates rule provenance; comments alone cannot prove which rules were added. No firewall rules or activation are changed."))
    for package in installed_packages():
        added = package in value.get("packagesAdded", [])
        resources.append(resource("package:" + package, package, "package", False,
            "Installed during setup, but exclusive use is not provable; preserve this potentially shared system dependency." if added else
            "Preexisting or origin unknown; shared system packages and service installations are preserved.", managed=False))
    user = account()
    observed["user"] = user
    if user:
        safe, reason = user_safe(value, usage)
        resources.append(resource("account", "hermes account and empty dedicated home", "account", safe and not problem,
                                  reason, purge=True, managed=owned_user()))
    if root_file(JOURNAL):
        resources.append(resource("journal", JOURNAL, "ownership", False,
            "Retain the nonsecret ownership audit so repeated removal and later purge remain safe.", managed=False))
    LAST_OBSERVED.clear()
    LAST_OBSERVED.update(observed)
    revision = hashlib.sha256(json.dumps(observed, sort_keys=True).encode()).hexdigest()
    return {"resources": resources, "revision": revision, "transactionActive": transaction_active(own_lock)}, value

def remove_tree(path, expected=None):
    if mount_boundary(path):
        raise UnsafePath("Mounted/shared resource is not removed: " + path)
    with parent(path) as (fd, name):
        if fd is None:
            return False
        try:
            value = os.stat(name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            return False
        if expected and not same_identity(expected, info(path)):
            raise UnsafePath("Resource identity changed before deletion: " + path)
        device = value.st_dev
        boundary = mount_id(fd)
        def opened(parent_fd, entry):
            expected_stat = os.stat(entry, dir_fd=parent_fd, follow_symlinks=False)
            directory = stat.S_ISDIR(expected_stat.st_mode)
            handle = os.open(entry, O_DIRECTORY if directory else os.O_PATH | os.O_NOFOLLOW, dir_fd=parent_fd)
            actual = os.fstat(handle)
            if actual.st_dev != device or actual.st_ino != expected_stat.st_ino or mount_id(handle) != boundary:
                os.close(handle)
                raise UnsafePath("Mounted/replaced filesystem resource is not removed: " + path)
            return handle, actual, directory
        def scan(parent_fd, entry):
            handle, actual, directory = opened(parent_fd, entry)
            try:
                if directory:
                    for child in os.listdir(handle):
                        scan(handle, child)
                elif not (stat.S_ISREG(actual.st_mode) or stat.S_ISLNK(actual.st_mode)):
                    raise UnsafePath("Special filesystem resource is not removed: " + path)
            finally:
                os.close(handle)
        def remove_entry(parent_fd, entry):
            handle, actual, directory = opened(parent_fd, entry)
            try:
                if directory:
                    for child in os.listdir(handle):
                        remove_entry(handle, child)
                elif not (stat.S_ISREG(actual.st_mode) or stat.S_ISLNK(actual.st_mode)):
                    raise UnsafePath("Special filesystem resource is not removed: " + path)
            finally:
                os.close(handle)
            if directory:
                os.rmdir(entry, dir_fd=parent_fd)
            else:
                os.unlink(entry, dir_fd=parent_fd)
        scan(fd, name)
        remove_entry(fd, name)
    return True

def empty_directory(path):
    try:
        with parent(path) as (fd, name):
            if fd is None:
                return
            child = os.open(name, O_DIRECTORY, dir_fd=fd)
            try:
                if os.listdir(child):
                    return
            finally:
                os.close(child)
            os.rmdir(name, dir_fd=fd)
    except FileNotFoundError:
        pass

def step(name, finished=False):
    print("HERMUSE_UNINSTALL_STEP_V1:" + name + (":finished" if finished else ":started"), flush=True)

def processes():
    user = account()
    if not user:
        return False
    result = command(["ps", "-u", str(user["uid"]), "-o", "pid="], required=False)
    if result.returncode not in (0, 1):
        raise RuntimeError("Could not prove that the dedicated account has no remaining processes.")
    return bool(result.stdout.strip())

def remove_jobs():
    path = HERMES + "/cron/jobs.json"
    data = json.loads(read(path))
    data["jobs"] = [job for job in data["jobs"] if not (isinstance(job, dict)
                    and isinstance(job.get("origin"), dict) and job["origin"].get("source") == "hermuse")]
    write(path, (json.dumps(data, indent=2) + "\n").encode())
def remove_config(value):
    code = """import json, sys, yaml
cfg = yaml.safe_load(sys.stdin.read()) or {}
if not isinstance(cfg, dict):
    raise SystemExit(2)
plugins = cfg.get('plugins', {})
if isinstance(plugins, dict):
    for key in ('enabled', 'disabled'):
        if isinstance(plugins.get(key), list):
            plugins[key] = [entry for entry in plugins[key] if entry != 'hermuse']
browser = cfg.get('browser', {})
if ABSENT and isinstance(browser, dict):
    for key, expected in (('cloud_provider', 'hermuse'), ('auto_local_for_private_urls', False), ('backend', 'off')):
        if browser.get(key) == expected:
            browser.pop(key, None)
sys.stdout.write(yaml.safe_dump(cfg, sort_keys=False))
"""
    code = "ABSENT = " + repr(bool(value.get("configBeforeAbsent"))) + "\n" + code
    result = subprocess.run(["runuser", "-u", "hermes", "--", CHECKOUT + "/venv/bin/python", "-I", "-B", "-c", code],
                            input=text(HERMES + "/config.yaml"), capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError("Could not edit YAML safely as the dedicated account; configuration was not changed.")
    write(HERMES + "/config.yaml", result.stdout.encode())
    value["configRemoved"] = True


def remove_caddy(value):
    if not site_owned(value) or not caddy_source_safe() or not root_file(CADDY):
        raise RuntimeError("Caddy fragment ownership/source changed before removal; inspect again.")
    original_metadata = info(CADDY)
    site_metadata = info(SITE)
    original = read(CADDY)
    original_site = read(SITE)
    direct = import_count()
    added = value.get("caddy", {}).get("importAdded") and direct == 1
    placeholder = bool(direct and not added)
    try:
        if added:
            body = original.decode().splitlines(keepends=True)
            write(CADDY, "".join(line for line in body if line.rstrip("\r\n") != IMPORT).encode())
        if placeholder:
            write(SITE, b"# Managed by Hermuse remote installer; route removed, import retained\n")
        else:
            remove_tree(SITE, info(SITE))
        command(["caddy", "validate", "--config", CADDY, "--adapter", "caddyfile"])
        if active("caddy"):
            command(["systemctl", "reload", "caddy"])
    except Exception:
        write(CADDY, original, original_metadata)
        write(SITE, original_site, site_metadata)
        if active("caddy"):
            command(["systemctl", "reload", "caddy"], required=False)
        raise

def remove():
    inherited = os.environ.get("HERMUSE_OPERATION_FD")
    handle = os.dup(int(inherited)) if inherited else lock_file(create=True)
    identity = os.fstat(handle)
    expected_lock = info(LOCK)
    if not root_file(LOCK) or not expected_lock or identity.st_ino != expected_lock["ino"] or identity.st_dev != expected_lock["dev"]:
        os.close(handle)
        raise UnsafePath("The inherited operation lock identity is invalid.")
    try:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("A server setup or uninstall is already running; nothing was removed.")
        step("inspect")
        preview, value = inventory(own_lock=True)
        baseline_observed = LAST_OBSERVED.copy()
        if preview["transactionActive"]:
            raise RuntimeError("A setup firewall/Caddy rollback is pending; nothing was removed.")
        if preview["revision"] != REQUEST["revision"]:
            raise RuntimeError("The server inventory changed after inspection; inspect and confirm again. Nothing was removed.")
        if not value and owned_user():
            # Record unknown historical origins, never infer that they were
            # created by this new uninstall attempt.
            value = capture()
            value["legacyRemovablePaths"] = {
                item["id"]: baseline_observed[item["id"]] for item in preview["resources"]
                if item["removable"] and item["id"] in baseline_observed and item["kind"] == "runtime"}
            save(value)
        step("inspect", True)
        purge = REQUEST["purge"]
        candidates = {item["id"]: item for item in preview["resources"] if item["removable"] and (purge or not item["purgeOnly"])}
        removed = []
        warnings = []
        def done(identifier):
            removed.append(identifier)
            if identifier in value.get("paths", {}):
                value["paths"][identifier]["removed"] = True
            if value:
                save(value)
        step("services")
        if "dashboard" in candidates:
            if not service_owned():
                raise RuntimeError("Dashboard ownership changed before stopping it.")
            command(["systemctl", "disable", "--now", "hermuse-dashboard.service"])
            remove_tree(SERVICE, info(SERVICE))
            command(["systemctl", "daemon-reload"])
            if active("hermuse-dashboard.service"):
                raise RuntimeError("The managed dashboard did not stop.")
            done("dashboard")
        if "scheduler" in candidates:
            if not gateway_owned():
                raise RuntimeError("Scheduler ownership changed before stopping it.")
            command(["systemctl", "disable", "--now", "hermuse-gateway.service"])
            remove_tree(GATEWAY, info(GATEWAY))
            command(["systemctl", "daemon-reload"])
            if active("hermuse-gateway.service"):
                raise RuntimeError("The managed scheduler did not stop.")
            done("scheduler")
        busy = processes() or external_runtime()
        if busy:
            warnings.append("The hermes account still has running processes or another service uses its runtime. Runtime, job and data deletion were skipped; unrelated services/processes were not stopped.")
        if "jobs" in candidates and not busy:
            remove_jobs()
            done("jobs")
        if "plugin-config" in candidates and not busy:
            remove_config(value)
            done("plugin-config")
            if not value.get("configBeforeAbsent"):
                warnings.append("Legacy/preexisting browser configuration has no before-state provenance and was retained; only Hermuse plugin entries were removed.")
        step("services", True)
        step("runtime")
        if "web" in candidates:
            current = docker_inspect("container", WEB_CONTAINER)
            expected = baseline_observed["web"].get("container")
            if not current or not expected or current["id"] != expected["id"] or not web_labelled(current):
                raise RuntimeError("Web app container identity changed before deletion.")
            command(["docker", "rm", "-f", current["id"]], timeout=60)
            if docker_inspect("container", WEB_CONTAINER):
                raise RuntimeError("The identified web app container was not removed.")
            done("web")
        if "computer" in candidates:
            current = docker_inspect("container", CONTAINER)
            expected = baseline_observed["docker"].get("container")
            if not current or not expected or current["id"] != expected["id"]:
                raise RuntimeError("Computer container identity changed before deletion.")
            command(["docker", "rm", "-f", current["id"]], timeout=60)
            if docker_inspect("container", CONTAINER):
                raise RuntimeError("The identified computer container was not removed.")
            done("computer")
        for path in RUNTIME_PATHS:
            if path in candidates and not busy:
                if not path_owned(path, value):
                    raise RuntimeError("Runtime ownership changed before deletion: " + path)
                remove_tree(path, baseline_observed[path])
                done(path)
        for path in [*plugin_assets(), *installer_assets()]:
            if path in candidates and not busy:
                if path in installer_assets() and not installer_assets()[path]:
                    raise RuntimeError("Installer assets gained unexpected/unowned entries before deletion.")
                remove_tree(path, baseline_observed[path])
                done(path)
        for identifier in candidates:
            if not identifier.startswith("image:"):
                continue
            tag = identifier[6:]
            expected = created_image(value, tag)
            current = docker_inspect("image", tag)
            if not expected or not current or expected.get("id") != current.get("id"):
                raise RuntimeError("Image identity changed before deletion: " + tag)
            result = command(["docker", "image", "rm", tag], required=False, timeout=60)
            if result.returncode:
                warnings.append("Image tag " + tag + " is in use/shared and was preserved.")
            elif docker_inspect("image", tag):
                raise RuntimeError("The image tag was not removed: " + tag)
            else:
                done(identifier)
        step("runtime", True)
        step("network")
        if "caddy-route" in candidates:
            remove_caddy(value)
            done("caddy-route")
        if "firewall-state" in candidates:
            if not firewall_equal(firewall(), value["firewall"]["after"]):
                raise RuntimeError("Firewall changed before restoring its prior inactive state.")
            command(["ufw", "--force", "disable"])
            if firewall().get("active"):
                raise RuntimeError("UFW did not restore its previous inactive state.")
            done("firewall-state")
        for identifier in candidates:
            if not identifier.startswith("firewall:"):
                continue
            rule = identifier[len("firewall:"):]
            port = rule_port(rule)
            before_rules = firewall().get("rules", [])
            if port is None or before_rules.count(rule) != 1:
                raise RuntimeError("Firewall addition changed before deletion.")
            command(["ufw", "--force", "delete", "allow", str(port) + "/tcp", "comment", "Hermuse remote setup"])
            expected = collections.Counter(before_rules)
            expected.subtract([rule])
            expected += collections.Counter()
            if collections.Counter(firewall().get("rules", [])) != expected:
                raise RuntimeError("UFW did not remove exactly the identified rule; no broad reset was attempted.")
            done(identifier)
        step("network", True)
        step("purge")
        if purge:
            for path in [*CACHE_PATHS, HERMES]:
                if path in candidates and not busy:
                    if not path_owned(path, value):
                        raise RuntimeError("Data ownership changed before purge: " + path)
                    if path == HERMES:
                        safe, reason = data_root_safe(value)
                        if not safe:
                            warnings.append(reason)
                            continue
                    remove_tree(path, baseline_observed[path])
                    done(path)
            if "computer-home" in candidates:
                current = docker()
                if current.get("error") or current.get("volumeReferences") or current.get("volume") != value.get("dockerAfter", {}).get("volume"):
                    warnings.append("The computer home volume is now shared or its identity changed; it was preserved.")
                else:
                    command(["docker", "volume", "rm", VOLUME])
                    if docker_inspect("volume", VOLUME):
                        raise RuntimeError("The dedicated computer volume was not removed.")
                    done("computer-home")
            if "account" in candidates and not busy:
                safe, reason = user_safe(value)
                if safe and not processes():
                    for name in DEFAULTS:
                        path = HOME + "/" + name
                        if info(path):
                            remove_tree(path, info(path))
                    for path in [HOME + "/.local/bin", HOME + "/.local/share", HOME + "/.local", HOME + "/.cache"]:
                        empty_directory(path)
                    with parent(HOME + "/placeholder") as (fd, _):
                        empty = fd is not None and not os.listdir(fd)
                    if empty:
                        # Never userdel -r: remove the proven empty home ourselves.
                        command(["userdel", "hermes"])
                        empty_directory(HOME)
                        remove_tree(ROOT + "/owns-hermes", info(ROOT + "/owns-hermes"))
                        done("account")
                    else:
                        warnings.append("The dedicated account still has unrelated/unproven files; its account and home were preserved.")
                else:
                    warnings.append(reason)
        step("purge", True)
        step("verify")
        final, _ = inventory(own_lock=True)
        # A still-present planned resource is not silently counted as removed.
        preserved = final["resources"]
        unexpected = [item for item in preserved if item["managed"] and not (not purge and item["purgeOnly"])]
        warnings.extend(item["reason"] for item in unexpected if item["reason"] not in warnings)
        step("verify", True)
        print("HERMUSE_UNINSTALL_OUTCOME_V1:" + json.dumps({"purged": purge, "removed": removed,
              "preserved": preserved, "warnings": warnings, "complete": not unexpected}, sort_keys=True), flush=True)
    finally:
        os.close(handle)

try:
    mode = REQUEST["mode"]
    if mode == "capture":
        capture()
    elif mode == "preflight":
        setup_preflight()
    elif mode == "checkpoint":
        checkpoint()
    elif mode == "mutation":
        mutation()
    elif mode == "dockerBaseline":
        docker_baseline()
    elif mode == "firewall":
        record_firewall()
    elif mode == "inspect":
        result, _ = inventory()
        print("HERMUSE_UNINSTALL_INVENTORY_V1:" + json.dumps(result, sort_keys=True), flush=True)
    elif mode == "remove":
        remove()
    else:
        raise RuntimeError("Unsupported ownership operation.")
except Exception as error:
    print("Hermuse remote removal: " + str(error), file=sys.stderr)
    raise SystemExit(1)
''';
