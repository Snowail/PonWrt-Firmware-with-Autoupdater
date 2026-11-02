#!/usr/bin/env python3
"""Publish the unified firmware catalog after its release succeeds."""
import json
import shutil
import sys
from pathlib import Path


def publish(source, root):
    source, root = Path(source), Path(root)
    path = source / "version.json"
    catalog = json.loads(path.read_text(encoding="utf-8"))
    if catalog.get("schema") != 2 or not catalog.get("devices"):
        raise ValueError("Invalid unified firmware catalog")
    shutil.copyfile(path, root / "version.json")


if __name__ == "__main__":
    publish(sys.argv[1], ".")
