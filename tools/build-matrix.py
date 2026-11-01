#!/usr/bin/env python3
"""Validate dispatch targets before allocating expensive build runners."""
import json
import os
import re
from pathlib import Path


def matrix(selection, soc, device, catalog):
    if not selection.strip():
        targets = [{"soc": soc, "device": device}]
    elif selection.strip() == "all":
        targets = catalog
    else:
        targets = []
        for item in selection.split(","):
            parts = item.strip().split(":")
            if len(parts) != 2:
                raise ValueError("Use all or soc:profile,soc:profile")
            targets.append(dict(zip(("soc", "device"), parts)))
    if not 1 <= len(targets) <= 8:
        raise ValueError("Select between 1 and 8 devices")
    seen = set()
    for target in targets:
        soc, device = target["soc"], target["device"]
        if soc not in ("an7581", "an7583") or not re.fullmatch(r"[a-z0-9][a-z0-9_-]+", device):
            raise ValueError("Invalid SoC or device")
        if (soc, device) in seen:
            raise ValueError("Duplicate target")
        seen.add((soc, device))
    return {"include": targets}


if __name__ == "__main__":
    result = matrix(os.environ.get("TARGETS", ""), os.environ["SOC"],
                    os.environ["DEVICE"], json.loads(Path("devices.json").read_text()))
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.write("matrix=" + json.dumps(result, separators=(",", ":")) + "\n")
