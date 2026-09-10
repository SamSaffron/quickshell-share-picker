# Development and testing

[Back to the README](../README.md) · [Contributing](../CONTRIBUTING.md)

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

## Release maintainers

See [Contributing: release automation](../CONTRIBUTING.md#release-automation) for versioning, publishing, recovery stages and AUR synchronization.

## Live and mock testing

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
