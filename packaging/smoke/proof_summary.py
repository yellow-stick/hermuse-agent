#!/usr/bin/env python3
"""Smoke legs and release proof of the Linux release workflow (stdlib only).

The legs listed here are the single source of truth: the workflow matrix is
generated from them and the summary fails any leg or result that is absent.

  proof_summary.py matrix guests|containers    GitHub matrix JSON of the smoke legs
  proof_summary.py leg <leg-dir> <scenario>    exit 1 when a result of one leg failed or is missing
  proof_summary.py collect <root> --out F --markdown M
                                               roll every leg up (fail on any fail/missing)
  proof_summary.py finalize --summary F [--model <leg-dir>] --out F --markdown M
                                               add the model-account proof, decide
                                               public_ready (printed as key=value)

A result is pass | fail | manual-gate | skipped-missing-prereq (see
packaging/smoke/linux.sh). The release may go public only when no result
failed or is missing, every manual gate carries its recorded evidence, and the
real conversation with the capped test account passed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

GUESTS = ("ubuntu-22.04", "debian-12")
CONTAINERS = ("ubuntu-24.04", "ubuntu-26.04", "debian-13")
FORMATS = ("deb", "appimage")

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

# Proofs no CI run can produce; the release approver attests them.
EXTERNAL_GATES = (
    "Real desktop spot check on Pop!_OS 24.04: menu entry and icon, compositor/GPU rendering, "
    "the AppImage under XWayland in a Wayland session, the real administrator dialog.",
    "Provider connections other than starting one bridge login are not exercised by CI "
    "(no subscription or API account is created): they stay unverified.",
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
    return out


def expected_ids(scenario: str) -> tuple[str, ...]:
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


def cmd_matrix(args: argparse.Namespace) -> int:
    kind = "smoke" if args.which == "guests" else "compat"
    include = [dict(leg, name=leg_name(leg)) for leg in legs() if leg["kind"] == kind]
    print(json.dumps({"include": include}, separators=(",", ":")))
    return 0


def cmd_leg(args: argparse.Namespace) -> int:
    failed = []
    for result in load_leg(Path(args.leg_dir), expected_ids(args.scenario)):
        print(f"{result['status']:24} {result['id']}")
        for check in result.get("checks", []):
            if check.get("status") in ("fail", "manual-gate", "skipped-missing-prereq"):
                print(f"{'':24}   {check['status']}: {check.get('name')}: {check.get('detail')}")
        if result["status"] == "fail":
            failed.append(result["id"])
    return 1 if failed else 0


def cmd_collect(args: argparse.Namespace) -> int:
    root = Path(args.root)
    rows = []
    for leg in legs():
        name = leg_name(leg)
        for result in load_leg(root / name, expected_ids(leg["scenario"])):
            rows.append({"leg": name, **{k: leg[k] for k in ("target", "scenario", "format")},
                         "id": result["id"], "criterion": result.get("criterion", "?"),
                         "status": result["status"], "checks": result.get("checks", []),
                         "gui_proof": result.get("gui_proof", [])})
    failed = [r for r in rows if r["status"] == "fail"]
    summary = {"schema": 1, "rows": rows, "failed": len(failed),
               "manual_gates": sum(r["status"] == "manual-gate" for r in rows),
               "smoke_ok": not failed, "external_gates": list(EXTERNAL_GATES)}
    Path(args.out).write_text(json.dumps(summary, indent=2))
    Path(args.markdown).write_text(render(summary, None))
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


def cmd_finalize(args: argparse.Namespace) -> int:
    summary = json.loads(Path(args.summary).read_text())
    model = model_proof(Path(args.model) if args.model else None)
    summary["model_proof"] = {k: v for k, v in model.items() if k != "results"}
    summary["model_results"] = model.get("results", [])
    summary["public_ready"] = bool(summary["smoke_ok"]) and model["status"] == "pass"
    Path(args.out).write_text(json.dumps(summary, indent=2))
    Path(args.markdown).write_text(render(summary, model))
    print(f"public_ready={'true' if summary['public_ready'] else 'false'}")
    return 0


def render(summary: dict[str, Any], model: dict[str, Any] | None) -> str:
    lines = ["## Linux release proof", ""]
    lines.append(f"Smoke results: {'no failure' if summary['smoke_ok'] else str(summary['failed']) + ' failed'}, "
                 f"{summary['manual_gates']} manual gate(s).")
    if model is not None:
        lines.append(f"Model-account proof: **{model['status']}** ({model['detail']}).")
        verdict = "may be published" if summary.get("public_ready") else "stays a draft"
        lines.append(f"Release {verdict}.")
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
    lines += ["", "### Outside CI (the approver attests them)", ""]
    lines += [f"- {gate}" for gate in summary["external_gates"]]
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    matrix = sub.add_parser("matrix")
    matrix.add_argument("which", choices=("guests", "containers"))
    matrix.set_defaults(run=cmd_matrix)
    leg = sub.add_parser("leg")
    leg.add_argument("leg_dir")
    leg.add_argument("scenario", choices=(*SCENARIOS, "compat"))
    leg.set_defaults(run=cmd_leg)
    collect = sub.add_parser("collect")
    collect.add_argument("root")
    collect.add_argument("--out", required=True)
    collect.add_argument("--markdown", required=True)
    collect.set_defaults(run=cmd_collect)
    finalize = sub.add_parser("finalize")
    finalize.add_argument("--summary", required=True)
    finalize.add_argument("--model")
    finalize.add_argument("--out", required=True)
    finalize.add_argument("--markdown", required=True)
    finalize.set_defaults(run=cmd_finalize)
    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
