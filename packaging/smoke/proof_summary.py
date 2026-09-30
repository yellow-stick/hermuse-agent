#!/usr/bin/env python3
"""Smoke legs and release proof of the release workflow (stdlib only).

The legs listed here are the single source of truth: the workflow matrices are
generated from them and the summary fails any leg or result that is absent.

  proof_summary.py matrix guests|containers|desktop [--set full|queue] [--filter REGEX]
                                               GitHub matrix JSON of the selected legs
  proof_summary.py leg <leg-dir> <scenario> [--target T]
                                               exit 1 when a result of one leg failed or is
                                               missing (--target: a macOS/Windows runner leg)
  proof_summary.py collect <root> --matrix JSON [--matrix JSON] --out F --markdown M
                                               roll the legs of the matrices up (fail on any
                                               fail/missing); `complete` = every leg ran
  proof_summary.py finalize --summary F [--model <leg-dir>] [--release-version F]
                            --out F --markdown M --notes N
                                               add the model-account proof and the signing
                                               of the macOS/Windows artifacts (assembled
                                               VERSION.json), decide automated_ok (printed
                                               as key=value), write the "Not yet proven"
                                               section of the release notes

A result is pass | fail | manual-gate | skipped-missing-prereq (see
packaging/smoke/linux.sh, macos.sh, windows.ps1). A release is published, as a
pre-release, only when every leg ran, no result failed or is missing, every
manual gate carries its recorded evidence and the model-account proof did not
fail. What the run could not prove (no model test account, unsigned macOS or
Windows artifacts, manual gates, the checks outside CI) is listed under "Not
yet proven" in its notes and checked before the manual promotion to latest.
Merge groups run the `queue` set (the fresh scenario of both guests and
formats, the containers, the macOS and Windows runners); the nightly run, test
runs and releases run the `full` set; pull requests run no leg.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

GUESTS = ("ubuntu-22.04", "debian-12")
CONTAINERS = ("ubuntu-24.04", "ubuntu-26.04", "debian-13")
FORMATS = ("deb", "appimage")

# The legs a merge group runs; the nightly run, test runs and releases run every leg.
QUEUE_SCENARIOS = ("fresh",)

# scenario -> formats, result ids (as linux.sh `expect`s them)
SCENARIOS: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "fresh": (FORMATS, ("c0-test-base", "c1-launch", "c2-prepare", "c3-keyring", "c4-hermes",
                        "c5-plugin", "c6-bridge", "c7-computer", "c8-scheduling-conversation")),
    "adopt-compatible": (("deb",), ("c0-test-base", "c4-hermes-adopt-compatible")),
    "adopt-foreign": (("deb",), ("c0-test-base", "c4-hermes-adopt-foreign")),
    "docker-ce": (("deb",), ("c0-test-base", "c9-docker-ce")),
    "docker-stopped": (("deb",), ("c0-test-base", "c9-docker-stopped")),
    "docker-rootless": (("deb",), ("c0-test-base", "c9-docker-rootless")),
    "docker-remote-context": (("deb",), ("c0-test-base", "c9-docker-remote-context")),
    "lifecycle": (FORMATS, ("c0-test-base", "c10-lifecycle")),
}
COMPAT_IDS = ("compat",)
MODEL_CHECKS = ("conversation", "cron-oneshot-agent")

# GitHub-hosted runner -> (os, format, result ids as macos.sh / windows.ps1
# `expect` them). One fresh leg each, on the runner itself: its VM is new for
# every job, and it has no nested virtualization for a guest.
DESKTOPS: dict[str, tuple[str, str, tuple[str, ...]]] = {
    "macos-15": ("macos", "dmg", ("c0-test-base", "c1-launch", "c3-keyring", "c4-hermes", "c5-plugin",
                                  "c6-bridge", "c7-computer")),
    "windows-2025": ("windows", "setup", ("c0-test-base", "c1-launch", "c3-keyring", "c4-hermes", "c5-plugin",
                                          "c6-bridge", "c7-computer", "c10-lifecycle")),
}
# Platforms whose artifacts a release signs, as the assembled VERSION.json
# records them (platforms.<os>.signing); an unsigned one is not yet proven.
SIGNED_PLATFORMS = {
    "macos": "macOS .dmg signature, notarization and stapling",
    "windows": "Windows Setup.exe signature with Artifact Signing",
}

# Proofs no CI run can produce: not yet proven, checked before the promotion to latest.
EXTERNAL_GATES = (
    "Real desktop spot check on Pop!_OS 24.04: menu entry and icon, compositor/GPU rendering, "
    "the AppImage under XWayland in a Wayland session, the real administrator dialog.",
    "Provider connections other than starting one bridge login are not exercised by CI "
    "(no subscription or API account is created): they stay unverified.",
    "Real Apple Silicon Mac: the downloaded .dmg (quarantined) opens through Gatekeeper, Dock icon and "
    "menu bar name; the agent's computer with a Docker engine (the hosted macOS runners have no "
    "nested virtualization, CI only records that Docker is reported missing).",
    "Real Windows 11 x64 desktop: SmartScreen and the Authenticode signature of the downloaded Setup.exe, "
    "Start menu entry and icon; the agent's computer with a Docker engine (phase 2, CI only records "
    "that Docker is reported missing).",
)


def leg_name(leg: dict[str, str]) -> str:
    """Artifact and directory name of a leg, e.g. smoke-debian-12-fresh-appimage."""
    return f"{leg['kind']}-{leg['target']}-{leg['scenario']}-{leg['format']}"


def legs() -> list[dict[str, str]]:
    out = []
    for guest in GUESTS:
        for scenario, (formats, _) in SCENARIOS.items():
            for fmt in formats:
                out.append({"kind": "smoke", "target": guest, "scenario": scenario, "format": fmt})
    for container in CONTAINERS:
        for fmt in FORMATS:
            out.append({"kind": "compat", "target": container, "scenario": "compat", "format": fmt})
    for runner, (_, fmt, _) in DESKTOPS.items():
        out.append({"kind": "smoke", "target": runner, "scenario": "fresh", "format": fmt})
    return out


def expected_ids(scenario: str, target: str = "") -> tuple[str, ...]:
    if target in DESKTOPS:
        return DESKTOPS[target][2]
    return COMPAT_IDS if scenario == "compat" else SCENARIOS[scenario][1]


def load_leg(leg_dir: Path, ids: tuple[str, ...]) -> list[dict[str, Any]]:
    results = []
    for result_id in ids:
        path = leg_dir / "results" / f"{result_id}.json"
        try:
            result = json.loads(path.read_text())
        except (OSError, ValueError) as exc:
            result = {"id": result_id, "status": "fail", "checks": [
                {"name": "result", "status": "fail", "detail": f"no result ({type(exc).__name__})",
                 "evidence": []}], "gui_proof": []}
        missing = [p for p in result.get("gui_proof", []) if not (leg_dir / p).exists()]
        if missing:
            result["status"] = "fail"
            result.setdefault("checks", []).append({
                "name": "evidence", "status": "fail",
                "detail": f"manual-gate evidence missing from the artifact: {missing}", "evidence": []})
        results.append(result)
    return results


def matrix_kind(leg: dict[str, str]) -> str:
    if leg["target"] in DESKTOPS:
        return "desktop"
    return "guests" if leg["kind"] == "smoke" else "containers"


def cmd_matrix(args: argparse.Namespace) -> int:
    pattern = re.compile(args.filter) if args.filter else None
    include = []
    for leg in legs():
        if matrix_kind(leg) != args.which:
            continue
        if args.set != "full" and leg["kind"] == "smoke" and leg["scenario"] not in QUEUE_SCENARIOS:
            continue
        if pattern is not None and not pattern.search(leg_name(leg)):
            continue
        entry = dict(leg, name=leg_name(leg))
        if args.which == "desktop":
            entry["os"] = DESKTOPS[leg["target"]][0]
        include.append(entry)
    print(json.dumps({"include": include}, separators=(",", ":")))
    return 0


def cmd_leg(args: argparse.Namespace) -> int:
    failed = []
    for result in load_leg(Path(args.leg_dir), expected_ids(args.scenario, args.target)):
        print(f"{result['status']:24} {result['id']}")
        for check in result.get("checks", []):
            if check.get("status") in ("fail", "manual-gate", "skipped-missing-prereq"):
                print(f"{'':24}   {check['status']}: {check.get('name')}: {check.get('detail')}")
        if result["status"] == "fail":
            failed.append(result["id"])
    return 1 if failed else 0


def cmd_collect(args: argparse.Namespace) -> int:
    root = Path(args.root)
    selected = {leg["name"] for matrix in args.matrix for leg in json.loads(matrix)["include"]}
    rows = []
    for leg in legs():
        name = leg_name(leg)
        if name not in selected:
            continue
        for result in load_leg(root / name, expected_ids(leg["scenario"], leg["target"])):
            rows.append({"leg": name, **{k: leg[k] for k in ("target", "scenario", "format")},
                         "id": result["id"], "criterion": result.get("criterion", "?"),
                         "status": result["status"], "checks": result.get("checks", []),
                         "gui_proof": result.get("gui_proof", [])})
    failed = [r for r in rows if r["status"] == "fail"]
    summary = {"schema": 1, "rows": rows, "failed": len(failed),
               "manual_gates": sum(r["status"] == "manual-gate" for r in rows),
               "smoke_ok": not failed and bool(rows),
               "complete": selected == {leg_name(leg) for leg in legs()},
               "external_gates": list(EXTERNAL_GATES)}
    Path(args.out).write_text(json.dumps(summary, indent=2))
    Path(args.markdown).write_text(render(summary, None, None))
    return 0 if not failed else 1


def model_proof(leg_dir: Path | None) -> dict[str, Any]:
    if leg_dir is None:
        return {"status": "skipped-missing-prereq",
                "detail": "no HERMUSE_TEST_MODEL_* test account in the release environment"}
    results = load_leg(leg_dir, SCENARIOS["fresh"][1])
    checks = {c["name"]: c for r in results for c in r.get("checks", [])}
    missing = [name for name in MODEL_CHECKS if checks.get(name, {}).get("status") != "pass"]
    failed = [r["id"] for r in results if r["status"] == "fail"]
    ok = not missing and not failed
    return {"status": "pass" if ok else "fail",
            "detail": "real conversation and agent one-shot job passed" if ok else
            f"model checks not passed: {missing}; failed results: {failed}", "results": results}


def signing_proof(version_file: Path | None) -> dict[str, Any]:
    """Whether the macOS/Windows artifacts of the assembled release are signed: pass, unsigned (not yet
    proven), or fail when the assembled VERSION.json cannot tell."""
    if version_file is None:
        return {"status": "fail", "detail": "no assembled VERSION.json: the signing is unknown", "unsigned": []}
    try:
        platforms = json.loads(version_file.read_text())["platforms"]
    except (OSError, ValueError, KeyError, TypeError) as exc:
        return {"status": "fail", "detail": f"unreadable assembled VERSION.json ({type(exc).__name__})",
                "unsigned": []}
    unsigned = []
    for name, label in SIGNED_PLATFORMS.items():
        signing = (platforms.get(name) or {}).get("signing") or {}
        if name == "macos":
            ok = bool(signing.get("signed") and signing.get("notarized") and signing.get("stapled"))
        else:
            ok = bool(signing.get("signed")) and signing.get("method") == "artifact-signing"
        if not ok:
            unsigned.append(f"{label} ({signing.get('reason') or 'not signed'})")
    return {"status": "pass" if not unsigned else "unsigned",
            "detail": "macOS signed, notarized and stapled; Windows signed (Artifact Signing)" if not unsigned
            else "not signed: " + "; ".join(unsigned), "unsigned": unsigned}


def not_yet_proven(summary: dict[str, Any], model: dict[str, Any], signing: dict[str, Any]) -> list[str]:
    """What the release run could not prove, for the "Not yet proven" section of the release notes."""
    items = []
    if model["status"] != "pass":
        items.append(f"Real conversation and agent one-shot job with the capped model test account "
                     f"({model['detail']})")
    items += signing["unsigned"]
    for row in summary["rows"]:
        for check in row["checks"]:
            if check["status"] == "manual-gate":
                items.append(f"Manual gate {row['id']}/{check['name']} of {row['leg']}: {check['detail']} "
                             f"(evidence in the {row['leg']} artifact of the release run)")
    items += [f"Checked outside CI: {gate}" for gate in summary["external_gates"]]
    return items


def cmd_finalize(args: argparse.Namespace) -> int:
    summary = json.loads(Path(args.summary).read_text())
    model = model_proof(Path(args.model) if args.model else None)
    signing = signing_proof(Path(args.release_version) if args.release_version else None)
    summary["model_proof"] = {k: v for k, v in model.items() if k != "results"}
    summary["model_results"] = model.get("results", [])
    summary["signing_proof"] = signing
    # A failed or missing automated result blocks the publication; what is only
    # unproven goes out in a pre-release that lists it.
    summary["automated_ok"] = (bool(summary["smoke_ok"]) and bool(summary.get("complete"))
                               and model["status"] != "fail" and signing["status"] != "fail")
    summary["not_yet_proven"] = not_yet_proven(summary, model, signing)
    Path(args.out).write_text(json.dumps(summary, indent=2))
    Path(args.markdown).write_text(render(summary, model, signing))
    Path(args.notes).write_text(render_notes(summary["not_yet_proven"]))
    print(f"automated_ok={'true' if summary['automated_ok'] else 'false'}")
    return 0


def render(summary: dict[str, Any], model: dict[str, Any] | None, signing: dict[str, Any] | None) -> str:
    lines = ["## Release proof", ""]
    lines.append(f"Smoke results: {'no failure' if summary['smoke_ok'] else str(summary['failed']) + ' failed'}, "
                 f"{summary['manual_gates']} manual gate(s), "
                 f"{'every leg ran' if summary.get('complete') else 'a subset of the legs ran'}.")
    if model is not None:
        lines.append(f"Model-account proof: **{model['status']}** ({model['detail']}).")
    if signing is not None:
        lines.append(f"Signing: **{signing['status']}** ({signing['detail']}).")
    if model is not None or signing is not None:
        lines.append("No failed or missing automated result: published as a pre-release, "
                     f"{len(summary['not_yet_proven'])} point(s) not yet proven listed in its notes."
                     if summary.get("automated_ok") else
                     "A failed or missing automated result blocks the publication.")
    lines += ["", "| Leg | Result | Criterion | Status |", "| --- | --- | --- | --- |"]
    for row in summary["rows"]:
        lines.append(f"| {row['leg']} | {row['id']} | {row['criterion']} | {row['status']} |")
    gates = [r for r in summary["rows"] if r["status"] in ("manual-gate", "fail")]
    if gates:
        lines += ["", "### To review (artifact = leg name)", ""]
        for row in gates:
            for check in row["checks"]:
                if check["status"] in ("manual-gate", "fail"):
                    evidence = ", ".join(check.get("evidence", [])) or "no evidence"
                    lines.append(f"- **{check['status']}** `{row['leg']}` {row['id']}/{check['name']}: "
                                 f"{check['detail']} ({evidence})")
    lines += ["", "### Outside CI (checked before the promotion to latest)", ""]
    lines += [f"- {gate}" for gate in summary["external_gates"]]
    lines.append("")
    return "\n".join(lines)


def render_notes(items: list[str]) -> str:
    """The "Not yet proven" section of the release notes."""
    lines = ["## Not yet proven", "",
             "Every automated check of the release run passed. It could not prove the points below: "
             "the release stays a pre-release until they are checked.", ""]
    lines += [f"- {item}" for item in items]
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    matrix = sub.add_parser("matrix")
    matrix.add_argument("which", choices=("guests", "containers", "desktop"))
    matrix.add_argument("--set", choices=("full", "queue"), default="full")
    matrix.add_argument("--filter", default="")
    matrix.set_defaults(run=cmd_matrix)
    leg = sub.add_parser("leg")
    leg.add_argument("leg_dir")
    leg.add_argument("scenario", choices=(*SCENARIOS, "compat"))
    leg.add_argument("--target", default="", choices=("", *DESKTOPS),
                     help="the GitHub-hosted runner of a macOS/Windows leg")
    leg.set_defaults(run=cmd_leg)
    collect = sub.add_parser("collect")
    collect.add_argument("root")
    collect.add_argument("--matrix", action="append", required=True,
                         help="GitHub matrix JSON of the legs this run started")
    collect.add_argument("--out", required=True)
    collect.add_argument("--markdown", required=True)
    collect.set_defaults(run=cmd_collect)
    finalize = sub.add_parser("finalize")
    finalize.add_argument("--summary", required=True)
    finalize.add_argument("--model")
    finalize.add_argument("--release-version", help="the assembled VERSION.json of every platform")
    finalize.add_argument("--out", required=True)
    finalize.add_argument("--markdown", required=True)
    finalize.add_argument("--notes", required=True, help="the \"Not yet proven\" section of the release notes")
    finalize.set_defaults(run=cmd_finalize)
    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
