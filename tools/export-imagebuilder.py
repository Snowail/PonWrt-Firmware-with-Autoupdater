#!/usr/bin/env python3
"""Export a self-contained, versioned Image Builder and its matching files."""
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path


def export(source, output, soc, pin):
    source, output = Path(source), Path(output)
    binary = source / "bin/targets/airoha" / soc
    archives = list(binary.glob("*-imagebuilder-*.tar.zst"))
    if len(archives) != 1:
        raise ValueError(f"Expected one Image Builder, found {archives}")
    profiles = json.loads((binary / "profiles.json").read_text())
    enabled = re.findall(rf"^CONFIG_TARGET_DEVICE_airoha_{soc}_DEVICE_(.+)=y$",
                         (source / ".config").read_text(), re.MULTILINE)
    if not set(enabled) <= profiles["profiles"].keys():
        raise ValueError("Base output is missing enabled profiles")
    output.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(archives[0], output / "imagebuilder.tar.zst")
    shutil.copytree(source / "files", output / "files")
    (output / "files/etc/ponwrt-version").unlink()
    packages = re.findall(r"^CONFIG_PACKAGE_(.+)=y$", (source / ".config").read_text(), re.MULTILINE)
    if not packages or "luci-app-ponwrt-update" not in packages:
        raise ValueError("Missing configured packages")
    (output / "packages.txt").write_text("\n".join(sorted(packages)) + "\n")
    shutil.copyfile(binary / "profiles.json", output / "base-profiles.json")
    (output / "base.json").write_text(json.dumps({"soc": soc, "commit": pin,
                                                  "devices": enabled}, indent=2) + "\n")
    # These are baseline rescue images, separate from personalized sysupgrade images.
    recovery = output / "recovery"
    recovery.mkdir()
    for path in binary.glob("*-initramfs*.itb"):
        shutil.copyfile(path, recovery / path.name)
    paths = [path for path in output.rglob("*") if path.is_file()]
    checksums = []
    for path in sorted(paths):
        with path.open("rb") as stream:
            checksum = hashlib.file_digest(stream, "sha256").hexdigest()
        checksums.append(f"{checksum}  {path.relative_to(output).as_posix()}\n")
    (output / "sha256sums").write_text("".join(checksums))


if __name__ == "__main__":
    export(*sys.argv[1:])
