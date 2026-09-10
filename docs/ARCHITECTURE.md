# Architecture and selector protocol

[Back to the README](../README.md) · [Installation](INSTALL.md) · [Security](../SECURITY.md)

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
