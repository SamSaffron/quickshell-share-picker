from __future__ import annotations

import importlib.machinery
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
RELEASE_PATH = REPOSITORY / "scripts/release"
LOADER = importlib.machinery.SourceFileLoader("qsp_release", str(RELEASE_PATH))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
release = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(release)


class ReleaseScriptTests(unittest.TestCase):
    def test_help_is_available(self) -> None:
        result = subprocess.run(
            [str(RELEASE_PATH), "--help"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--auto", result.stdout)
        self.assertIn("--prepare", result.stdout)
        self.assertIn("--publish", result.stdout)
        self.assertIn("--finalize", result.stdout)

    def test_version_parser_is_strict(self) -> None:
        self.assertEqual(release.parse_version("1.2.3"), (1, 2, 3))
        self.assertEqual(release.next_version("patch", "1.2.3"), "1.2.4")
        self.assertEqual(release.next_version("minor", "1.2.3"), "1.3.0")
        self.assertEqual(release.next_version("major", "1.2.3"), "2.0.0")
        for invalid in ("v1.2.3", "1.2", "01.2.3", "1.2.3-rc1"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(release.ReleaseError):
                    release.parse_version(invalid)

    def test_changelog_selects_minor_or_patch_bump(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            changelog = root / "CHANGELOG.md"
            previous_root = release.ROOT
            release.ROOT = root
            try:
                changelog.write_text("## [Unreleased]\n\n### Added\n\n- Feature.\n", encoding="utf-8")
                self.assertEqual(release.suggested_bump(), "minor")
                changelog.write_text("## [Unreleased]\n\n### Fixed\n\n- Bug.\n", encoding="utf-8")
                self.assertEqual(release.suggested_bump(), "patch")
            finally:
                release.ROOT = previous_root

    def test_release_file_updates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "aur").mkdir()
            (root / "README.md").write_text(
                "The current public release is **v0.1.2**.\n"
                "The v0.1.2 recipe is pinned to its asset.\n",
                encoding="utf-8",
            )
            (root / "CHANGELOG.md").write_text(
                "## [Unreleased]\n\n### Added\n\n- Feature.\n\n"
                "[Unreleased]: https://github.com/sam-saffron-jarvis/"
                "quickshell-share-picker/compare/v0.1.2...HEAD\n",
                encoding="utf-8",
            )
            (root / "aur/PKGBUILD").write_text(
                "pkgver=0.1.2\n"
                "pkgrel=2\n"
                "sha256sums=('1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef')\n",
                encoding="utf-8",
            )

            previous_root = release.ROOT
            release.ROOT = root
            try:
                release.update_readme("0.1.2", "0.2.0")
                release.update_changelog("0.1.2", "0.2.0")
                release.update_pkgbuild("0.2.0")
            finally:
                release.ROOT = previous_root

            readme = (root / "README.md").read_text(encoding="utf-8")
            changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
            pkgbuild = (root / "aur/PKGBUILD").read_text(encoding="utf-8")
            self.assertIn("**v0.2.0**", readme)
            self.assertIn("The v0.2.0 recipe", readme)
            self.assertIn("## [0.2.0] - ", changelog)
            self.assertIn("compare/v0.1.2...v0.2.0", changelog)
            self.assertIn("pkgver=0.2.0", pkgbuild)
            self.assertIn("pkgrel=1", pkgbuild)
            self.assertIn(release.ZERO_CHECKSUM, pkgbuild)


if __name__ == "__main__":
    unittest.main()
