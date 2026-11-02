#!/usr/bin/env python3
"""Resolve selected Kconfig symbols to binary packages present in this builder."""
import re
import fnmatch
import sys
from pathlib import Path

EXCLUDED = (Path(__file__).resolve().parents[1] / "excluded-packages.txt").read_text().split()


def excluded(name):
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in EXCLUDED)


def resolve(selected, metadata, archives):
    result = []
    for block in re.split(r"\n\s*\n", metadata):
        fields = dict(re.findall(r"^([\w-]+):[ \t]*(.*)$", block, re.MULTILINE))
        name = fields.get("Package")
        if name not in selected or excluded(name) or fields.get("Build-Only") == "1":
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
    names = re.findall(r"^Package:\s*(\S+)", (builder / ".packageinfo").read_text(), re.MULTILINE)
    # Remove profile defaults too, including binaries present in older cached bases.
    removals = ["-" + name for name in sorted(set(names)) if excluded(name)]
    print(" ".join(packages + removals))
