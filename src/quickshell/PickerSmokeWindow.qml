pragma ComponentBehavior: Bound

import Quickshell

FloatingWindow {
    id: surface

    color: content.backgroundColor
    visible: content.windowModelReady
    implicitWidth: content.preferredWidth
    implicitHeight: content.preferredHeight

    PickerWindow {
        id: content

        anchors.fill: parent
        hostWindow: surface
    }

    onClosed: content.cancel()
}
