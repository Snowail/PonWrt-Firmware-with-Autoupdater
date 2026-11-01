#!/usr/bin/env python3
"""Fail closed: only publish exact device images with verified hashes and packages."""
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def collect(mode, source, output, soc, device):
    source, output = Path(source), Path(output)
    if output.exists() and any(output.iterdir()):
        raise ValueError("Output directory must be empty")
    files = []
    if mode == "packages":
        for name in ("luci-app-ponwrt-update", "curl", "jsonfilter"):
            # APK uses name-version; legacy IPK uses name_version.
            matches = [p for p in (source / "bin/packages").rglob("*") if p.is_file()
                       and re.fullmatch(re.escape(name) + r"(?:-[0-9].*\.apk|_[0-9].*\.ipk)", p.name)]
            if len(matches) != 1:
                raise ValueError(f"Expected one {name} package, found {matches}")
            files.extend(matches)
        metadata = None
    elif mode == "firmware":
        binary = source / "bin/targets/airoha" / soc
        prefix = f"ponwrt-airoha-{soc}-{device}"
        profiles = json.loads((binary / "profiles.json").read_text())
        profile = profiles["profiles"][device]
        sysupgrade = f"{prefix}-squashfs-sysupgrade"
        names = [image["name"] for image in profile["images"]]
        candidates = [name for name in names if name in (sysupgrade + ".bin", sysupgrade + ".itb")]
        if len(candidates) != 1:
            raise ValueError(f"Missing image or ambiguous sysupgrade: {device}")
        images = [binary / candidates[0]]
        if candidates[0].endswith(".itb"):
            images.append(binary / f"{prefix}-initramfs-recovery.itb")
        for name in names:
            if (name.startswith(prefix + "-") and re.fullmatch(r"[a-zA-Z0-9_.-]+\.(bin|itb)", name)
                    and binary / name not in images):
                images.append(binary / name)
        checksums = {}
        for line in (binary / "sha256sums").read_text().splitlines():
            match = re.fullmatch(r"([0-9a-f]{64})\s+\*?(.+)", line)
            if match:
                checksums[match[2]] = match[1]
        for path in images:
            if not path.is_file() or path.stat().st_size == 0:
                raise ValueError(f"Missing image: {path.name}")
            if checksums.get(path.name) != digest(path):
                raise ValueError(f"SHA256 mismatch: {path.name}")
        manifest = binary / f"{prefix}.manifest"
        if not manifest.is_file():
            # Multi-profile OpenWrt writes IMG_PREFIX.manifest without a device
            # suffix. Only accept it when this build contains exactly our device.
            if set(profiles["profiles"]) != {device}:
                raise ValueError("Target-level manifest requires exactly one device profile")
            manifest = binary / f"ponwrt-airoha-{soc}.manifest"
        if not manifest.is_file():
            raise ValueError(f"Missing package manifest: {manifest.name}")
        packages = {line.split()[0] for line in manifest.read_text().splitlines() if line.strip()}
        required = {"luci-app-ponwrt-update", "curl", "jsonfilter", "ca-bundle", "luci-mod-system"}
        if required - packages:
            raise ValueError(f"Missing image packages: {sorted(required - packages)}")
        advertised = {image["name"]: image["sha256"] for image in profile["images"]}
        for path in images:
            if advertised.get(path.name) != digest(path):
                raise ValueError(f"Profile image mismatch: {path.name}")
        version = source / "files/etc/ponwrt-version"
        info = dict(line.split("=", 1) for line in version.read_text().splitlines() if "=" in line)
        if info.get("device") != device or info.get("target") != soc:
            raise ValueError("Embedded device/target mismatch")
        if not re.fullmatch(r"[0-9a-f]{40}", info.get("commit", "")) or not re.fullmatch(r"[0-9]{8}-[0-9]{6}", info.get("built", "")):
            raise ValueError("Invalid embedded version")
        build_id = os.environ.get("GITHUB_RUN_ID", "local") + "-" + os.environ.get("GITHUB_RUN_ATTEMPT", "1")
        tag = f"{device}-{info['built']}-{build_id}"
        repo = os.environ.get("GITHUB_REPOSITORY", "Snowail/PonWrt-Firmware-with-Autoupdater")
        metadata = dict(version=tag, device=device, target=soc, commit=info["commit"], built=info["built"],
                        file=images[0].name, sha256=digest(images[0]), notes="automated build",
                        download_url=f"https://github.com/{repo}/releases/download/{tag}/{images[0].name}")
        files = images + [manifest, version, binary / "profiles.json"]
    else:
        raise ValueError(f"Unknown mode: {mode}")
    # Do not create a publishable output until all validation has passed.
    output.mkdir(parents=True, exist_ok=True)
    for path in files:
        shutil.copy2(path, output / path.name)
    if metadata:
        (output / "version.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (output / "sha256sums").write_text("".join(
        f"{digest(path)}  {path.name}\n" for path in sorted(output.iterdir()) if path.is_file()), encoding="utf-8")


if __name__ == "__main__":
    collect(*sys.argv[1:])
