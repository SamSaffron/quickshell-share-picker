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

## Release checklist

Maintainers should:

1. Confirm `VERSION`, `CHANGELOG.md`, `aur/PKGBUILD`, and `aur/.SRCINFO` agree.
2. Run all checks, including required shellcheck and qmllint.
3. Build twice with the same `SOURCE_DATE_EPOCH` and compare SHA-256 hashes.
4. Tag `v<VERSION>` and upload the exact `make dist` archive.
5. Replace the AUR's all-zero checksum using `updpkgsums`, regenerate
   `.SRCINFO`, and test `makepkg` before publishing it.

Do not commit generated `dist/` archives.
