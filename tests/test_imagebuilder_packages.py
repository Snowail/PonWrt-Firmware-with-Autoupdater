import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("ib_packages", Path(__file__).resolve().parents[1] / "tools/imagebuilder-packages.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ImageBuilderPackagesTests(unittest.TestCase):
    def test_old_base_does_not_restore_lucky_duplicates(self):
        names = ["lucky", "ddns-scripts", "ddns-scripts-cloudflare", "luci-app-wol", "etherwake", "frpc"]
        metadata = "\n\n".join("Package: " + name + "\nVersion: 1" for name in names)
        self.assertEqual(module.resolve(set(names), metadata, [name + "-1.apk" for name in names]), ["lucky"])

    def test_only_real_binary_packages_are_installed(self):
        metadata = "Package: dnsmasq-full\nVersion: 1\n\nPackage: u-boot-test\nBuild-Only: 1\n\nPackage: libexample\nABIVersion: 2026\n"
        selected = {"dnsmasq-full", "dnsmasq_full_auth", "u-boot-test", "libexample", "TAR_ZSTD"}
        self.assertEqual(module.resolve(selected, metadata,
                         ["dnsmasq-full-1.apk", "libexample2026-1.apk", "u-boot-test-1.apk"]),
                         ["dnsmasq-full", "libexample"])
