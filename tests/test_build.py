import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


prepare = module("prepare-config").prepare
collect = module("collect-artifacts").collect
patcher = module("patch-flash")
DEVICE = "nokia_xg-040g-md-ubi"
PREFIX = f"ponwrt-airoha-an7581-{DEVICE}"


class ConfigurationTests(unittest.TestCase):
    def test_only_requested_device_and_required_package(self):
        base = "\n".join([
            f"CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_{DEVICE}=y",
            f"CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_{DEVICE}-usb-sfp=y",
            "CONFIG_PACKAGE_kmod-pon=y",
            "# CONFIG_PACKAGE_curl is not set",
        ])
        result = prepare(base, "an7581", DEVICE, ["CONFIG_PACKAGE_curl=y"])
        self.assertNotIn("usb-sfp", result)
        self.assertIn("CONFIG_PACKAGE_kmod-pon=y", result)
        self.assertIn("CONFIG_PACKAGE_curl=y", result)
        self.assertIn("CONFIG_DEVEL=y", result)
        self.assertIn("CONFIG_CCACHE=y", result)
        self.assertNotIn("# CONFIG_PACKAGE_curl", result)

    def test_unknown_device_rejected(self):
        with self.assertRaises(ValueError):
            prepare("", "an7581", "wrong", [])


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.source = Path(self.tmp.name) / "source"
        self.out = Path(self.tmp.name) / "out"
        self.binary = self.source / "bin/targets/airoha/an7581"
        self.binary.mkdir(parents=True)
        images, hashes = [], []
        for suffix in ("squashfs-sysupgrade", "initramfs-recovery"):
            name = f"{PREFIX}-{suffix}.itb"
            (self.binary / name).write_bytes(b"synthetic test fixture: " + suffix.encode())
            sha = hashlib.sha256((self.binary / name).read_bytes()).hexdigest()
            images.append(dict(name=name, sha256=sha))
            hashes.append(f"{sha}  {name}")
        (self.binary / "sha256sums").write_text("\n".join(hashes))
        (self.binary / "profiles.json").write_text(json.dumps({"profiles": {DEVICE: {"images": images}}}))
        (self.binary / f"{PREFIX}.manifest").write_text("\n".join(
            f"{p} - 1.0" for p in ("luci-app-ponwrt-update", "curl", "jsonfilter", "ca-bundle", "luci-mod-system")))
        self.version = self.source / "files/etc/ponwrt-version"
        self.version.parent.mkdir(parents=True)
        self.version.write_text(f"device={DEVICE}\ntarget=an7581\ncommit={'a' * 40}\nbuilt=20261031-123456\n")

    def build(self):
        collect("firmware", self.source, self.out, "an7581", DEVICE)

    def test_success_and_complete_checksums(self):
        self.build()
        data = json.loads((self.out / "version.json").read_text())
        self.assertEqual(data["file"], f"{PREFIX}-squashfs-sysupgrade.itb")
        self.assertIn(f"/releases/download/{data['version']}/", data["download_url"])
        for line in (self.out / "sha256sums").read_text().splitlines():
            expected, name = line.split("  ")
            self.assertEqual(expected, hashlib.sha256((self.out / name).read_bytes()).hexdigest())

    def test_target_manifest_layout_from_run16(self):
        # The pinned upstream's Image/Manifest writes this target-level name.
        target_manifest = self.binary / "ponwrt-airoha-an7581.manifest"
        (self.binary / f"{PREFIX}.manifest").rename(target_manifest)
        self.build()
        self.assertTrue((self.out / target_manifest.name).is_file())

    def test_target_manifest_rejects_multiple_profiles(self):
        (self.binary / f"{PREFIX}.manifest").rename(self.binary / "ponwrt-airoha-an7581.manifest")
        path = self.binary / "profiles.json"
        data = json.loads(path.read_text())
        data["profiles"][DEVICE + "-usb-sfp"] = data["profiles"][DEVICE]
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "exactly one device"):
            self.build()
        self.assertFalse(self.out.exists())

    def test_target_manifest_still_requires_plugin(self):
        (self.binary / f"{PREFIX}.manifest").unlink()
        (self.binary / "ponwrt-airoha-an7581.manifest").write_text("curl - 1.0\n")
        with self.assertRaisesRegex(ValueError, "Missing image packages"):
            self.build()

    def test_device_manifest_takes_precedence(self):
        (self.binary / "ponwrt-airoha-an7581.manifest").write_text("curl - 1.0\n")
        self.build()
        self.assertTrue((self.out / f"{PREFIX}.manifest").is_file())
        self.assertFalse((self.out / "ponwrt-airoha-an7581.manifest").exists())

    def test_missing_manifests_rejected(self):
        (self.binary / f"{PREFIX}.manifest").unlink()
        with self.assertRaisesRegex(ValueError, "Missing package manifest"):
            self.build()

    def test_similar_device_cannot_substitute(self):
        p = self.binary / f"{PREFIX}-squashfs-sysupgrade.itb"
        p.rename(self.binary / f"{PREFIX}-usb-sfp-squashfs-sysupgrade.itb")
        with self.assertRaisesRegex(ValueError, "Missing image"):
            self.build()
        self.assertFalse(self.out.exists())

    def test_modified_image_rejected(self):
        (self.binary / f"{PREFIX}-squashfs-sysupgrade.itb").write_bytes(b"corrupted")
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            self.build()

    def test_missing_plugin_rejected(self):
        (self.binary / f"{PREFIX}.manifest").write_text("curl - 1.0\n")
        with self.assertRaisesRegex(ValueError, "Missing image packages"):
            self.build()

    def test_profile_hash_mismatch_rejected(self):
        p = self.binary / "profiles.json"
        data = json.loads(p.read_text())
        data["profiles"][DEVICE]["images"][0]["sha256"] = "0" * 64
        p.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "Profile image mismatch"):
            self.build()

    def test_embedded_device_mismatch_rejected(self):
        self.version.write_text(self.version.read_text().replace(DEVICE, "other"))
        with self.assertRaisesRegex(ValueError, "Embedded device"):
            self.build()

    def test_stale_output_rejected(self):
        self.out.mkdir()
        (self.out / "old.itb").touch()
        with self.assertRaisesRegex(ValueError, "must be empty"):
            self.build()

    def test_packages_can_be_in_base_feed(self):
        base = self.source / "bin/packages/aarch64_cortex-a53/base"
        base.mkdir(parents=True)
        for name in ("luci-app-ponwrt-update", "curl", "jsonfilter"):
            (base / f"{name}-1.0-r1.apk").write_bytes(b"fixture")
        (base / "curl-example-1.0-r1.apk").write_bytes(b"must not collect")
        collect("packages", self.source, self.out, "an7581", DEVICE)
        self.assertEqual(len(list(self.out.glob("*.apk"))), 3)

    def test_missing_package_rejected(self):
        with self.assertRaisesRegex(ValueError, "Expected one"):
            collect("packages", self.source, self.out, "an7581", DEVICE)


class PatchTests(unittest.TestCase):
    def test_patch_once_when_repeated(self):
        src = "return Promise.all(tasks);\nrender([a, b]) { m.readonly = isReadonlyView; }"
        once = patcher.patch(src)
        twice = patcher.patch(once)
        self.assertEqual(twice.count(patcher.BEGIN), 1)
        self.assertEqual(twice, once)
        self.assertEqual(patcher.undo(once), src)
        self.assertNotIn("tasks.push(fs.exec", twice)

    def test_missing_anchor_rejected(self):
        with self.assertRaises(SystemExit):
            patcher.patch("unsupported upstream source")


if __name__ == "__main__":
    unittest.main()
