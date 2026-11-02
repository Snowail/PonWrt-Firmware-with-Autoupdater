import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import hashlib

spec = importlib.util.spec_from_file_location("prepare_release", Path(__file__).resolve().parents[1] / "tools/prepare-release.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseCatalogTests(unittest.TestCase):
    def test_single_catalog_with_distinct_manifests_and_legacy_md_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, output = Path(tmp) / "source", Path(tmp) / "output"
            for device in ("nokia_xg-040g-md-ubi", "nokia_xg-040g-mf-ubi"):
                folder = source / device
                folder.mkdir(parents=True)
                image = folder / (device + ".itb")
                image.write_bytes(b"fixture")
                info = dict(device=device, target="an7581", commit="a" * 40,
                            built="20261102-100000", version=device + "-123-1", file=image.name,
                            sha256=hashlib.sha256(image.read_bytes()).hexdigest())
                (folder / "version.json").write_text(json.dumps(info))
                (folder / "profiles.json").write_text(json.dumps({"linux_kernel": {"version": "6.18.55"}}))
                (folder / "target.manifest").write_text("package 1\n")
                (folder / "sha256sums").write_text("".join(
                    hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n" for p in folder.iterdir()))
            result = module.prepare(source, output, "2026-10-23T12:56:41Z")
            self.assertEqual(len(result["devices"]), 2)
            self.assertNotIn("device", result)
            self.assertEqual(result["display_version"], "6.18.55 / 2026-10-23 20:56:41")
            self.assertEqual(len(list(output.glob("*.manifest"))), 2)
            self.assertFalse((output / "profiles.json").exists())
            self.assertTrue(all(result["version"] in i["download_url"] for i in result["devices"].values()))
