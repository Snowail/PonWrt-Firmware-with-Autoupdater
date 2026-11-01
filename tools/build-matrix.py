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
    print("Building", len(result["include"]), "profiles:", result["include"])
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.write("matrix=" + json.dumps(result, separators=(",", ":")) + "\n")
