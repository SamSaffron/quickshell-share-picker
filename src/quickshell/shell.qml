//@ pragma AppId io.github.samsaffron.quickshell-share-picker

import QtQuick
import Quickshell

ShellRoot {
    Loader {
        source: Quickshell.env("QSP_SMOKE_MODE") === "1"
            ? "PickerSmokeWindow.qml"
            : "PickerPanelWindow.qml"
    }
}
