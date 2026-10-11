import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.4.1"
TAG = f"v{VERSION}"
INSTALLER = f"codex-usage-sidebar-{TAG}-windows-x64-setup.exe"
CHECKSUMS = "WINDOWS-V041-SHA256SUMS.txt"
RELEASE_NOTES = "docs/releases/windows-v0.4.1.md"


class WindowsV041ReleaseDocsTests(unittest.TestCase):
    def test_public_windows_installation_docs_target_v041(self) -> None:
        for relative in ("README.md", "README.zh-CN.md"):
            text = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn(f"releases/tag/{TAG}", text, relative)
            self.assertIn(INSTALLER, text, relative)
            self.assertIn(CHECKSUMS, text, relative)
            self.assertIn(RELEASE_NOTES, text, relative)

    def test_release_catalog_targets_v041_without_changing_macos(self) -> None:
        catalog = json.loads((ROOT / "releases/platform-release-catalog.json").read_text(encoding="utf-8"))
        windows = catalog["published"]["windows"]
        self.assertEqual(windows["version"], VERSION)
        self.assertEqual(windows["tag"], TAG)
        self.assertIs(windows["legacyTag"], False)
        self.assertEqual(windows["assets"]["installer"], INSTALLER)
        self.assertEqual(windows["assets"]["checksums"], CHECKSUMS)
        self.assertEqual(windows["releaseNotes"], RELEASE_NOTES)
        self.assertTrue((ROOT / RELEASE_NOTES).is_file())
        self.assertEqual(catalog["published"]["macos"]["version"], "0.4.0")


if __name__ == "__main__":
    unittest.main()
