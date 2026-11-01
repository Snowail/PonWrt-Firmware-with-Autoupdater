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
    def test_single_and_all(self):
        catalog = json.loads((ROOT / "devices.json").read_text())
        self.assertEqual(matrix("all", "", "", catalog)["include"], catalog)
        self.assertEqual(matrix("", "an7581", "test", catalog)["include"],
                         [{"soc": "an7581", "device": "test"}])

    def test_multiple_and_invalid(self):
        self.assertEqual(len(matrix("an7581:md, an7583:mf", "", "", [])["include"]), 2)
        for selection in ("an7581:md,an7581:md", "an7582:md", "an7581:../../x",
                          "bad", "an7581:md,", ",".join("an7581:d" + str(i) for i in range(9))):
            with self.assertRaises(ValueError):
                matrix(selection, "", "", [])

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
