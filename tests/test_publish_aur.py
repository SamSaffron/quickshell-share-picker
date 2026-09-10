from __future__ import annotations

import importlib.machinery
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[1]
PUBLISH_PATH = REPOSITORY / "scripts/publish-aur"
LOADER = importlib.machinery.SourceFileLoader("qsp_publish_aur", str(PUBLISH_PATH))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
publish_aur = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = publish_aur
LOADER.exec_module(publish_aur)


class AurPublisherTests(unittest.TestCase):
    def make_source(self, root: Path, *, checksum: str = "1" * 64) -> None:
        aur = root / "aur"
        aur.mkdir()
        (root / "VERSION").write_text("1.2.3\n", encoding="utf-8")
        (aur / "PKGBUILD").write_text(
            "pkgver=1.2.3\n"
            "pkgrel=4\n"
            f"sha256sums=('{checksum}')\n",
            encoding="utf-8",
        )
        (aur / ".SRCINFO").write_text(
            "pkgbase = quickshell-share-picker\n"
            "\tpkgver = 1.2.3\n"
            "\tpkgrel = 4\n",
            encoding="utf-8",
        )
        (aur / "quickshell-share-picker.install").write_text(
            "post_install() { :; }\n", encoding="utf-8"
        )

    def test_help_is_available(self) -> None:
        result = subprocess.run(
            [str(PUBLISH_PATH), "--help"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("--repo", result.stdout)
        self.assertIn("--yes", result.stdout)

    def test_validates_matching_finalized_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_source(root)
            self.assertEqual(("1.2.3", "4"), publish_aur.validate_metadata(root))

    def test_rejects_unfinalized_or_mismatched_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_source(root, checksum=publish_aur.ZERO_CHECKSUM)
            with self.assertRaisesRegex(publish_aur.AurError, "all-zero"):
                publish_aur.validate_metadata(root)

            self.make_source_in_place(root, version="1.2.4")
            with self.assertRaisesRegex(publish_aur.AurError, "does not match VERSION"):
                publish_aur.validate_metadata(root)

    def make_source_in_place(self, root: Path, *, version: str) -> None:
        (root / "VERSION").write_text(version + "\n", encoding="utf-8")
        pkgbuild = root / "aur/PKGBUILD"
        pkgbuild.write_text(
            pkgbuild.read_text(encoding="utf-8").replace(
                publish_aur.ZERO_CHECKSUM, "1" * 64
            ),
            encoding="utf-8",
        )

    def test_copy_includes_only_owned_aur_files(self) -> None:
        with tempfile.TemporaryDirectory() as source_directory, tempfile.TemporaryDirectory() as destination_directory:
            source = Path(source_directory)
            destination = Path(destination_directory)
            self.make_source(source)
            (source / "aur/quickshell-share-picker-1.2.3.tar.gz").write_bytes(b"artifact")
            (destination / "README").write_text("keep\n", encoding="utf-8")

            publish_aur.copy_aur_files(source, destination)

            self.assertEqual(
                {".SRCINFO", "PKGBUILD", "README", "quickshell-share-picker.install"},
                {path.name for path in destination.iterdir()},
            )
            self.assertEqual("keep\n", (destination / "README").read_text(encoding="utf-8"))

    def test_publish_requires_makepkg_before_any_work(self) -> None:
        with (
            mock.patch.object(
                publish_aur.shutil,
                "which",
                side_effect=lambda command: None if command == "makepkg" else "/usr/bin/git",
            ),
            mock.patch.object(publish_aur, "validate_metadata") as validate_metadata,
        ):
            with self.assertRaisesRegex(publish_aur.AurError, "missing required commands: makepkg"):
                publish_aur.publish(Path("unused"), assume_yes=True)
            validate_metadata.assert_not_called()

    def test_publishes_initial_and_idempotent_updates_to_git(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            remote = root / "remote.git"
            repository = root / "aur-clone"
            source.mkdir()
            self.make_source(source)
            subprocess.run(["git", "init", "--bare", str(remote)], check=True, capture_output=True)
            subprocess.run(
                ["git", "clone", str(remote), str(repository)], check=True, capture_output=True
            )
            subprocess.run(
                ["git", "config", "user.name", "AUR Test"], cwd=repository, check=True
            )
            subprocess.run(
                ["git", "config", "user.email", "aur@example.invalid"],
                cwd=repository,
                check=True,
            )

            with (
                mock.patch.object(publish_aur, "ROOT", source),
                # Package verification is mocked below; its makepkg prerequisite
                # must not leak into this real-Git integration test on non-Arch hosts.
                mock.patch.object(publish_aur, "require_commands") as require_commands,
                mock.patch.object(publish_aur, "validate_remote_url"),
                mock.patch.object(publish_aur, "verify_package_sources"),
                mock.patch.object(publish_aur, "ensure_source_metadata_committed"),
                mock.patch.object(publish_aur, "confirm") as confirmation,
            ):
                publish_aur.publish(repository, assume_yes=True)
                publish_aur.publish(repository, assume_yes=True)
                self.assertEqual(2, confirmation.call_count)
                self.assertEqual(
                    [mock.call("git", "makepkg"), mock.call("git", "makepkg")],
                    require_commands.call_args_list,
                )

            remote_files = subprocess.run(
                ["git", "--git-dir", str(remote), "ls-tree", "--name-only", "master"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.splitlines()
            self.assertEqual(sorted(publish_aur.AUR_FILES), sorted(remote_files))
            subject = subprocess.run(
                ["git", "--git-dir", str(remote), "log", "-1", "--format=%s", "master"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            self.assertEqual(
                "Initial import: quickshell-share-picker 1.2.3-4", subject
            )

    def test_accepts_only_the_project_aur_remote(self) -> None:
        for valid in (
            "ssh://aur@aur.archlinux.org/quickshell-share-picker.git",
            "aur@aur.archlinux.org:quickshell-share-picker.git",
        ):
            publish_aur.validate_remote_url(valid)
        with self.assertRaises(publish_aur.AurError):
            publish_aur.validate_remote_url(
                "ssh://aur@aur.archlinux.org/a-different-package.git"
            )


if __name__ == "__main__":
    unittest.main()
