#!/usr/bin/env python3
"""Validate dispatch targets before allocating expensive build runners."""
import json
import os
import re
from pathlib import Path


def matrix(configs):
    targets = []
    for soc, config in configs.items():
        pattern = rf"^CONFIG_TARGET_DEVICE_airoha_{soc}_DEVICE_([a-z0-9][a-z0-9_-]*)=y$"
        devices = re.findall(pattern, config, re.MULTILINE)
        if not devices or len(devices) != len(set(devices)):
            raise ValueError(f"Missing or duplicate enabled profiles for {soc}")
        targets.extend({"soc": soc, "device": device, "cache_writer": i == 0}
                       for i, device in enumerate(devices))
    return {"include": targets}


if __name__ == "__main__":
    configs = {soc: Path(f"upstream/configs/{soc}.config").read_text()
               for soc in ("an7581", "an7583")}
    result = matrix(configs)
    if Path("retry-jobs.json").exists():
        pages = json.loads(Path("retry-jobs.json").read_text())
        succeeded = {job["name"] for page in pages for job in page["jobs"]
                     if job["conclusion"] == "success"}
        result["include"] = [target for target in result["include"]
                             if f'{target["soc"]} / {target["device"]}' not in succeeded]
        if not result["include"]:
            raise ValueError("All profiles already succeeded")
    bases = {"include": [{"soc": soc} for soc in sorted({t["soc"] for t in result["include"]})]}
    print("Building", len(result["include"]), "profiles:", result["include"])
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.write("bases=" + json.dumps(bases, separators=(",", ":")) + "\n")
        stream.write("matrix=" + json.dumps(result, separators=(",", ":")) + "\n")
