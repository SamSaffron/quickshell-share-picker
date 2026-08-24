# Contributing

Thank you for improving quickshell-share-picker.

## Before opening a change

- Keep the picker compatible with stock xdg-desktop-portal-hyprland's custom
  selector protocol.
- Preserve the compact Screen/Window/Region interaction structure unless a
  change is explicitly motivated and documented.
- Do not copy code or assets from GPL projects into this MIT repository.
- Avoid new runtime dependencies when the Python standard library or current
  Quickshell APIs are sufficient.

For security-sensitive reports, follow [SECURITY.md](SECURITY.md) instead of
opening a public issue.

## Development setup

Install Python 3, shellcheck, qmllint/Qt declarative tools, Quickshell, and the
runtime dependencies listed in the README. Then run:

```sh
make check
```

`make test` is fully headless and exercises the Python protocol/wrapper suite.
`make smoke` exercises the real QML runtime on Qt's offscreen platform, while
`./scripts/run-mock` opens the real QML UI with deterministic fixture data and
is the preferred way to inspect layout changes without constructing XDPH
environment records.

## Changes and tests

1. Add focused tests for parser, output protocol, quoting, cleanup, or
   concurrency changes.
2. Keep protocol fixtures under `tests/fixtures/` and UI mock data under
   `src/fixtures/`.
3. Run `make format`, then `make check`.
4. If UI behavior changed, run the mock launcher and a real Hyprland/XDPH share
   flow. State clearly when either runtime check was unavailable.
5. Update `CHANGELOG.md` for user-visible changes.

Commits should be small and use imperative summaries. Pull requests should
explain the behavior change, tests run, and any protocol or packaging impact.

## Release automation

Install the maintainer tools (`github-cli`, `pacman-contrib`, `base-devel`, and
the development dependencies above), commit all intended changes, and start from
a clean `main` branch. A complete release is then one command:

```sh
./scripts/release --auto
```

The script inspects the `Unreleased` changelog sections and selects the next
version automatically: `Added`, `Changed`, `Removed`, or `Deprecated` changes
produce a minor bump, while a release containing only `Fixed` or `Security`
changes produces a patch bump. Use `--bump major|minor|patch` or an explicit
version only when overriding that decision:

```sh
./scripts/release --auto --bump major
./scripts/release --auto 1.0.0
```

The script prompts once, then:

1. Updates `VERSION`, README release references, `CHANGELOG.md`, `aur/PKGBUILD`,
   and `aur/.SRCINFO`.
2. Runs formatting and all required checks.
3. Commits `Prepare v<VERSION>`, builds twice with one `SOURCE_DATE_EPOCH`,
   compares both archives byte-for-byte, and creates the annotated tag.
4. Pushes `main` and the tag and uploads the exact archive with GitHub CLI.
5. Replaces the fail-closed AUR checksum, regenerates `.SRCINFO`, builds and tests
   the published Arch package, commits the finalized metadata, and pushes it.

Use `--yes` for non-interactive automation. The same workflow is split into
recoverable stages if a network or publishing step fails:

```sh
./scripts/release --prepare
./scripts/release --publish
./scripts/release --finalize
```

The script refuses dirty trees, non-`main` branches, malformed/non-increasing
versions, existing tags, missing tools, non-reproducible archives, unavailable
GitHub releases, and all-zero finalized checksums. Do not commit generated
`dist/` archives or Arch build artifacts.
