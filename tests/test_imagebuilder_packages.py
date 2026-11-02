import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("ib_packages", Path(__file__).resolve().parents[1] / "tools/imagebuilder-packages.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ImageBuilderPackagesTests(unittest.TestCase):
    def test_only_real_binary_packages_are_installed(self):
        metadata = "Package: dnsmasq-full\nVersion: 1\n\nPackage: u-boot-test\nBuild-Only: 1\n\nPackage: libexample\nABIVersion: 2026\n"
        selected = {"dnsmasq-full", "dnsmasq_full_auth", "u-boot-test", "libexample", "TAR_ZSTD"}
        self.assertEqual(module.resolve(selected, metadata,
                         ["dnsmasq-full-1.apk", "libexample2026-1.apk", "u-boot-test-1.apk"]),
                         ["dnsmasq-full", "libexample"])
