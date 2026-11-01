#!/usr/bin/env python3
"""Build an on-device update using the same overlay and flash page as the firmware."""
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FLASH = "www/luci-static/resources/view/system/flash.js"
BACKEND = "usr/bin/ponwrt-update-check"
ACL = "usr/share/rpcd/acl.d/luci-app-ponwrt-update.json"


def build(output):
    lock = json.loads((REPO / "sources.lock.json").read_text(encoding="utf-8"))
    luci = lock["feeds"]["luci"]
    if not all(re.fullmatch(r"[a-f0-9]{40}", pin) for pin in (lock["ponwrt"], luci["commit"])):
        raise ValueError("Expected full commit IDs in sources.lock.json")
    repo_name = re.fullmatch(r"https://github\.com/([\w.-]+/[\w.-]+)\.git", luci["url"])
    if not repo_name:
        raise ValueError("Invalid locked LuCI repository")
    url = (f"https://raw.githubusercontent.com/{repo_name[1]}/{luci['commit']}/"
           "modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js")
    revision = subprocess.check_output(["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True).strip()
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "flash.js"
        subprocess.run(["curl", "-fsSL", "--retry", "3", "--max-time", "60", "-o", str(page), url], check=True)
        subprocess.run([sys.executable, str(REPO / "tools/patch-flash.py"), str(page)], check=True)
        subprocess.run(["node", "--check", str(page)], check=True)
        files = {
            "payload/" + FLASH: (page, 0o644),
            "payload/" + BACKEND: (REPO / "overlay" / BACKEND, 0o755),
            "payload/" + ACL: (REPO / "overlay" / ACL, 0o644),
            "apply.sh": (REPO / "fast-ui/apply.sh", 0o755),
            "README.md": (REPO / "fast-ui/README.md", 0o644),
        }
        # Explicit Unix permissions and line endings also work in Windows checkouts.
        contents = {name: (path.read_text(encoding="utf-8").encode(), mode)
                    for name, (path, mode) in files.items()}
    json.loads(contents["payload/" + ACL][0])
    contents["build-info"] = (f"ponwrt={lock['ponwrt']}\nluci={luci['commit']}\nsource={revision}\n".encode(), 0o644)
    sums = "".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n" for name, (data, _) in contents.items())
    contents["sha256sums"] = (sums.encode(), 0o644)
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("Output directory must be empty")
    bundle = output / "ponwrt-fast-ui.tar.gz"
    with tarfile.open(bundle, "w:gz") as archive:
        for name, (data, mode) in contents.items():
            member = tarfile.TarInfo("ponwrt-fast-ui/" + name)
            member.mode, member.size = mode, len(data)
            archive.addfile(member, io.BytesIO(data))
    (output / "sha256sums").write_bytes(f"{hashlib.sha256(bundle.read_bytes()).hexdigest()}  {bundle.name}\n".encode())
    print(f"{bundle.name}: {bundle.stat().st_size} bytes; source {revision}")


if __name__ == "__main__":
    build(Path(sys.argv[1]))
