#!/usr/bin/env python3
"""Keep upstream package choices, but build exactly one device."""
import argparse
import re
from pathlib import Path


def prepare(text, soc, device, extras):
    symbol = f"CONFIG_TARGET_DEVICE_airoha_{soc}_DEVICE_{device}"
    if f"{symbol}=y" not in text.splitlines():
        raise ValueError(f"Device not enabled in upstream configs/{soc}.config: {device}")
    overrides = dict(line.split("=", 1) for line in extras)
    overrides.update({symbol: "y", "CONFIG_CCACHE": "y", "CONFIG_DEVEL": "y"})
    result = []
    for line in text.splitlines():
        match = re.match(r"(?:# )?(CONFIG_[^ =]+)(?:=| is not set)", line)
        key = match[1] if match else None
        if key and key.startswith("CONFIG_TARGET_DEVICE_") and "_DEVICE_" in key:
            if key.startswith("CONFIG_TARGET_DEVICE_PACKAGES_"):
                if key != f"CONFIG_TARGET_DEVICE_PACKAGES_airoha_{soc}_DEVICE_{device}":
                    continue
            else:
                continue
        if key in overrides:
            continue
        result.append(line)
    result.extend(f"{key}={value}" for key, value in overrides.items())
    return "\n".join(result) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("soc", choices=["an7581", "an7583"])
    parser.add_argument("device")
    parser.add_argument("extras", nargs="*")
    args = parser.parse_args()
    args.output.write_text(prepare(args.source.read_text(), args.soc, args.device, args.extras), encoding="utf-8")
