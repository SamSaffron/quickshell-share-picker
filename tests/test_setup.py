#!/usr/bin/env python3
"""Tests for the user-scoped XDPH setup helper."""

from __future__ import annotations

import argparse
import contextlib
import importlib.machinery
import importlib.util
import io
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/quickshell-share-picker-setup"
LOADER = importlib.machinery.SourceFileLoader("picker_setup", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
setup = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = setup
LOADER.exec_module(setup)


class SetupContentTests(unittest.TestCase):
    def test_fresh_install_is_idempotent_and_uninstalls_cleanly(self) -> None:
        original = "misc {\n    value = true\n}\n"
        installed = setup.install_content(original)

        self.assertEqual(installed, setup.install_content(installed))
        self.assertIn(setup.BEGIN_MARKER, installed)
        self.assertEqual(setup.DEFAULT_PICKER, setup.effective_picker(installed))
        self.assertEqual(original, setup.uninstall_content(installed))

    def test_empty_config_round_trip(self) -> None:
        installed = setup.install_content("")
        self.assertEqual(setup.render_block(), installed)
        self.assertEqual("", setup.uninstall_content(installed))

    def test_replaces_drifted_managed_block(self) -> None:
        drifted = setup.render_block("/tmp/old-picker")
        updated = setup.install_content(drifted)
        self.assertEqual(setup.render_block(), updated)

    def test_preserves_crlf_newlines(self) -> None:
        original = "misc {\r\n    value = true\r\n}\r\n"
        installed = setup.install_content(original)
        self.assertNotIn("\n", installed.replace("\r\n", ""))
        self.assertEqual(original, setup.uninstall_content(installed))

    def test_config_without_trailing_newline_stays_valid(self) -> None:
        installed = setup.install_content("misc {\n}")
        self.assertIn("}\n" + setup.BEGIN_MARKER, installed)
        self.assertEqual("misc {\n}\n", setup.uninstall_content(installed))

    def test_malformed_markers_are_rejected(self) -> None:
        with self.assertRaises(setup.SetupError):
            setup.install_content(setup.BEGIN_MARKER + "\n")
        duplicate = setup.render_block() + setup.render_block()
        with self.assertRaises(setup.SetupError):
            setup.uninstall_content(duplicate)

    def test_force_moves_managed_block_after_later_override(self) -> None:
        text = (
            setup.render_block()
            + "screencopy {\n"
            + "    custom_picker_binary = /tmp/foreign\n"
            + "    allow_token_by_default = false\n"
            + "}\n"
        )
        self.assertFalse(setup.effective_allow_token(text))
        updated = setup.install_content(text)
        self.assertEqual(setup.DEFAULT_PICKER, setup.effective_picker(updated))
        self.assertTrue(setup.effective_allow_token(updated))
        self.assertTrue(updated.endswith(setup.render_block()))

    def test_finds_picker_assignments_and_ignores_comments(self) -> None:
        text = (
            "# custom_picker_binary = /commented\n"
            "screencopy {\n"
            "  custom_picker_binary = '/tmp/other' # explanation\n"
            "}\n"
            + setup.render_block()
        )
        self.assertEqual(["/tmp/other"], setup.picker_assignments(text))
        self.assertEqual(setup.DEFAULT_PICKER, setup.effective_picker(text))


class SetupFilesystemTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.config = self.root / "config/hypr/xdph.conf"
        self.picker = self.root / "quickshell-share-picker"
        self.picker.write_text("#!/bin/sh\n", encoding="utf-8")
        self.picker.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def arguments(self, **overrides: object) -> argparse.Namespace:
        values: dict[str, object] = {
            "config": self.config,
            "picker": str(self.picker),
            "force": False,
            "yes": True,
            "restart": False,
            "no_restart": True,
            "dry_run": False,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    @mock.patch.object(setup.os, "geteuid", return_value=1000)
    def test_install_creates_backup_and_preserves_mode(self, _geteuid: mock.Mock) -> None:
        self.config.parent.mkdir(parents=True)
        original = "misc {\n    value = true\n}\n"
        self.config.write_text(original, encoding="utf-8")
        self.config.chmod(0o600)

        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, setup.install(self.arguments()))

        self.assertEqual(original, Path(str(self.config) + ".bak").read_text(encoding="utf-8"))
        self.assertEqual(0o600, stat.S_IMODE(self.config.stat().st_mode))
        self.assertIn(setup.BEGIN_MARKER, self.config.read_text(encoding="utf-8"))

    @mock.patch.object(setup.os, "geteuid", return_value=1000)
    def test_install_preserves_symlink(self, _geteuid: mock.Mock) -> None:
        target = self.root / "actual-xdph.conf"
        target.write_text("misc {}\n", encoding="utf-8")
        self.config.parent.mkdir(parents=True)
        self.config.symlink_to(target)

        with contextlib.redirect_stdout(io.StringIO()):
            setup.install(self.arguments())

        self.assertTrue(self.config.is_symlink())
        self.assertIn(setup.BEGIN_MARKER, target.read_text(encoding="utf-8"))
        self.assertEqual("misc {}\n", Path(str(self.config) + ".bak").read_text(encoding="utf-8"))

    @mock.patch.object(setup.os, "geteuid", return_value=1000)
    def test_foreign_picker_requires_force(self, _geteuid: mock.Mock) -> None:
        self.config.parent.mkdir(parents=True)
        self.config.write_text(
            "screencopy {\n    custom_picker_binary = /tmp/foreign\n}\n",
            encoding="utf-8",
        )
        with self.assertRaises(setup.SetupError):
            setup.install(self.arguments())
        self.assertNotIn(setup.BEGIN_MARKER, self.config.read_text(encoding="utf-8"))

        with contextlib.redirect_stdout(io.StringIO()):
            setup.install(self.arguments(force=True))
        self.assertEqual(str(self.picker), setup.effective_picker(self.config.read_text(encoding="utf-8")))

    @mock.patch.object(setup.os, "geteuid", return_value=1000)
    def test_dry_run_does_not_write_or_back_up(self, _geteuid: mock.Mock) -> None:
        self.config.parent.mkdir(parents=True)
        self.config.write_text("misc {}\n", encoding="utf-8")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            setup.install(self.arguments(dry_run=True))
        self.assertIn(setup.BEGIN_MARKER, output.getvalue())
        self.assertEqual("misc {}\n", self.config.read_text(encoding="utf-8"))
        self.assertFalse(Path(str(self.config) + ".bak").exists())

    def test_check_exit_codes(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(1, setup.check_configuration(self.config, str(self.picker)))
        self.config.parent.mkdir(parents=True)
        self.config.write_text(setup.render_block(str(self.picker)), encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, setup.check_configuration(self.config, str(self.picker)))
        self.config.write_text(
            setup.render_block(str(self.picker))
            + "screencopy {\n    allow_token_by_default = false\n}\n",
            encoding="utf-8",
        )
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(1, setup.check_configuration(self.config, str(self.picker)))
        self.config.write_text(setup.BEGIN_MARKER + "\n", encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(2, setup.check_configuration(self.config, str(self.picker)))

    def test_root_mutations_are_rejected(self) -> None:
        with mock.patch.object(setup.os, "geteuid", return_value=0):
            with self.assertRaises(setup.SetupError):
                setup.install(self.arguments())
            with self.assertRaises(setup.SetupError):
                setup.uninstall(self.arguments())

    def test_default_path_honors_xdg_config_home(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.root)}, clear=True):
            self.assertEqual(self.root / "hypr/xdph.conf", setup.default_config_path())


if __name__ == "__main__":
    unittest.main()
