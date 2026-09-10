from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
WRAPPER = REPOSITORY / "bin/quickshell-share-picker"
FAKE_QS = REPOSITORY / "tests/helpers/fake-qs"
FAKE_SLURP = REPOSITORY / "tests/helpers/fake-slurp"
WINDOW_LIST = "17[HC>]app[HT>]Title[HE>]255[HA>]"


class WrapperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.runtime = root / "runtime"
        self.state = root / "state"
        self.runtime.mkdir(mode=0o700)
        self.state.mkdir(mode=0o700)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def picker_environment(self, mode: str) -> dict[str, str]:
        environment = os.environ.copy()
        environment.pop("XDPH_PICKER_ALLOW_TOKEN_SELECTION", None)
        environment.update(
            {
                "QSP_FAKE_MODE": mode,
                "QSP_PYTHON_BIN": sys.executable,
                "QSP_QS_BIN": str(FAKE_QS),
                "QSP_SHARE_DIR": str(REPOSITORY / "src"),
                "QSP_SLURP_BIN": str(FAKE_SLURP),
                "QSP_STATE_DIR": str(self.state),
                "QSP_TIMEOUT_SECONDS": "5",
                "XDG_RUNTIME_DIR": str(self.runtime),
                "XDPH_WINDOW_SHARING_LIST": WINDOW_LIST,
            }
        )
        return environment

    def run_picker(
        self, *arguments: str, mode: str = "success", selection: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        environment = self.picker_environment(mode)
        if selection is not None:
            environment["QSP_FAKE_SELECTION"] = selection
        return subprocess.run(
            [str(WRAPPER), *arguments],
            check=False,
            capture_output=True,
            env=environment,
            text=True,
            timeout=10,
        )

    def test_success_stdout_is_exactly_one_selection_line(self) -> None:
        result = self.run_picker(selection="[SELECTION]/window:17")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]/window:17\n")
        self.assertNotIn("fake qs", result.stdout)

    def test_allow_token_requires_explicit_argument(self) -> None:
        without_argument = self.run_picker(mode="allow-token")
        with_argument = self.run_picker("--allow-token", mode="allow-token")
        self.assertEqual(without_argument.stdout, "[SELECTION]/window:17\n")
        self.assertEqual(with_argument.stdout, "[SELECTION]r/window:17\n")

    def test_token_checkbox_requires_explicit_environment_opt_in(self) -> None:
        for value in (None, "", "0", "false", "true", "1"):
            with self.subTest(value=value):
                environment = self.picker_environment("token-visibility")
                if value is not None:
                    environment["XDPH_PICKER_ALLOW_TOKEN_SELECTION"] = value
                result = subprocess.run(
                    [str(WRAPPER)], check=False, capture_output=True,
                    env=environment, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                handle = "18" if value == "1" else "17"
                self.assertEqual(result.stdout, f"[SELECTION]/window:{handle}\n")

    def test_showing_checkbox_does_not_enable_tokens(self) -> None:
        environment = self.picker_environment("allow-token")
        environment["XDPH_PICKER_ALLOW_TOKEN_SELECTION"] = "1"
        environment["QSP_ALLOW_TOKEN"] = "1"  # Internal state cannot override CLI defaults.
        result = subprocess.run(
            [str(WRAPPER)], check=False, capture_output=True,
            env=environment, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]/window:17\n")

    def test_cancel_has_empty_stdout(self) -> None:
        result = self.run_picker(mode="cancel")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")

    def test_malformed_result_is_rejected_without_stdout(self) -> None:
        result = self.run_picker(mode="malformed")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("invalid selection", result.stderr)

    def test_conflicting_picker_actions_are_rejected(self) -> None:
        result = self.run_picker(mode="conflicting-actions")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("conflicting actions", result.stderr)

    def test_quickshell_failure_is_reported_only_on_stderr(self) -> None:
        result = self.run_picker(mode="failure")
        self.assertEqual(result.returncode, 42)
        self.assertEqual(result.stdout, "")
        self.assertIn("status 42", result.stderr)
        self.assertIn("fake qs stdout noise", result.stderr)

    def test_mock_launcher_path(self) -> None:
        result = self.run_picker("--test")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]/window:17\n")

    def test_region_request_runs_slurp_after_picker_and_resolves_coordinates(self) -> None:
        result = self.run_picker("--allow-token", mode="region-request")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]r/region:DP-1@10,20,30,40\n")
        state = json.loads((self.state / "last-region.json").read_text(encoding="utf-8"))
        self.assertEqual(
            state,
            {
                "height": 40,
                "output": "DP-1",
                "outputHeight": 1440,
                "outputWidth": 2560,
                "version": 1,
                "width": 30,
                "x": 10,
                "y": 20,
            },
        )
        self.assertEqual((self.state / "last-region.json").stat().st_mode & 0o777, 0o600)

    def test_repeat_last_region_skips_slurp_and_uses_current_token_choice(self) -> None:
        first = self.run_picker("--allow-token", mode="region-request")
        self.assertEqual(first.returncode, 0, first.stderr)
        repeated = self.run_picker(mode="repeat-region")
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(repeated.stdout, "[SELECTION]/region:DP-1@10,20,30,40\n")

    def test_region_slurp_cancellation_has_empty_stdout(self) -> None:
        environment = self.picker_environment("region-request")
        environment["QSP_FAKE_SLURP_MODE"] = "cancel"
        result = subprocess.run(
            [str(WRAPPER)],
            check=False,
            capture_output=True,
            env=environment,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")

    def test_region_cancellation_reopens_picker_and_can_select_window(self) -> None:
        environment = self.picker_environment("region-recovery")
        environment["QSP_FAKE_SLURP_MODE"] = "cancel"
        result = subprocess.run(
            [str(WRAPPER)],
            check=False,
            capture_output=True,
            env=environment,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]/window:17\n")

    def test_region_recovery_preserves_unchecked_restore_token(self) -> None:
        environment = self.picker_environment("region-recovery-token")
        environment["QSP_FAKE_SLURP_MODE"] = "cancel"
        environment["XDPH_PICKER_ALLOW_TOKEN_SELECTION"] = "1"
        result = subprocess.run(
            [str(WRAPPER), "--allow-token"],
            check=False,
            capture_output=True,
            env=environment,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]/window:17\n")

    def test_region_recovery_preserves_checked_restore_token(self) -> None:
        environment = self.picker_environment("region-recovery-checked")
        environment["QSP_FAKE_SLURP_MODE"] = "cancel"
        environment["XDPH_PICKER_ALLOW_TOKEN_SELECTION"] = "1"
        result = subprocess.run(
            [str(WRAPPER)], check=False, capture_output=True,
            env=environment, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]r/window:17\n")

    def test_live_test_uses_runtime_toplevel_mode_without_portal_windows(self) -> None:
        result = self.run_picker("--test-live", mode="live-test")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]/window:1\n")

    def test_fixture_and_live_test_modes_are_mutually_exclusive(self) -> None:
        result = self.run_picker("--test", "--test-live")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("mutually exclusive", result.stderr)

    def test_source_tree_detection_requires_project_marker(self) -> None:
        environment = self.picker_environment("success")
        environment.pop("QSP_SHARE_DIR")
        result = subprocess.run(
            [str(WRAPPER)],
            check=False,
            capture_output=True,
            env=environment,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[SELECTION]/window:17\n")

    def test_timeout_has_empty_stdout(self) -> None:
        started = time.monotonic()
        result = self.run_picker(mode="wait")
        elapsed = time.monotonic() - started
        self.assertEqual(result.returncode, 124)
        self.assertEqual(result.stdout, "")
        self.assertIn("timed out after 5 seconds", result.stderr)
        self.assertLess(elapsed, 8)

    def test_existing_state_directory_permissions_are_not_changed(self) -> None:
        self.state.chmod(0o755)
        result = self.run_picker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o755)

    def test_signal_cleanup_terminates_child_and_removes_picker_runtime_data(self) -> None:
        process = subprocess.Popen(
            [str(WRAPPER)],
            env=self.picker_environment("wait"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for _ in range(200):
            if list(self.runtime.iterdir()):
                break
            time.sleep(0.01)
        process.terminate()
        stdout, _stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 143)
        self.assertEqual(stdout, "")
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_concurrent_invocations_do_not_share_result_paths(self) -> None:
        selections = [f"[SELECTION]/window:{handle}" for handle in range(40, 48)]
        with ThreadPoolExecutor(max_workers=len(selections)) as executor:
            results = list(
                executor.map(lambda selection: self.run_picker(selection=selection), selections)
            )
        self.assertEqual(
            [result.stdout for result in results],
            [selection + "\n" for selection in selections],
        )
        self.assertTrue(all(result.returncode == 0 for result in results))
        self.assertEqual(list(self.runtime.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
