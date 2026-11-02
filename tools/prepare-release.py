#!/usr/bin/env python3
"""Merge validated device artifacts into one release and one version catalog."""
import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone, timedelta
from pathlib import Path


def prepare(source, output, upstream_time):
    source, output = Path(source), Path(output)
    records = []
    for path in sorted(source.glob("*/version.json")):
        info = json.loads(path.read_text())
        folder = path.parent
        for line in (folder / "sha256sums").read_text().splitlines():
            expected, name = line.split("  ", 1)
            if Path(name).name != name:
                raise ValueError("Unsafe asset filename")
            with (folder / name).open("rb") as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
                    raise ValueError(f"Checksum mismatch: {name}")
        profile = json.loads((folder / "profiles.json").read_text())
        records.append((folder, info, profile["linux_kernel"]["version"]))
    if not records or output.exists():
        raise ValueError("Missing input or nonempty release output")
    commits = {info["commit"] for _, info, _ in records}
    kernels = {kernel for _, _, kernel in records}
    if len(commits) != 1 or len(kernels) != 1:
        raise ValueError("Mixed source or kernel versions")
    kernel = kernels.pop()
    built = max(info["built"] for _, info, _ in records)
    run = re.search(r"-([0-9]+-[0-9]+)$", records[0][1]["version"])[1]
    tag = f"ponwrt-{kernel}-{built}-{run}"
    stamp = datetime.fromisoformat(upstream_time.replace("Z", "+00:00"))
    display = f"{kernel} / {stamp.astimezone(timezone(timedelta(hours=8))):%Y-%m-%d %H:%M:%S}"
    devices = {}
    output.mkdir(parents=True)
    for folder, original, _ in records:
        info = dict(original, version=tag, kernel=kernel, upstream_time=upstream_time, display_version=display)
        if info["device"] in devices:
            raise ValueError("Duplicate device")
        info["download_url"] = f"https://github.com/Snowail/PonWrt-Firmware-with-Autoupdater/releases/download/{tag}/{info['file']}"
        devices[info["device"]] = info
        assets = list(folder.glob("*.bin")) + list(folder.glob("*.itb"))
        for asset in assets:
            if (output / asset.name).exists():
                raise ValueError("Duplicate image asset")
            shutil.copyfile(asset, output / asset.name)
        manifest, = folder.glob("*.manifest")
        name = f"ponwrt-airoha-{info['target']}-{info['device']}.manifest"
        shutil.copyfile(manifest, output / name)
    catalog = dict(schema=2, version=tag, commit=next(iter(commits)), kernel=kernel,
                   upstream_time=upstream_time, display_version=display,
                   built=built, devices=devices)
    (output / "version.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checksums = []
    for path in sorted(output.iterdir()):
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        checksums.append(f"{digest}  {path.name}\n")
    (output / "sha256sums").write_text("".join(checksums))
    return catalog


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("output")
    parser.add_argument("upstream_time")
    args = parser.parse_args()
    prepare(args.source, args.output, args.upstream_time)
