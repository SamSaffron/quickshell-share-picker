# Installation and configuration

[Back to the README](../README.md) · [Architecture](ARCHITECTURE.md) · [Development](DEVELOPMENT.md)

This is the full reference. For the shortest Arch install path, start with the README.

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
- `/usr/bin/quickshell-share-picker-setup`
- `/usr/share/quickshell-share-picker/`
- `/usr/share/doc/quickshell-share-picker/`

Uninstall a source installation with:

```sh
sudo make uninstall
```

## Configure XDPH

Configure the portal as your desktop user (not with `sudo`):

```sh
quickshell-share-picker-setup install
```

The helper appends a clearly marked block to
`${XDG_CONFIG_HOME:-$HOME/.config}/hypr/xdph.conf`, preserving all unrelated
settings. It is safe to run repeatedly, writes atomically, and retains the
original file as `xdph.conf.bak` before its first change. If another picker is
already configured outside the managed block, setup refuses to override it
unless you review the conflict and rerun with `--force`.

An interactive install offers to restart XDPH. Restarting interrupts active
portal sessions, so non-interactive use leaves that step to you unless
`--restart` is explicit:

```sh
quickshell-share-picker-setup check
quickshell-share-picker-setup install --restart
quickshell-share-picker-setup uninstall
```

`check` exits with status 0 when the managed configuration and installed picker
are ready, 1 when setup is needed, and 2 for an invalid or unreadable config.
Use `print` to inspect the managed block and `install --dry-run` to preview the
complete resulting file. `uninstall` removes only the managed block; it never
restores the backup over later user changes.

For manual configuration, add this equivalent block to `~/.config/hypr/xdph.conf`:

```ini
screencopy {
    custom_picker_binary = /usr/bin/quickshell-share-picker
    allow_token_by_default = false
}
```

### Optional restore-token support

Most users can leave this off. By default there is **no restore-token checkbox**,
and screen, window, region and repeated-region selections do **not** include
XDPH's `r` flag. This does not remove the normal source selection or sharing flow.

To expose an optional, **initially unchecked** checkbox, set
`XDPH_PICKER_ALLOW_TOKEN_SELECTION=1` in the **portal service environment**, then
restart the portal when it is safe to interrupt active sharing. Only the literal
value `1` enables the checkbox; unset, empty and `0` all leave it hidden. Showing
the checkbox is not consent: the user must check it to allow a restore token.
The choice survives a cancelled region-selection attempt, but is not saved as a
preference for later picker invocations.

Advanced callers may explicitly pass `--allow-token` to allow a token without
showing the checkbox. If combined with the opt-in checkbox, it starts checked
and can be unchecked. XDPH supplies that argument when its
`allow_token_by_default` setting is true; the managed setup now writes **false**.
This preserves the stock selector interface without silently enabling tokens.

**Upgrading an existing installation:** rerun the setup helper as your desktop
user to replace the old managed `allow_token_by_default = true` setting:

```sh
quickshell-share-picker-setup install
quickshell-share-picker-setup check
```

The existing config backup and unrelated settings are preserved. The helper's
`check` reports setup needed while the effective setting is still true. Until
you update that older configuration, XDPH can continue passing `--allow-token`.
Previously, merely defining `XDPH_PICKER_ALLOW_TOKEN_SELECTION` showed the choice;
it now requires `=1`. Remove an existing `XDPH_PICKER_ALLOW_TOKEN_SELECTION=1`
service setting if you want the default checkbox-free dialog again. No user
configuration is changed by a root package install.

After changing the configuration manually, restart the portal (this interrupts
active portal sessions):

```sh
systemctl --user restart xdg-desktop-portal-hyprland.service
```

Applications should then use their normal “Share screen” action. Do not pipe or
wrap the picker with commands that add stdout text; XDPH expects its selector
line directly.

### Optional environment settings

- `XDPH_PICKER_ALLOW_TOKEN_SELECTION=1` (opt in to the unchecked restore-token choice; hidden by default)
- `XDPH_PICKER_DEFAULT_TAB=screen|window|region` (default: `window`)
- `QSP_TIMEOUT_SECONDS=5..600` (default: `120`)
- `QSP_THEME=light|dark` (default: `light`)
- `QS_ICON_THEME=<theme>` to override Quickshell's icon theme

`QSP_*` path/binary overrides exist for tests and development. They should not
be needed in an XDPH configuration.

## Arch Linux

Install the runtime dependencies using the package source appropriate for your
system, for example:

```sh
sudo pacman -S python coreutils quickshell slurp xdg-desktop-portal-hyprland
```

The `aur/PKGBUILD` is for a versioned release asset, not a moving `-git`
package. Its unversioned `quickshell` dependency is deliberate: Arch's
`quickshell-git` currently provides `quickshell` without a version, so a
versioned dependency would incorrectly reject that compatible provider. The
runtime minimum remains Quickshell 0.3.1. `slurp` and
`xdg-desktop-portal-hyprland` are required package dependencies: XDPH provides
the portal integration this picker targets, and `slurp` keeps the primary Region
action functional after a normal installation. The package's `check()` runs
the complete headless suite, including the real-QML offscreen smoke.

### Build and install the published Arch package

The bundled recipe downloads the versioned release archive, builds a native Arch
package, runs its checks, and installs it through pacman:

```sh
sudo pacman -S --needed base-devel
cd aur
makepkg -si
```

Pacman prints the one remaining user-scoped setup command after installation:

```sh
quickshell-share-picker-setup install
```

The package does not edit a home directory from its root package transaction.
Run the command as the Hyprland desktop user, without `sudo`.

Run `makepkg` as your normal user, not as root. Its `-s` option asks pacman to
install missing package dependencies, and `-i` installs the completed package.
The package explicitly uses Qt 6's `/usr/lib/qt6/bin/qmllint`; this avoids the
legacy Qt 5 `/usr/bin/qmllint`, which does not support the strict warning flags.
The resulting `*.pkg.tar.zst` can later be removed normally with:

```sh
sudo pacman -Rns quickshell-share-picker
```

### Build and install a custom package from this checkout

To package local modifications instead of the published release, first create the
deterministic source archive, then build with a temporary copy of the PKGBUILD
pointed at that local archive:

```sh
sudo pacman -S --needed base-devel shellcheck qt6-declarative

make check
make dist

version=$(cat VERSION)
archive="$PWD/dist/quickshell-share-picker-$version.tar.gz"
build_dir=$(mktemp -d)
cp aur/PKGBUILD "$build_dir/PKGBUILD"
cp "$archive" "$build_dir/"
checksum=$(sha256sum "$archive" | cut -d' ' -f1)

sed -i \
  -e 's|^pkgrel=.*|pkgrel=99|' \
  -e 's|^source=.*|source=("$pkgname-$pkgver.tar.gz")|' \
  -e "s|^sha256sums=.*|sha256sums=('$checksum')|" \
  "$build_dir/PKGBUILD"

(cd "$build_dir" && makepkg -si)
rm -rf "$build_dir"
```

This leaves the repository's release-oriented `aur/PKGBUILD` unchanged. Pacman
tracks the custom build as `quickshell-share-picker`, so later upgrades and
removal use normal package-management commands. Do not commit the generated
`dist/` archive or `*.pkg.tar.zst` package.

The bundled recipe is pinned to the published release asset and its SHA-256.
Maintainers update, verify, publish, and finalize future versions with the release
automation documented below and in [CONTRIBUTING.md](../CONTRIBUTING.md).

A `-git` PKGBUILD is not included because this small release-oriented project
gains no concrete benefit from one.

## Picker behavior

- Window is the initial tab unless `XDPH_PICKER_DEFAULT_TAB` overrides it. The current workspace comes first; ordering stays stable once you begin interacting.
- Screen and window previews refresh once per second for the selected source while its tab is active. They are still previews, not continuous video streams.
- The picker remembers its width and height under the user's XDG state directory. It starts at 800 × 500 when no size is saved.
- Cancelling `slurp` returns to the picker. A saved region is offered again only when it still matches the current output geometry.

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
