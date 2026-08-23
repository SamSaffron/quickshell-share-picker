#!/usr/bin/env python3
"""Parse and validate the xdg-desktop-portal-hyprland picker protocol.

This module intentionally has no third-party dependencies. The wrapper uses it to
turn XDPH_WINDOW_SHARING_LIST into JSON for QML and to validate the one line that
is eventually returned to XDPH.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

ID_CLASS = "[HC>]"
CLASS_TITLE = "[HT>]"
TITLE_ADDRESS = "[HE>]"
ENTRY_END = "[HA>]"
MAX_XDPH_HANDLE = (1 << 32) - 1

_SELECTION_RE = re.compile(
    r"\[SELECTION\](?P<flags>r?)/(?P<kind>screen|window|region):(?P<payload>[^\r\n]+)\n\Z"
)
_REGION_RE = re.compile(
    r"(?P<output>[^@\r\n]+)@(?P<x>\d+),(?P<y>\d+),(?P<w>\d+),(?P<h>\d+)\Z"
)


class ProtocolError(ValueError):
    """Raised when picker protocol data is malformed."""


def normalize_hyprland_address(value: str, *, xdph_decimal: bool = False) -> str:
    """Return a lowercase, prefix-free hexadecimal Hyprland address.

    XDPH's mapping field is emitted as an unsigned decimal integer. Quickshell's
    HyprlandToplevel.address is hexadecimal without ``0x``. The explicit mode
    avoids JavaScript's loss of precision for 64-bit addresses.
    """

    text = value.strip().lower()
    if not text:
        return ""

    try:
        if xdph_decimal and not text.startswith("0x"):
            number = int(text, 10)
        elif text.startswith("0x"):
            number = int(text[2:], 16)
        elif any(char in "abcdef" for char in text):
            number = int(text, 16)
        else:
            # This branch is for Hyprland/fixture values, which are hexadecimal.
            number = int(text, 16)
    except ValueError:
        return ""

    if number <= 0 or number >= 1 << 64:
        return ""
    return format(number, "x")


def _next_field(data: str, start: int, marker: str) -> tuple[str, int] | None:
    end = data.find(marker, start)
    if end < 0:
        return None
    return data[start:end], end + len(marker)


def parse_window_list(raw: str | None) -> list[dict[str, Any]]:
    """Parse XDPH_WINDOW_SHARING_LIST, skipping malformed entries safely.

    Parsing resumes after each complete ``[HA>]`` record, so one bad complete
    record does not hide later valid records. An incomplete tail is ignored.
    """

    if not raw:
        return []

    windows: list[dict[str, Any]] = []
    cursor = 0
    source_index = 0

    while cursor < len(raw):
        record_end = raw.find(ENTRY_END, cursor)
        if record_end < 0:
            break
        record = raw[cursor:record_end]
        cursor = record_end + len(ENTRY_END)

        id_field = _next_field(record, 0, ID_CLASS)
        if id_field is None:
            source_index += 1
            continue
        handle, offset = id_field

        class_field = _next_field(record, offset, CLASS_TITLE)
        if class_field is None:
            source_index += 1
            continue
        window_class, offset = class_field

        title_field = _next_field(record, offset, TITLE_ADDRESS)
        if title_field is None:
            source_index += 1
            continue
        title, offset = title_field
        address = record[offset:]

        try:
            numeric_handle = int(handle, 10)
            numeric_address = int(address.strip(), 10)
        except ValueError:
            source_index += 1
            continue

        if not (0 <= numeric_handle <= MAX_XDPH_HANDLE) or not (
            0 <= numeric_address < 1 << 64
        ):
            source_index += 1
            continue
        # A zero mapping means XDPH could not associate this foreign toplevel
        # with a Hyprland window. Keep it selectable, but do not try to preview it.
        normalized = normalize_hyprland_address(address, xdph_decimal=True)

        windows.append(
            {
                "handle": handle,
                "class": window_class,
                "title": title,
                "address": address,
                "normalizedAddress": normalized,
                "sourceIndex": source_index,
            }
        )
        source_index += 1

    return windows


def _normalized_fixture_toplevels(toplevels: list[Any]) -> list[Any]:
    """Normalize fixture addresses with the same function used for portal data."""

    result: list[Any] = []
    for toplevel in toplevels:
        if not isinstance(toplevel, dict):
            result.append(toplevel)
            continue
        normalized = dict(toplevel)
        address = normalized.get("address", "")
        normalized["address"] = normalize_hyprland_address(str(address))
        result.append(normalized)
    return result


def build_session(raw: str | None, fixture: dict[str, Any] | None = None) -> dict[str, Any]:
    fixture = fixture or {}
    window_list = fixture.get("windowList", raw)
    if window_list is not None and not isinstance(window_list, str):
        raise ProtocolError("fixture windowList must be a string")

    mock = fixture.get("mock", {})
    if not isinstance(mock, dict):
        raise ProtocolError("fixture mock must be an object")

    screens = mock.get("screens", [])
    toplevels = mock.get("toplevels", [])
    if not isinstance(screens, list) or not isinstance(toplevels, list):
        raise ProtocolError("fixture screens and toplevels must be arrays")

    return {
        "windows": parse_window_list(window_list),
        "mock": {
            "enabled": bool(fixture),
            "currentWorkspaceId": mock.get("currentWorkspaceId", -1),
            "screens": screens,
            "toplevels": _normalized_fixture_toplevels(toplevels),
        },
    }


def atomic_write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def validate_selection(data: str) -> str:
    """Validate and return one complete XDPH selection line."""

    match = _SELECTION_RE.fullmatch(data)
    if match is None:
        raise ProtocolError("result is not exactly one XDPH selection line")

    kind = match.group("kind")
    payload = match.group("payload")

    if kind == "window":
        if not payload.isascii() or not payload.isdigit():
            raise ProtocolError("window handle is not an unsigned decimal integer")
        handle = int(payload, 10)
        if not 0 <= handle <= MAX_XDPH_HANDLE:
            raise ProtocolError("window handle is outside the XDPH uint32 range")
    elif kind == "screen":
        if not payload or any(ord(char) < 0x20 or ord(char) == 0x7F for char in payload):
            raise ProtocolError("screen name contains a control character")
    else:
        region = _REGION_RE.fullmatch(payload)
        if region is None:
            raise ProtocolError("region payload is malformed")
        if int(region.group("w")) == 0 or int(region.group("h")) == 0:
            raise ProtocolError("region dimensions must be nonzero")

    return data


def _load_fixture(path: str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ProtocolError(f"cannot read fixture: {error}") from error
    if not isinstance(value, dict):
        raise ProtocolError("fixture root must be an object")
    return value


def command_prepare(arguments: argparse.Namespace) -> int:
    fixture = _load_fixture(arguments.fixture)
    session = build_session(os.environ.get("XDPH_WINDOW_SHARING_LIST"), fixture)
    atomic_write_json(Path(arguments.output), session)
    return 0


def command_validate(arguments: argparse.Namespace) -> int:
    try:
        data = Path(arguments.file).read_text(encoding="utf-8")
    except OSError as error:
        raise ProtocolError(f"cannot read result: {error}") from error
    sys.stdout.write(validate_selection(data))
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare = subparsers.add_parser("prepare", help="write picker session JSON")
    prepare.add_argument("--output", required=True)
    prepare.add_argument("--fixture")
    prepare.set_defaults(handler=command_prepare)

    validate = subparsers.add_parser("validate", help="validate and print a picker result")
    validate.add_argument("--file", required=True)
    validate.set_defaults(handler=command_validate)
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        arguments = make_parser().parse_args(argv)
        return arguments.handler(arguments)
    except ProtocolError as error:
        print(f"quickshell-share-picker: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
