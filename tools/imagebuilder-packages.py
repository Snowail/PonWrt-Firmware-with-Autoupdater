#!/usr/bin/env python3
"""Resolve selected Kconfig symbols to binary packages present in this builder."""
import re
import sys
from pathlib import Path


def resolve(selected, metadata, archives):
    result = []
    for block in re.split(r"\n\s*\n", metadata):
        fields = dict(re.findall(r"^([\w-]+):[ \t]*(.*)$", block, re.MULTILINE))
        name = fields.get("Package")
        if name not in selected or fields.get("Build-Only") == "1":
            continue
        abi = fields.get("ABIVersion", "")
        prefixes = (name + "-", name + abi + "-", name + "_")
        if any(archive.startswith(prefixes) and archive.endswith((".apk", ".ipk")) for archive in archives):
            result.append(name)
    if not result:
        raise ValueError("No installable packages resolved from Image Builder metadata")
    return sorted(set(result))


if __name__ == "__main__":
    builder = Path(sys.argv[1])
    packages = resolve(set(Path(sys.argv[2]).read_text().split()),
                       (builder / ".packageinfo").read_text(),
                       [path.name for path in (builder / "packages").iterdir()])
    required = set(Path(sys.argv[3]).read_text().split()) | {"luci-app-ponwrt-update"}
    if required - set(packages):
        raise ValueError(f"Missing required binary packages: {sorted(required - set(packages))}")
    print(" ".join(packages))
