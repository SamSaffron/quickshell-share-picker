pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// PanelWindow is provided dynamically by Quickshell's active layer-shell backend.
// qmllint disable uncreatable-type
PanelWindow {
    id: overlay

    required property var targetScreen
    required property string label

    screen: targetScreen
    visible: targetScreen !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-share-picker-identify"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        color: "transparent"
        border.color: "#6ea0ff"
        border.width: 6
        radius: 12
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, overlay.width - 80)
        implicitWidth: identificationText.implicitWidth + 48
        implicitHeight: identificationText.implicitHeight + 32
        color: "#d92b2e33"
        border.color: "#806ea0ff"
        border.width: 1
        radius: 10

        Text {
            id: identificationText
            anchors.centerIn: parent
            color: "#f5f6f7"
            font.pixelSize: 28
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            text: overlay.label
        }
    }
}
