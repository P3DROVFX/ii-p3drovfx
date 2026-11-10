#!/usr/bin/env python3
"""Status and install plans for the packages in defaults/dependencies.json.

The one place that knows what the fork needs on top of the base install and
whether it is there. The setup script asks it what to install; Settings asks it
what to show. It never installs anything itself: that needs a terminal for sudo,
and the setup script owns that part.

  deps.py status [--json]              every feature, and whether it is present:
                                       tier, id, status, installable, label, missing
  deps.py env                          distro and AUR helper, as deps.py sees them
  deps.py plan (--tier T | --features a,b | --optional-missing)
                                       what an install would do, one TSV row per
                                       package: kind, feature, package, known
  deps.py summary                      required_missing and optional_available
  deps.py record  <feature> <pkg>...   remember packages the fork installed
  deps.py owned   <feature>            recorded packages that are safe to remove
  deps.py forget  <feature> <pkg>...   drop them from the record

`kind` is repo, aur (needs yay or paru) or unavailable (not packaged here).
`known` is 1 when the package manager already has the package even though the
check failed, so the caller does not record it as one the fork installed.

Standard library only: this runs mid-install on a bare machine, before the
shell's venv exists, with the system python3 the shell's helpers use.
"""

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_MANIFEST = HERE.parent.parent / "defaults" / "dependencies.json"
SBIN_DIRS = ("/usr/sbin", "/sbin", "/usr/local/sbin")


def state_file():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "ii-p3drovfx" / "deps.json"


def detect_distro():
    forced = os.environ.get("II_DEPS_DISTRO")
    if forced:
        return forced
    fields = {}
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            key, _, value = line.partition("=")
            fields[key] = value.strip().strip('"').lower()
    except OSError:
        pass
    ids = {fields.get("ID", "")} | set(fields.get("ID_LIKE", "").split())
    if "arch" in ids or Path("/etc/arch-release").exists():
        return "arch"
    if "fedora" in ids or Path("/etc/fedora-release").exists():
        return "fedora"
    return "other"


def aur_helper():
    for name in ("yay", "paru"):
        if shutil.which(name):
            return name
    return ""


def load_manifest(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    features = data.get("features")
    if not isinstance(features, list):
        raise ValueError("manifest has no features list")
    return features


def package_name(pkg, distro):
    """The package on this distro, or None when it is not packaged here."""
    if distro in pkg:
        return pkg[distro]
    if distro in ("arch", "fedora"):
        return pkg.get("name")
    return None


def has_bin(names):
    if isinstance(names, str):
        names = [names]
    for name in names:
        if shutil.which(name):
            return True
        # dnsmasq and friends live in sbin, which is not on every user's PATH.
        if any(os.access(os.path.join(d, name), os.X_OK) for d in SBIN_DIRS):
            return True
    return False


def has_python(module):
    try:
        return importlib.util.find_spec(module) is not None
    except (ImportError, ValueError):
        return False


def pm_has(name, distro):
    """Whether the package manager has <name> installed."""
    if not name:
        return False
    if distro == "arch" and shutil.which("pacman"):
        cmd = ["pacman", "-Qq", name]
    elif distro == "fedora" and shutil.which("rpm"):
        cmd = ["rpm", "-q", "--quiet", name]
    else:
        return False
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    except OSError:
        return False


def package_present(pkg, distro):
    if "bin" in pkg:
        return has_bin(pkg["bin"])
    if "python" in pkg:
        return has_python(pkg["python"])
    return pm_has(package_name(pkg, distro), distro)


def evaluate(features, distro):
    helper = aur_helper() if distro == "arch" else ""
    out = []
    for feature in features:
        rows = []
        for pkg in feature.get("packages", []):
            name = package_name(pkg, distro)
            aur = distro == "arch" and bool(pkg.get("aur"))
            present = package_present(pkg, distro)
            rows.append({
                "name": name or pkg.get("arch") or pkg.get("name") or "",
                "present": present,
                "available": bool(name),
                "aur": aur,
                # Installable from here, now: an AUR package with no helper is not.
                "installable": bool(name) and (not aur or bool(helper)),
            })
        present = sum(1 for r in rows if r["present"])
        if rows and present == len(rows):
            status = "installed"
        elif present:
            status = "partial"
        elif any(r["available"] for r in rows):
            status = "missing"
        else:
            status = "unavailable"
        out.append({
            "id": feature.get("id", ""),
            "tier": feature.get("tier", "optional"),
            "label": feature.get("label", feature.get("id", "")),
            "description": feature.get("description", ""),
            "status": status,
            "installable": any(r["installable"] and not r["present"] for r in rows),
            "packages": rows,
        })
    return {"distro": distro, "aurHelper": helper, "features": out}


def select(report, args):
    features = report["features"]
    if args.tier:
        return [f for f in features if f["tier"] == args.tier]
    if args.optional_missing:
        return [f for f in features if f["tier"] == "optional" and f["status"] in ("missing", "partial")]
    wanted = [w for w in (args.features or "").replace(" ", ",").split(",") if w]
    by_id = {f["id"]: f for f in features}
    unknown = [w for w in wanted if w not in by_id]
    if unknown:
        print("unknown feature: " + ", ".join(unknown), file=sys.stderr)
        sys.exit(3)
    return [by_id[w] for w in wanted]


def cmd_status(report, args):
    if args.json:
        json.dump(report, sys.stdout)
        sys.stdout.write("\n")
        return 0
    for f in report["features"]:
        missing = [p["name"] for p in f["packages"] if not p["present"]]
        print("\t".join([
            f["tier"], f["id"], f["status"], "1" if f["installable"] else "0",
            f["label"], " ".join(missing),
        ]))
    return 0


def cmd_env(report, _args):
    print(f"{report['distro']}\t{report['aurHelper']}")
    return 0


def cmd_plan(report, args):
    distro = report["distro"]
    seen = set()
    for f in select(report, args):
        for p in f["packages"]:
            if p["present"] or p["name"] in seen:
                continue
            seen.add(p["name"])
            if not p["available"]:
                kind = "unavailable"
            elif p["aur"]:
                kind = "aur"
            else:
                kind = "repo"
            known = "1" if p["available"] and pm_has(p["name"], distro) else "0"
            print("\t".join([kind, f["id"], p["name"], known]))
    return 0


def cmd_summary(report, _args):
    required = sum(
        1 for f in report["features"]
        for p in f["packages"]
        if f["tier"] == "required" and not p["present"]
    )
    optional = sum(
        1 for f in report["features"]
        if f["tier"] == "optional" and f["status"] in ("missing", "partial") and f["installable"]
    )
    print(f"{required}\t{optional}")
    return 0


def read_state():
    try:
        data = json.loads(state_file().read_text())
        installed = data.get("installed", {})
        if isinstance(installed, dict):
            return {k: list(v) for k, v in installed.items() if isinstance(v, list)}
    except (OSError, ValueError):
        pass
    return {}


def write_state(installed):
    path = state_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"version": 1, "installed": installed}, indent=2) + "\n")
    tmp.replace(path)


def cmd_record(args):
    installed = read_state()
    names = installed.setdefault(args.feature, [])
    for pkg in args.packages:
        if pkg not in names:
            names.append(pkg)
    write_state(installed)
    return 0


def cmd_owned(args):
    """What removing <feature> may uninstall: packages the fork put there for it
    and for nothing else, and which are still installed."""
    distro = detect_distro()
    installed = read_state()
    others = {p for fid, pkgs in installed.items() if fid != args.feature for p in pkgs}
    for pkg in installed.get(args.feature, []):
        if pkg not in others and pm_has(pkg, distro):
            print(pkg)
    return 0


def cmd_forget(args):
    installed = read_state()
    left = [p for p in installed.get(args.feature, []) if p not in set(args.packages)]
    if left:
        installed[args.feature] = left
    else:
        installed.pop(args.feature, None)
    write_state(installed)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_status = sub.add_parser("status")
    p_status.add_argument("--json", action="store_true")

    p_plan = sub.add_parser("plan")
    group = p_plan.add_mutually_exclusive_group(required=True)
    group.add_argument("--tier", choices=["required", "optional"])
    group.add_argument("--features")
    group.add_argument("--optional-missing", action="store_true")

    sub.add_parser("summary")
    sub.add_parser("env")

    for name in ("record", "forget"):
        p = sub.add_parser(name)
        p.add_argument("feature")
        p.add_argument("packages", nargs="+")
    p_owned = sub.add_parser("owned")
    p_owned.add_argument("feature")

    args = parser.parse_args(argv)

    if args.cmd == "record":
        return cmd_record(args)
    if args.cmd == "owned":
        return cmd_owned(args)
    if args.cmd == "forget":
        return cmd_forget(args)

    try:
        features = load_manifest(args.manifest)
    except (OSError, ValueError) as exc:
        print(f"cannot read {args.manifest}: {exc}", file=sys.stderr)
        return 2
    report = evaluate(features, detect_distro())
    commands = {"status": cmd_status, "plan": cmd_plan, "summary": cmd_summary, "env": cmd_env}
    return commands[args.cmd](report, args)


if __name__ == "__main__":
    sys.exit(main())
