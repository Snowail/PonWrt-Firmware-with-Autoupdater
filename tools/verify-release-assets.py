#!/usr/bin/env python3
"""Require every uploaded asset to match the prepared release exactly."""
import hashlib
import json
import sys
from pathlib import Path


def verify(folder, metadata):
    files = {p.name: p for p in Path(folder).iterdir() if p.is_file()}
    assets = {a["name"]: a for a in metadata["assets"]}
    if files.keys() != assets.keys():
        raise ValueError("Release asset list differs from verified local files")
    for name, path in files.items():
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if assets[name]["size"] != path.stat().st_size or assets[name]["digest"] != "sha256:" + digest:
            raise ValueError(f"Remote asset mismatch: {name}")


if __name__ == "__main__":
    verify(sys.argv[1], json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")))
