"""Archive safety and packaging checks using isolated fixtures."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ReleaseToolsTests(unittest.TestCase):
    def check_archive(self, extra=(), duplicates=False):
        with tempfile.TemporaryDirectory() as temporary:
            archive = pathlib.Path(temporary) / "previous.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("CopyShelf.app/Contents/Info.plist", b"fixture")
                bundle.writestr("CopyShelf.app/Contents/MacOS/CopyShelf", b"fixture")
                for name, content in extra:
                    bundle.writestr(name, content)
                if duplicates:
                    bundle.writestr("CopyShelf.app/Contents/./Info.plist", b"duplicate")
            return subprocess.run([sys.executable, str(ROOT / "Scripts/check-release-archive.py"), temporary],
                                  capture_output=True, text=True)

    def test_normal_app_archive_is_accepted(self):
        self.assertEqual(self.check_archive().returncode, 0)

    def test_paths_outside_the_app_are_rejected(self):
        for name in ["../outside", "/outside", "CopyShelf.app/../../outside", "Other.app/item", r"CopyShelf.app\outside"]:
            with self.subTest(name=name):
                self.assertNotEqual(self.check_archive([(name, b"fixture")]).returncode, 0)

    def test_duplicate_normalized_paths_are_rejected(self):
        self.assertNotEqual(self.check_archive(duplicates=True).returncode, 0)

    def test_symlinks_are_rejected(self):
        entry = zipfile.ZipInfo("CopyShelf.app/link")
        entry.create_system = 3
        entry.external_attr = 0o120777 << 16
        self.assertNotEqual(self.check_archive([(entry, b"../../outside")]).returncode, 0)

    def package_fixture(self, app_version=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        for name in ["Scripts/package-release.sh", "Scripts/check-release-archive.py", "Resources/Info.plist", "docs/INSTALL.txt"]:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        if app_version is not None:
            app = root / "dist/build/CopyShelf.app/Contents"
            app.mkdir(parents=True)
            with (ROOT / "Resources/Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            info["CFBundleShortVersionString"] = app_version
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump(info, stream)
        return root

    @unittest.skipUnless(sys.platform == "darwin", "macOS packaging tools")
    def test_missing_app_is_not_published(self):
        root = self.package_fixture()
        result = subprocess.run(["bash", str(root / "Scripts/package-release.sh")], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("build-app.sh", result.stderr)
        self.assertFalse((root / "dist").exists())

    @unittest.skipUnless(sys.platform == "darwin", "macOS packaging tools")
    def test_stale_app_version_is_not_published(self):
        root = self.package_fixture(app_version="0.0.0")
        result = subprocess.run(["bash", str(root / "Scripts/package-release.sh")], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("version differs", result.stderr)
        self.assertFalse(list((root / "dist").glob("*.zip")))


if __name__ == "__main__":
    unittest.main()
