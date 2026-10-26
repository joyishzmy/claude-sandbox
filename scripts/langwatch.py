#!/usr/bin/env python3
"""Poll a workspace and report text files containing CJK characters."""
import argparse
import os
import re
import sys
import time
from pathlib import Path

HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u3000-\u303f\uff00-\uffef]")
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "target", "build", "dist"}
MAX_SIZE = 5_000_000


def has_cjk(path: Path) -> bool:
    try:
        if path.stat().st_size > MAX_SIZE:
            return False
        data = path.read_bytes()
        if b"\x00" in data[:8192]:
            return False
        return bool(HAN.search(data.decode("utf-8", errors="ignore")))
    except OSError:
        return False


def scan(root: Path, seen: dict, initial: bool = False) -> int:
    hits = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            try:
                mtime = path.stat().st_mtime
            except OSError:
                continue
            if seen.get(str(path)) == mtime:
                continue
            seen[str(path)] = mtime
            if has_cjk(path):
                hits += 1
                print(f"[langwatch] {time.strftime('%H:%M:%S')} CJK content: {path}", flush=True)
    return hits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--once", action="store_true", help="scan once; exit 1 if CJK is found")
    args = parser.parse_args()
    root = args.workspace.resolve()
    if not root.is_dir():
        parser.error(f"not a directory: {root}")
    if args.once:
        found = scan(root, {})
        if not found:
            print(f"[langwatch] no CJK content found in {root}")
        sys.exit(1 if found else 0)

    print(f"[langwatch] watching {root} (English-only policy). Ctrl+C to stop.", flush=True)
    seen = {}
    while True:
        scan(root, seen)
        time.sleep(2)


if __name__ == "__main__":
    main()
