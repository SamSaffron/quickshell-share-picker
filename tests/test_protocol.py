from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
PROTOCOL_PATH = REPOSITORY / "src/lib/protocol.py"
SPEC = importlib.util.spec_from_file_location("qsp_protocol", PROTOCOL_PATH)
assert SPEC is not None and SPEC.loader is not None
protocol = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(protocol)


class WindowListTests(unittest.TestCase):
    def test_fixture_cases(self) -> None:
        cases = json.loads(
            (REPOSITORY / "tests/fixtures/parser-cases.json").read_text(encoding="utf-8")
        )
        for case in cases:
            with self.subTest(case=case["name"]):
                self.assertEqual(protocol.parse_window_list(case["raw"]), case["expected"])

    def test_absent_value_is_empty(self) -> None:
        self.assertEqual(protocol.parse_window_list(None), [])
        self.assertEqual(protocol.parse_window_list(""), [])

    def test_xdph_decimal_and_hyprland_hex_normalize_identically(self) -> None:
        self.assertEqual(
            protocol.normalize_hyprland_address("11256099", xdph_decimal=True),
            protocol.normalize_hyprland_address("0x00ABC123"),
        )

    def test_address_conversion_does_not_lose_64_bit_precision(self) -> None:
        self.assertEqual(
            protocol.normalize_hyprland_address(
                "18446744073709551614", xdph_decimal=True
            ),
            "fffffffffffffffe",
        )
    def test_fixture_toplevels_use_production_address_normalization(self) -> None:
        session = protocol.build_session(
            None,
            {
                "windowList": "",
                "mock": {
                    "screens": [],
                    "toplevels": [
                        {"address": "0x00ABC123"},
                        {"address": "00123456"},
                    ],
                },
            },
        )
        self.assertEqual(
            [entry["address"] for entry in session["mock"]["toplevels"]],
            ["abc123", "123456"],
        )


class RegionTests(unittest.TestCase):
    REQUEST = {
        "allowRestore": True,
        "screens": [
            {"height": 1080, "name": "HDMI-A-1", "width": 1920, "x": -1920, "y": 180}
        ],
    }

    def test_resolve_region_makes_coordinates_output_relative(self) -> None:
        self.assertEqual(
            protocol.resolve_region(self.REQUEST, "HDMI-A-1 -1900 200 300 400\n"),
            "[SELECTION]r/region:HDMI-A-1@20,20,300,400\n",
        )

    def test_resolve_region_rejects_selection_outside_output(self) -> None:
        with self.assertRaises(protocol.ProtocolError):
            protocol.resolve_region(self.REQUEST, "HDMI-A-1 -1930 200 300 400\n")


class SelectionTests(unittest.TestCase):
    def test_protocol_line_fixtures(self) -> None:
        cases = json.loads(
            (REPOSITORY / "tests/fixtures/protocol-lines.json").read_text(
                encoding="utf-8"
            )
        )
        for line in cases["valid"]:
            with self.subTest(valid=line):
                self.assertEqual(protocol.validate_selection(line), line)
        for line in cases["invalid"]:
            with self.subTest(invalid=line):
                with self.assertRaises(protocol.ProtocolError):
                    protocol.validate_selection(line)

    def test_prepare_cli_reads_environment_and_writes_private_json(self) -> None:
        raw = "31[HC>]app[HT>]A title[HE>]255[HA>]"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "session.json"
            environment = os.environ.copy()
            environment["XDPH_WINDOW_SHARING_LIST"] = raw
            result = subprocess.run(
                [
                    sys.executable,
                    str(PROTOCOL_PATH),
                    "prepare",
                    "--output",
                    str(output),
                ],
                check=False,
                capture_output=True,
                env=environment,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            session = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(session["windows"][0]["handle"], "31")
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_validate_cli_emits_only_the_selection(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result_file = Path(directory) / "result"
            result_file.write_text("[SELECTION]r/screen:DP-1\n", encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(PROTOCOL_PATH),
                    "validate",
                    "--file",
                    str(result_file),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "[SELECTION]r/screen:DP-1\n")


if __name__ == "__main__":
    unittest.main()
