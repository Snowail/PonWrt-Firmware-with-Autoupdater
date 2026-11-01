import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


matrix = module("build-matrix").matrix
publish = module("publish-metadata").publish


class MatrixTests(unittest.TestCase):
    def test_all_enabled_profiles_across_targets(self):
        configs = {soc: "\n".join(f"CONFIG_TARGET_DEVICE_airoha_{soc}_DEVICE_test-{i}=y"
                                  for i in range(10)) for soc in ("an7581", "an7583")}
        self.assertEqual(len(matrix(configs)["include"]), 20)
        with self.assertRaises(ValueError):
            matrix({"an7583": "# no devices"})

    def test_metadata_channels_are_independent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            src = root / "artifacts"
            (root / "version.json").write_text('old MD')
            for soc, device in (("an7583", "nokia_xg-040g-mf-ubi"),):
                folder = src / device
                folder.mkdir(parents=True)
                (folder / "version.json").write_text(json.dumps(dict(target=soc, device=device)))
            publish(src, root)
            self.assertEqual((root / "version.json").read_text(), 'old MD')
            self.assertTrue((root / "versions/an7583/nokia_xg-040g-mf-ubi/version.json").exists())
            folder = src / "md"
            folder.mkdir()
            (folder / "version.json").write_text(json.dumps(dict(target="an7581", device="nokia_xg-040g-md-ubi")))
            publish(src, root)
            self.assertEqual(json.loads((root / "version.json").read_text())["device"], "nokia_xg-040g-md-ubi")
