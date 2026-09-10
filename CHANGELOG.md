# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Documentation

- Shorten the README, add a real stock-picker / Quickshell before-and-after
  comparison and a sharing-scope diagram, and move detailed setup and protocol
  reference into linked guides. Ship the guides and visuals with source archives
  and installed documentation.

### Fixed

- The release workflow now includes `make aur`, which safely verifies and copies
  finalized metadata into a local AUR clone, commits it, and pushes AUR's master
  branch instead of stopping after updating this repository.
- The Arch package now requires `slurp` and `xdg-desktop-portal-hyprland`, so a
  standard installation includes working Region selection and XDPH integration.

## [0.2.1] - 2026-08-24

### Fixed

- Up and Down now move the selected window while the slash-activated filter
  field keeps keyboard focus, so filtering and list navigation work together.

## [0.2.0] - 2026-08-24

### Added

- `--test-live` launches the real picker from a source checkout or installed
  binary using current Hyprland windows and real ScreencopyView previews, without
  requiring an active XDPH request.
- Keyboard-first list focus, Enter-to-share, tab shortcuts, inline filtering,
  workspace grouping, stable interaction ordering, and richer preview metadata.
- Focused-monitor placement and preselection with transient physical-output
  identification overlays for multi-display setups.
- Wrapper-driven region cancellation recovery and a strictly validated,
  geometry-aware Repeat last region action.
- Opt-in `QSP_THEME=dark` palette.
- `scripts/release` automatically selects the next semantic version from the
  Unreleased changelog, provides staged `--prepare`, `--publish`, and `--finalize`
  recovery, and offers a one-command `--auto` workflow with required checks,
  reproducibility verification, GitHub publishing, and Arch finalization.
- `quickshell-share-picker-setup` safely installs, checks, previews, and removes
  a user-scoped managed XDPH configuration block, with conflict detection,
  one-time backup, atomic writes, symlink preservation, and optional portal
  restart. The Arch package now prints the setup command after installation.

### Changed

- The picker now uses a centered, keyboard-focused layer-shell surface instead
  of a normal tiled toplevel, so it opens above windows without a Hyprland rule.
- Geometry state written by the previous toplevel implementation is ignored once
  when migrating to the panel surface, restoring the compact 800×500 size.
- The selected window preview refreshes once per second while visible instead of
  remaining at its initial frame.
- Initial toplevel association is settled before the picker appears, and unchanged
  polling results no longer replace the list model, eliminating launch-time list
  bouncing and scroll movement.
- The Screen tab now mirrors the compact list-and-preview structure of the Window
  tab, including a once-per-second preview of the selected output.
- Elided window titles now use a delayed, size-constrained dark tooltip instead
  of the immediate unbounded native tooltip.
- Screen and window lists reserve a slim gutter for their scrollbars so titles
  and selection highlights never render underneath them.
- Tabs now use larger 48-pixel hit targets with explicit hover and selected-fill
  states, without a heavy accent outline.
- README Arch instructions now cover both the published PKGBUILD and building a
  pacman-managed custom package from the current checkout.

### Fixed

- QML lint discovery now prefers Qt 6's `qmllint` when a legacy Qt 5 tool also
  appears on `PATH`.
- Region selection now fully exits the focused layer-shell picker before the
  wrapper launches `slurp`, allowing `slurp` to acquire pointer and keyboard
  input reliably.
- The Arch package check now explicitly invokes Qt 6's `qmllint` and declares
  `qt6-declarative` as a check dependency, avoiding an incompatible Qt 5 tool on
  `PATH`.

## [0.1.2] - 2026-08-24

### Fixed

- Release archives now exclude local AUR source/package artifacts, with a CI
  regression check that injects an ignored archive before rebuilding.

## [0.1.1] - 2026-08-24

### Fixed

- ShellCheck compatibility across the older Ubuntu CI release and current Arch
  release without suppressing actionable diagnostics.

## [0.1.0] - 2026-08-24

### Added

- Independent Quickshell implementation of the three-tab XDPH share picker.
- XDPH window-list parsing and 64-bit-safe Hyprland address normalization.
- Quickshell toplevel matching, workspace-aware ordering and labels, themed
  icons, and selected-window `ScreencopyView` previews.
- Screen, window, and output-relative `slurp` region protocol output.
- Upstream-compatible restore-token visibility and default-on behavior, while
  preserving `--allow-token` compatibility.
- Stable picker-specific Quickshell application ID and a restrained light UI.
- XDG state geometry persistence and secure one-shot wrapper lifecycle.
- Fixture-driven headless protocol/concurrency tests and a real-QML offscreen
  smoke covering production toplevel iteration, tab defaults, and token output.
- Fatal QML warnings, required CI runtime coverage, install/uninstall targets,
  deterministic release archives, and an Arch release-package template.
- XDPH/BSD attribution and implementation notes for selected-window previews.

[Unreleased]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/releases/tag/v0.1.0
