#!/usr/bin/env python3
"""Extract US nodes from Clash Verge or a Clash YAML file, without printing secrets."""
import argparse
import os
import re
import sys
from pathlib import Path

import yaml

US_PATTERN = re.compile(r"美国|西美|🇺🇸|(^|[^a-z])us([^a-z]|$)|united states", re.I)
STATE = Path(os.environ.get("SANDBOX_STATE_DIR", "/sandbox/state"))
VERGE = os.environ.get("SANDBOX_VERGE_DIR", "")


def current_profile_nodes(verge: str):
    root = Path(verge)
    profiles = yaml.safe_load((root / "profiles.yaml").read_text(encoding="utf-8"))
    uid = profiles.get("current")
    if not uid:
        raise ValueError("profiles.yaml has no current profile")
    path = root / "profiles" / f"{uid}.yaml"
    if not path.is_file():
        raise ValueError(f"current profile file is missing: {path.name}")
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return data.get("proxies") or []


def import_nodes(path: str):
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError("the YAML root must be a mapping")
    return data.get("proxies") or []


def us_nodes(nodes):
    return [node for node in nodes if US_PATTERN.search(str(node.get("name", "")))]


def selected_nodes(nodes):
    us = us_nodes(nodes)
    if not us:
        raise ValueError("no US nodes found (looked for 美国/西美/US/United States)")
    pin_file = STATE / "pinned-node"
    pinned = pin_file.read_text(encoding="utf-8").strip() if pin_file.exists() else ""
    if not pinned:
        return us, "auto (url-test)"
    selected = [node for node in us if str(node.get("name")) == pinned]
    if not selected:
        available = ", ".join(str(node.get("name")) for node in us)
        raise ValueError(f"pinned node not found: {pinned}. Available US nodes: {available}")
    return selected, f"pinned: {pinned}"


def write_nodes(nodes):
    out = STATE / "gateway" / "proxies.yaml"
    if out.is_dir():
        raise ValueError(f"{out} is a directory, not a file; remove it and retry")
    out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(STATE, 0o700)
    os.chmod(out.parent, 0o700)
    # Write in place: replacing the file would change its inode and break the
    # gateway's single-file bind mount. 0600 protects the node credentials.
    descriptor = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        yaml.safe_dump({"proxies": nodes}, handle, allow_unicode=True, sort_keys=False)
    os.chmod(out, 0o600)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="list US node names from the current Verge profile")
    refresh = sub.add_parser("refresh", help="write state/gateway/proxies.yaml")
    refresh.add_argument("--from-file", metavar="YAML", help="import this Clash YAML instead of Verge")
    args = parser.parse_args()

    if args.command == "list":
        for node in us_nodes(current_profile_nodes(VERGE)):
            print(node.get("name", "<unnamed>"))
        return

    nodes = import_nodes(args.from_file) if args.from_file else current_profile_nodes(VERGE)
    selected, mode = selected_nodes(nodes)
    out = write_nodes(selected)
    print(f"{len(selected)} US node(s) written to {out} ({mode})")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
