#!/usr/bin/env python3
"""Materialize pinned feeds and record verified revisions for each build."""
import json
import re
import subprocess
import sys
from pathlib import Path


def main(mode, lock_path, source):
    lock = json.loads(Path(lock_path).read_text(encoding="utf-8"))
    source = Path(source)
    entries = {**lock["feeds"], "aurora": lock["aurora"]}
    for name, entry in entries.items():
        if not re.fullmatch(r"[a-z_]+", name) or not re.fullmatch(r"[0-9a-f]{40}", entry["commit"]):
            raise ValueError(f"Invalid lock entry: {name}")
        if not re.fullmatch(r"https://github.com/[\w.-]+/[\w.-]+\.git", entry["url"]):
            raise ValueError(f"Invalid source URL: {name}")
    if mode == "prepare":
        (source / "feeds.conf").write_text("".join(
            f"src-git {name} {entry['url']}^{entry['commit']}\n"
            for name, entry in lock["feeds"].items()), encoding="utf-8")
    elif mode == "verify":
        resolved = {}
        for name, entry in entries.items():
            path = source / ("package/luci-theme-aurora" if name == "aurora" else f"feeds/{name}")
            sha = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
            if sha != entry["commit"]:
                raise ValueError(f"Revision mismatch for {name}: {sha}")
            resolved[name] = {**entry, "commit": sha}
        resolved["ponwrt"] = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        print(json.dumps(resolved, indent=2))
    else:
        raise ValueError(f"Unknown mode: {mode}")


if __name__ == "__main__":
    main(*sys.argv[1:])
