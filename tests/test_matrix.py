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

    def test_only_unified_catalog_is_published(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "release"
            source.mkdir()
            catalog = dict(schema=2, devices={"test": {"device": "test"}})
            (source / "version.json").write_text(json.dumps(catalog))
            publish(source, root)
            self.assertEqual(json.loads((root / "version.json").read_text()), catalog)
            self.assertFalse((root / "versions").exists())
