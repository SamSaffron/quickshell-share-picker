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
_SLURP_RE = re.compile(
    r"(?P<output>\S+)\s+(?P<x>-?\d+)\s+(?P<y>-?\d+)\s+"
    r"(?P<w>\d+)\s+(?P<h>\d+)\s*\Z"
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


def _region_screens(request: Any) -> tuple[bool, dict[str, tuple[int, int, int, int]]]:
    if not isinstance(request, dict) or not isinstance(request.get("allowRestore"), bool):
        raise ProtocolError("region request is malformed")
    screens = request.get("screens")
    if not isinstance(screens, list):
        raise ProtocolError("region request screens must be an array")

    valid_screens: dict[str, tuple[int, int, int, int]] = {}
    for screen in screens:
        if not isinstance(screen, dict):
            raise ProtocolError("region request screen is malformed")
        name = screen.get("name")
        dimensions = [screen.get(key) for key in ("x", "y", "width", "height")]
        if (
            not isinstance(name, str)
            or not name
            or "@" in name
            or any(ord(char) < 0x20 or ord(char) == 0x7F for char in name)
            or any(not isinstance(value, int) or isinstance(value, bool) for value in dimensions)
            or dimensions[2] <= 0
            or dimensions[3] <= 0
            or name in valid_screens
        ):
            raise ProtocolError("region request screen is malformed")
        valid_screens[name] = tuple(dimensions)
    return request["allowRestore"], valid_screens


def validate_region_state(value: Any) -> dict[str, Any]:
    fields = {"version", "output", "outputWidth", "outputHeight", "x", "y", "width", "height"}
    if not isinstance(value, dict) or set(value) != fields or value.get("version") != 1:
        raise ProtocolError("saved region is malformed")
    output = value.get("output")
    numbers = [value.get(key) for key in ("outputWidth", "outputHeight", "x", "y", "width", "height")]
    if (
        not isinstance(output, str)
        or not output
        or "@" in output
        or any(ord(char) < 0x20 or ord(char) == 0x7F for char in output)
        or any(not isinstance(number, int) or isinstance(number, bool) for number in numbers)
    ):
        raise ProtocolError("saved region is malformed")
    output_width, output_height, x, y, width, height = numbers
    if (
        output_width <= 0
        or output_height <= 0
        or x < 0
        or y < 0
        or width <= 0
        or height <= 0
        or x + width > output_width
        or y + height > output_height
    ):
        raise ProtocolError("saved region is outside its output")
    return {key: value[key] for key in sorted(fields)}


def region_state_from_selection(request: Any, selection: str) -> dict[str, Any]:
    _allow_restore, screens = _region_screens(request)
    line = validate_selection(selection)
    match = _SELECTION_RE.fullmatch(line)
    if match is None or match.group("kind") != "region":
        raise ProtocolError("selection is not a region")
    region = _REGION_RE.fullmatch(match.group("payload"))
    if region is None or region.group("output") not in screens:
        raise ProtocolError("region output is unknown")
    output = region.group("output")
    _screen_x, _screen_y, output_width, output_height = screens[output]
    return validate_region_state(
        {
            "version": 1,
            "output": output,
            "outputWidth": output_width,
            "outputHeight": output_height,
            "x": int(region.group("x")),
            "y": int(region.group("y")),
            "width": int(region.group("w")),
            "height": int(region.group("h")),
        }
    )


def repeat_region(request: Any) -> str:
    allow_restore, screens = _region_screens(request)
    state = validate_region_state(request.get("region"))
    output = state["output"]
    if output not in screens:
        raise ProtocolError("saved region output is unavailable")
    _screen_x, _screen_y, screen_width, screen_height = screens[output]
    if state["outputWidth"] != screen_width or state["outputHeight"] != screen_height:
        raise ProtocolError("saved region output geometry changed")
    flags = "r" if allow_restore else ""
    return validate_selection(
        f"[SELECTION]{flags}/region:{output}@{state['x']},{state['y']},{state['width']},{state['height']}\n"
    )


def resolve_region(request: Any, selection: str) -> str:
    """Convert one slurp selection using private screen geometry from QML."""

    allow_restore, valid_screens = _region_screens(request)

    match = _SLURP_RE.fullmatch(selection)
    if match is None:
        raise ProtocolError("slurp returned an unrecognized region")
    output = match.group("output")
    if output not in valid_screens:
        raise ProtocolError("slurp selected an unknown output")

    screen_x, screen_y, screen_width, screen_height = valid_screens[output]
    x = int(match.group("x")) - screen_x
    y = int(match.group("y")) - screen_y
    width = int(match.group("w"))
    height = int(match.group("h"))
    if (
        x < 0
        or y < 0
        or width <= 0
        or height <= 0
        or x + width > screen_width
        or y + height > screen_height
    ):
        raise ProtocolError("slurp selection is outside its output")

    flags = "r" if allow_restore else ""
    return f"[SELECTION]{flags}/region:{output}@{x},{y},{width},{height}\n"


def _load_json_file(path: str, description: str) -> Any:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ProtocolError(f"cannot read {description}: {error}") from error


def _load_fixture(path: str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    value = _load_json_file(path, "fixture")
    if not isinstance(value, dict):
        raise ProtocolError("fixture root must be an object")
    return value


def _load_region_state(path: str | None) -> dict[str, Any] | None:
    if not path:
        return None
    state_path = Path(path)
    try:
        if state_path.is_symlink() or not state_path.is_file() or state_path.stat().st_size > 4096:
            return None
        return validate_region_state(_load_json_file(path, "saved region"))
    except (OSError, ProtocolError):
        return None


def command_prepare(arguments: argparse.Namespace) -> int:
    fixture = _load_fixture(arguments.fixture)
    session = build_session(os.environ.get("XDPH_WINDOW_SHARING_LIST"), fixture)
    session["lastRegion"] = _load_region_state(arguments.region_state)
    atomic_write_json(Path(arguments.output), session)
    return 0


def command_validate(arguments: argparse.Namespace) -> int:
    try:
        data = Path(arguments.file).read_text(encoding="utf-8")
    except OSError as error:
        raise ProtocolError(f"cannot read result: {error}") from error
    sys.stdout.write(validate_selection(data))
    return 0


def command_region(arguments: argparse.Namespace) -> int:
    request = _load_json_file(arguments.request, "region request")
    try:
        selection = Path(arguments.selection).read_text(encoding="utf-8")
    except OSError as error:
        raise ProtocolError(f"cannot read slurp selection: {error}") from error
    sys.stdout.write(resolve_region(request, selection))
    return 0


def command_repeat_region(arguments: argparse.Namespace) -> int:
    request = _load_json_file(arguments.request, "repeat-region request")
    sys.stdout.write(repeat_region(request))
    return 0


def command_save_region(arguments: argparse.Namespace) -> int:
    request = _load_json_file(arguments.request, "region request")
    try:
        selection = Path(arguments.selection).read_text(encoding="utf-8")
    except OSError as error:
        raise ProtocolError(f"cannot read region selection: {error}") from error
    atomic_write_json(Path(arguments.state), region_state_from_selection(request, selection))
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare = subparsers.add_parser("prepare", help="write picker session JSON")
    prepare.add_argument("--output", required=True)
    prepare.add_argument("--fixture")
    prepare.add_argument("--region-state")
    prepare.set_defaults(handler=command_prepare)

    validate = subparsers.add_parser("validate", help="validate and print a picker result")
    validate.add_argument("--file", required=True)
    validate.set_defaults(handler=command_validate)

    region = subparsers.add_parser("region", help="resolve a private slurp region request")
    region.add_argument("--request", required=True)
    region.add_argument("--selection", required=True)
    region.set_defaults(handler=command_region)

    repeat_region_parser = subparsers.add_parser("repeat-region", help="resolve a saved region request")
    repeat_region_parser.add_argument("--request", required=True)
    repeat_region_parser.set_defaults(handler=command_repeat_region)

    save_region = subparsers.add_parser("save-region", help="persist a validated region selection")
    save_region.add_argument("--request", required=True)
    save_region.add_argument("--selection", required=True)
    save_region.add_argument("--state", required=True)
    save_region.set_defaults(handler=command_save_region)
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
