#!/usr/bin/env python3
"""Publish all device pointers together, keeping the legacy Nokia MD pointer."""
import json
import re
import shutil
import sys
from pathlib import Path


def publish(source, root):
    source, root = Path(source), Path(root)
    records = []
    seen = set()
    for path in sorted(source.glob("*/version.json")):
        info = json.loads(path.read_text())
        soc, device = info["target"], info["device"]
        if soc not in ("an7581", "an7583") or not re.fullmatch(r"[a-z0-9][a-z0-9_-]+", device):
            raise ValueError("Invalid device metadata")
        if (soc, device) in seen:
            raise ValueError("Duplicate device metadata")
        seen.add((soc, device))
        records.append((path, soc, device))
    if not records:
        raise ValueError("No published firmware metadata")
    for path, soc, device in records:
        dest = root / "versions" / soc / device / "version.json"
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, dest)
        if (soc, device) == ("an7581", "nokia_xg-040g-md-ubi"):
            shutil.copyfile(path, root / "version.json")


if __name__ == "__main__":
    publish(sys.argv[1], ".")
