"""``hermes hermuse ...`` CLI subcommands (registered via ``ctx.register_cli_command``).

Verbs: ``status`` (default), ``enable`` (register cron jobs), ``disable``
(remove them), ``doctor`` (home/store/cron diagnostics).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Callable, Optional


def _store() -> Any:
    from . import store as _store_mod

    return _store_mod


def _specs() -> Any:
    from . import cron_specs as _specs_mod

    return _specs_mod


def _home() -> Path:
    from hermes_constants import get_hermes_home

    return get_hermes_home()


def _print_status(root: Path, jobs: Any, out: Callable[[str], None]) -> int:
    specs = _specs()
    store = _store()
    store.ensure_defaults(root)
    out(f"Hermuse store: {root}")
    managed = [n for n in store.MANAGED_FILES if (root / n).is_file()]
    out(f"  managed files: {len(managed)}/{len(store.MANAGED_FILES)} present")
    for spec in specs.SPECS:
        job = specs.find_job(jobs, spec.key)
        if job is None:
            out(f"  [{spec.key}] not registered")
            continue
        state = "paused" if not job.get("enabled", True) else str(job.get("state", "scheduled"))
        out(f"  [{spec.key}] {job.get('id')} state={state} next={job.get('next_run_at')}")
    return 0


def _cmd_status(args: argparse.Namespace) -> int:
    from cron import jobs

    return _print_status(_store().hermuse_root(_home()), jobs, print)


def _cmd_enable(args: argparse.Namespace) -> int:
    from cron import jobs

    specs = _specs()
    results = specs.register_all(jobs)
    for key, (record, created) in results.items():
        verb = "created" if created else "refreshed"
        print(f"[{key}] {verb}: {record.get('id')} next={record.get('next_run_at')}")
    return 0


def _cmd_disable(args: argparse.Namespace) -> int:
    from cron import jobs

    removed = _specs().remove_all(jobs)
    if not removed:
        print("No Hermuse cron jobs registered.")
    for job_id in removed:
        print(f"removed: {job_id}")
    return 0


def _cmd_doctor(args: argparse.Namespace) -> int:
    import hermes_cli

    store = _store()
    failures = 0
    home = _home()
    root = store.hermuse_root(home)
    version = getattr(hermes_cli, "__version__", "?")
    print(f"hermes: {version} home: {home}")
    try:
        created = store.ensure_defaults(root)
        print(f"store: {root} ({len(created)} default file(s) created)")
    except OSError as exc:
        print(f"store: FAILED to prepare {root}: {exc}")
        return 1
    try:
        from cron import jobs as cron_jobs

        for path in (cron_jobs.JOBS_FILE,):
            print(f"cron store: {path} ({'exists' if Path(path).exists() else 'not yet created'})")
        count = len(cron_jobs.load_jobs())
        print(f"cron jobs visible: {count}")
    except Exception as exc:  # noqa: BLE001 — doctor must report, not crash
        print(f"cron: FAILED to read jobs: {exc}")
        failures += 1
    return 1 if failures else 0


_COMMANDS = {
    "status": _cmd_status,
    "enable": _cmd_enable,
    "disable": _cmd_disable,
    "doctor": _cmd_doctor,
}


def register_cli(parser: argparse.ArgumentParser) -> None:
    subs = parser.add_subparsers(dest="hermuse_command", required=False)
    subs.add_parser("status", help="Show the Hermuse store and cron job state")
    subs.add_parser("enable", help="Register (or refresh) the Hermuse cron jobs")
    subs.add_parser("disable", help="Remove the Hermuse cron jobs")
    subs.add_parser("doctor", help="Diagnose the Hermuse store and cron wiring")
    parser.set_defaults(func=dispatch)


def dispatch(args: argparse.Namespace) -> int:
    sub = getattr(args, "hermuse_command", None)
    handler = _cmd_status if sub is None else _COMMANDS.get(sub)
    if handler is None:
        print(f"unknown subcommand: {sub}", file=sys.stderr)
        return 2
    return handler(args)
