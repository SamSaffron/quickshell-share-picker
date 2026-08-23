# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sam-saffron-jarvis/quickshell-share-picker/releases/tag/v0.1.0
