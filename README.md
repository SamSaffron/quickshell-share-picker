# quickshell-share-picker

A focused screencast source picker for
[xdg-desktop-portal-hyprland](https://github.com/hyprwm/xdg-desktop-portal-hyprland),
implemented as a one-shot [Quickshell](https://quickshell.org/) configuration.

The project follows the practical interaction model of Sam Saffron's
`better-picker` branch: it opens on the **Window** tab, places the window list
beside a selected-window preview, shows workspace labels and application icons,
and keeps **Screen**, **Window**, and **Region** choices in one compact 800×500
centered layer-shell surface. The restrained light palette is intentional and
remains consistent across desktops rather than following a dark or system theme.

The current public release is **v0.1.2**.

## Features

- Screen, window, and `slurp` region selection using XDPH's selector protocol.
- Screen and window tabs pair their compact source lists with a selected-source
  preview refreshed once per second while that tab is active.
- XDPH windows matched to Quickshell Hyprland toplevels by normalized 64-bit
  Hyprland address; the original XDPH window handle is returned unchanged.
- Current workspace first, then workspace ID, preserving source order for ties.
- Labels such as `[3] firefox: Project board` and themed application icons.
- Restore tokens enabled by default, with the optional upstream-compatible user
  choice controlled by `XDPH_PICKER_ALLOW_TOKEN_SELECTION`.
- Width and height persistence under the user's XDG state directory.
- Private per-invocation picker runtime directories, bounded process lifetime,
  atomic result writes, strict output validation, and picker-data cleanup on
  exit/signals.
- Headless parser/protocol/wrapper tests, a real-QML offscreen smoke, and a
  deterministic mock-data launcher.

## Requirements

Runtime:

- Linux with Hyprland and a compatible current `xdg-desktop-portal-hyprland`.
- Quickshell **0.3.1 or newer**, built with Wayland layer-shell, Hyprland,
  toplevel management, and screencopy support.
- Python 3.10 or newer (standard library only).
- GNU coreutils (`timeout`).
- `slurp` for region selection. Screen and window selection still work when
  `slurp` is absent, but the Region action is disabled.
- A working icon theme is recommended.

Development checks additionally use `shellcheck`, `qmllint`, and Quickshell's
real QML runtime. Unit tests do not need Hyprland, Wayland, Qt, or Quickshell;
the runtime smoke uses Qt's offscreen platform and skips locally with an
explicit message only when `qs` is unavailable. CI requires and runs it.

## Architecture

```text
xdg-desktop-portal-hyprland
  │  XDPH_WINDOW_SHARING_LIST + compatible picker options
  ▼
/usr/bin/quickshell-share-picker
  ├─ creates $XDG_RUNTIME_DIR/quickshell-share-picker.XXXXXXXX (0700)
  ├─ protocol.py parses XDPH records into private session.json (0600)
  ├─ starts a bounded, one-shot qs config with stdout/stderr redirected
  │    └─ centered PickerPanelWindow layer-shell surface
  │         └─ PickerWindow.qml
  │              ├─ Quickshell.Hyprland: address/workspace/toplevel association
  │              ├─ ScreencopyView: selected toplevel still preview
  │              └─ Quickshell.screens: output names and geometry
  ├─ launches slurp only after the layer-shell picker has fully exited
  ├─ validates the private result file
  └─ writes exactly one [SELECTION]… line, or nothing on cancellation
```

XDPH supplies records in this form:

```text
HANDLE[HC>]CLASS[HT>]TITLE[HE>]DECIMAL_HYPRLAND_ADDRESS[HA>]
```

The helper converts the decimal mapping address to a lowercase hexadecimal
string without passing through JavaScript numbers, avoiding 64-bit precision
loss. QML compares it with `HyprlandToplevel.address`, uses the associated
Wayland toplevel as the `ScreencopyView.captureSource`, and retains `HANDLE` for
`window:HANDLE` output. The picker also listens to
`Hyprland.toplevels.valuesChanged`, in addition to a bounded startup poll, so a
window gains workspace metadata and a preview when its association arrives
after the dialog opens.

### Preview implementation difference

The BSD XDPH `better-picker` branch starts captures for every listed window and
stores each image eagerly. This Quickshell implementation instead attaches one
non-live `ScreencopyView` only to the currently selected, associated toplevel.
That reduces capture work and retained image data when many windows are listed,
at the cost of the first preview for a newly selected window potentially taking
a moment to appear. Selection protocol output is unchanged.

The accepted output grammar is deliberately narrow:

```text
[SELECTION][r]/screen:OUTPUT
[SELECTION][r]/window:UINT32_HANDLE
[SELECTION][r]/region:OUTPUT@X,Y,WIDTH,HEIGHT
```

`r` means the application may receive a restore token. Cancellation and invalid
results produce no stdout selection.

## Install from a source checkout

```sh
make check
sudo make install
```

The default prefix is `/usr`. Staged/package installs are supported:

```sh
make install DESTDIR="$PWD/pkgroot" PREFIX=/usr
```

Installed files are under:

- `/usr/bin/quickshell-share-picker`
- `/usr/share/quickshell-share-picker/`
- `/usr/share/doc/quickshell-share-picker/`

Uninstall a source installation with:

```sh
sudo make uninstall
```

## Configure XDPH

Add this to `~/.config/hypr/xdph.conf`:

```ini
screencopy {
    custom_picker_binary = /usr/bin/quickshell-share-picker
    allow_token_by_default = true
}
```

Restore-token behavior intentionally matches the BSD `origin/better-picker`
branch exactly. Its `allowTokenByDefault` value is `true`, so selections include
`r` by default and the checkbox starts checked whenever it is shown.
`XDPH_PICKER_ALLOW_TOKEN_SELECTION` controls whether the checkbox is visible:
if the variable is absent, the checkbox is hidden and the picker emits `r`
unconditionally; if it is present (even with an empty value), the checkbox is
shown, starts checked, and the user's final checked state is honored.
`--allow-token` remains accepted for stock XDPH compatibility, although it is
redundant with this true default.

To expose the checkbox, add `XDPH_PICKER_ALLOW_TOKEN_SELECTION=1` to the
xdg-desktop-portal-hyprland service environment. For example, use a systemd user
service override appropriate to the local setup, then restart the service.

Restart the portal after changing its configuration (this interrupts active
portal sessions):

```sh
systemctl --user restart xdg-desktop-portal-hyprland.service
```

Applications should then use their normal “Share screen” action. Do not pipe or
wrap the picker with commands that add stdout text; XDPH expects its selector
line directly.

### Optional environment settings

- `XDPH_PICKER_ALLOW_TOKEN_SELECTION` (presence shows the restore-token choice)
- `XDPH_PICKER_DEFAULT_TAB=screen|window|region` (default: `window`)
- `QSP_TIMEOUT_SECONDS=5..600` (default: `120`)
- `QS_ICON_THEME=<theme>` to override Quickshell's icon theme

`QSP_*` path/binary overrides exist for tests and development. They should not
be needed in an XDPH configuration.

## Arch Linux

Install the runtime dependencies using the package source appropriate for your
system, for example:

```sh
sudo pacman -S python coreutils quickshell
# Optional: slurp for Region; xdg-desktop-portal-hyprland for portal use
```

The `aur/PKGBUILD` is for a versioned release asset, not a moving `-git`
package. Its unversioned `quickshell` dependency is deliberate: Arch's
`quickshell-git` currently provides `quickshell` without a version, so a
versioned dependency would incorrectly reject that compatible provider. The
runtime minimum remains Quickshell 0.3.1. `slurp` and
`xdg-desktop-portal-hyprland` are optional dependencies because screen/window
selection and direct mock use do not require them. The package's `check()` runs
the complete headless suite, including the real-QML offscreen smoke.

The v0.1.2 recipe is pinned to the published release asset and its SHA-256.
Validate future release updates with:

```sh
updpkgsums aur/PKGBUILD
(cd aur && makepkg --printsrcinfo > .SRCINFO)
(cd aur && makepkg -si)
```

A `-git` PKGBUILD is not included because this small release-oriented project
gains no concrete benefit from one.

## Development

```sh
make format          # normalize deterministic text rules
make format-check    # verify formatting and JSON/Python syntax
make lint            # sh -n; shellcheck/qmllint when installed; QML warnings fail
make test            # headless Python unit tests
make smoke           # real QML on Qt's offscreen platform
make check           # formatting + lint + unit tests + runtime smoke
./bin/quickshell-share-picker --test-live # current Hyprland windows and real previews
./scripts/run-mock   # launch the real QML UI with fixture data
make dist            # deterministic release archive in dist/
```

Require optional tools explicitly in automation with `REQUIRE_SHELLCHECK=1`,
`REQUIRE_QMLLINT=1`, or `REQUIRE_QS=1`.

The mock launcher still needs `qs` and a Qt platform on which to display the
window, but it does not query Hyprland or require the XDPH environment. Window
previews intentionally show as unavailable in mock mode.

For local testing on a running Hyprland session, `--test-live` skips XDPH input,
builds the window list from Quickshell's current Hyprland toplevels, and uses
their associated Wayland handles for real still previews. Window selections in
this mode print a synthetic numeric handle for diagnostics only; that output is
not a valid handle to feed back into XDPH. Screen and region interactions use
the current desktop in the same way as a portal-launched picker.

Runtime cleanup is intentionally scoped: the wrapper removes only the private
picker directory it creates and any files inside it. Quickshell owns its global
instance registry/data under the user's XDG directories; this project neither
claims to remove nor attempts to delete that shared state.

## Troubleshooting

### The portal does not open the picker

- Confirm `command -v quickshell-share-picker` and `command -v qs` work in the
  portal service environment.
- Check `systemctl --user status xdg-desktop-portal-hyprland.service` and its
  journal.
- Confirm the XDPH build recognizes `screencopy:custom_picker_binary`.
- Run `./scripts/run-mock` from a checkout to separate QML/display problems from
  portal protocol problems.

### Windows appear but have no preview or workspace label

XDPH and Quickshell must both receive Hyprland's toplevel-to-window mapping.
The picker still returns XDPH's original handle when no Quickshell association
arrives, but it cannot attach a `ScreencopyView` or workspace metadata. Check
that the installed Quickshell build includes Hyprland and screencopy support and
that Hyprland exposes the required protocols.

### Region selection is disabled

Install `slurp` and ensure it is on the portal service's `PATH`, then restart
XDPH. A cancelled `slurp` invocation returns to the picker and emits no
selection.

### XDPH reports an invalid or empty selection

The wrapper rejects extra output, malformed handles, zero-sized regions, and
multiple lines. Quickshell logs never share stdout with the selector protocol;
on abnormal exit, the wrapper sends a short diagnostic tail to stderr instead.

## License and attribution

The original code in this repository is MIT licensed. See [LICENSE](LICENSE).
The XDPH selector protocol, restore-token semantics, and interaction model are
informed by the BSD-3-Clause licensed
[`origin/better-picker` branch at commit `23bda24`](https://github.com/SamSaffron/xdg-desktop-portal-hyprland/tree/23bda24).
See [NOTICE](NOTICE) for the upstream copyright and BSD terms.
