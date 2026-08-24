pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: picker

    required property var hostWindow

    readonly property color backgroundColor: "#f7f7f8"
    readonly property color surfaceColor: "#ffffff"
    readonly property color borderColor: "#d8dadd"
    readonly property color textColor: "#202124"
    readonly property color mutedTextColor: "#687078"
    readonly property color accentColor: "#2864dc"
    readonly property color selectedColor: "#e7efff"
    readonly property bool testMode: Quickshell.env("QSP_TEST_MODE") === "1"
    readonly property bool liveTestMode: Quickshell.env("QSP_LIVE_TEST_MODE") === "1"
    readonly property bool smokeMode: Quickshell.env("QSP_SMOKE_MODE") === "1"
        && Quickshell.env("QT_QPA_PLATFORM") === "offscreen"
    readonly property bool slurpAvailable: Quickshell.env("QSP_SLURP_AVAILABLE") === "1"
    readonly property bool allowTokenSelection: Quickshell.env("QSP_ALLOW_TOKEN_SELECTION") === "1"
    readonly property var session: loadSession()

    property var screenEntries: []
    property var windowEntries: []
    property bool windowModelReady: false
    property bool finalized: false
    property bool rebuilding: false
    property int rebuildAttempts: 0

    readonly property int preferredWidth: initialWidth()
    readonly property int preferredHeight: initialHeight()

    function parseJson(text, fallback) {
        if (!text)
            return fallback;
        try {
            return JSON.parse(text);
        } catch (error) {
            return fallback;
        }
    }

    function loadSession() {
        return parseJson(sessionFile.text(), {
            "windows": [],
            "mock": {
                "enabled": false,
                "currentWorkspaceId": -1,
                "screens": [],
                "toplevels": []
            }
        });
    }

    function loadGeometry() {
        const geometry = parseJson(geometryFile.text(), {});
        return geometry.surface === "panel" ? geometry : { "width": 800, "height": 500 };
    }

    function boundedDimension(value, fallback, lower, upper) {
        const number = Number(value);
        if (!Number.isFinite(number))
            return fallback;
        return Math.max(lower, Math.min(upper, Math.round(number)));
    }

    function initialWidth() {
        const geometry = loadGeometry();
        return boundedDimension(geometry.width, 800, 640, 2400);
    }

    function initialHeight() {
        const geometry = loadGeometry();
        return boundedDimension(geometry.height, 500, 400, 1600);
    }

    function saveGeometry() {
        geometryFile.setText(JSON.stringify({
            "height": Math.round(hostWindow.height),
            "surface": "panel",
            "width": Math.round(hostWindow.width)
        }) + "\n");
    }

    function iconFor(windowClass) {
        const requested = String(windowClass || "");
        const safeName = /^[A-Za-z0-9._+-]+$/.test(requested) ? requested : "";
        if (safeName && Quickshell.hasThemeIcon(safeName))
            return Quickshell.iconPath(safeName, "application-x-executable");
        const lower = safeName.toLowerCase();
        if (lower && Quickshell.hasThemeIcon(lower))
            return Quickshell.iconPath(lower, "application-x-executable");
        return Quickshell.iconPath("application-x-executable", true);
    }

    function rebuildScreens() {
        const source = session.mock && session.mock.enabled
            ? session.mock.screens
            : [...Quickshell.screens];
        const result = [];
        for (let index = 0; index < source.length; ++index) {
            const screen = source[index];
            result.push({
                "height": Number(screen.height),
                "index": index,
                "name": String(screen.name),
                "screen": session.mock && session.mock.enabled ? null : screen,
                "width": Number(screen.width),
                "x": Number(screen.x),
                "y": Number(screen.y)
            });
        }
        screenEntries = result;
        if (screenList.currentIndex < 0 && result.length > 0)
            screenList.currentIndex = 0;
    }

    function runtimeToplevels() {
        if (session.mock && session.mock.enabled)
            return session.mock.toplevels || [];
        return Hyprland.toplevels.values;
    }

    function currentWorkspaceId() {
        if (session.mock && session.mock.enabled)
            return Number(session.mock.currentWorkspaceId);
        return Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : -1;
    }

    function windowModelsEqual(left, right) {
        if (left.length !== right.length)
            return false;
        for (let index = 0; index < left.length; ++index) {
            const a = left[index];
            const b = right[index];
            if (a.address !== b.address || a.captureSource !== b.captureSource
                    || a.className !== b.className || a.handle !== b.handle
                    || a.matched !== b.matched || a.sourceIndex !== b.sourceIndex
                    || a.title !== b.title || a.workspaceId !== b.workspaceId
                    || a.workspaceName !== b.workspaceName
                    || a.isCurrentWorkspace !== b.isCurrentWorkspace)
                return false;
        }
        return true;
    }

    function rebuildWindows() {
        if (!windowModelReady || rebuilding)
            return;
        rebuilding = true;

        try {
            const previous = selectedWindow();
            const previousKey = previous ? (liveTestMode ? previous.address : previous.handle) : "";
            const toplevels = runtimeToplevels();
            const currentWorkspace = currentWorkspaceId();
            const result = [];

            if (liveTestMode) {
                for (let index = 0; index < toplevels.length; ++index) {
                    const toplevel = toplevels[index];
                    const workspace = toplevel.workspace;
                    const workspaceId = workspace ? Number(workspace.id) : -1;
                    const wayland = toplevel.wayland;
                    result.push({
                        "address": String(toplevel.address),
                        "captureSource": wayland || null,
                        "className": String(wayland ? wayland.appId : ""),
                        "handle": String(index + 1),
                        "matched": true,
                        "sourceIndex": index,
                        "title": String(toplevel.title || (wayland ? wayland.title : "")),
                        "workspaceId": workspaceId,
                        "workspaceName": workspace ? String(workspace.name) : "",
                        "isCurrentWorkspace": workspaceId === currentWorkspace
                    });
                }
            } else {
                const portalWindows = session.windows || [];
                for (let index = 0; index < portalWindows.length; ++index) {
                    const portalWindow = portalWindows[index];
                    let match = null;
                    for (let candidateIndex = 0; candidateIndex < toplevels.length; ++candidateIndex) {
                        const candidate = toplevels[candidateIndex];
                        if (String(candidate.address) === portalWindow.normalizedAddress) {
                            match = candidate;
                            break;
                        }
                    }

                    const workspace = match ? match.workspace : null;
                    const workspaceId = workspace ? Number(workspace.id) : -1;
                    const workspaceName = workspace ? String(workspace.name) : "";
                    let captureSource = null;
                    if (!(session.mock && session.mock.enabled) && match && match.wayland)
                        captureSource = match.wayland;

                    result.push({
                        "address": portalWindow.normalizedAddress,
                        "captureSource": captureSource,
                        "className": String(portalWindow.class || (match && match.wayland ? match.wayland.appId : "")),
                        "handle": String(portalWindow.handle),
                        "matched": match !== null,
                        "sourceIndex": Number(portalWindow.sourceIndex),
                        "title": String(portalWindow.title || (match ? match.title : "")),
                        "workspaceId": workspaceId,
                        "workspaceName": workspaceName,
                        "isCurrentWorkspace": workspaceId === currentWorkspace
                    });
                }
            }

            result.sort((left, right) => {
                if (left.isCurrentWorkspace !== right.isCurrentWorkspace)
                    return left.isCurrentWorkspace ? -1 : 1;
                if (left.workspaceId !== right.workspaceId)
                    return left.workspaceId - right.workspaceId;
                return left.sourceIndex - right.sourceIndex;
            });

            if (windowModelsEqual(windowEntries, result))
                return;

            windowEntries = result;
            let selectedIndex = result.length > 0 ? 0 : -1;
            if (previousKey) {
                const preservedIndex = result.findIndex(entry => (liveTestMode ? entry.address : entry.handle) === previousKey);
                if (preservedIndex >= 0)
                    selectedIndex = preservedIndex;
            }
            windowList.currentIndex = selectedIndex;
        } finally {
            rebuilding = false;
        }
    }

    function selectedScreen() {
        const index = screenList.currentIndex;
        return index >= 0 && index < screenEntries.length ? screenEntries[index] : null;
    }

    function selectedWindow() {
        const index = windowList.currentIndex;
        return index >= 0 && index < windowEntries.length ? windowEntries[index] : null;
    }

    function finish(selection) {
        if (finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.visible ? restoreToken.checked : true;
        const flags = allowRestore ? "r" : "";
        resultFile.setText("[SELECTION]" + flags + "/" + selection + "\n");
        Qt.quit();
    }

    function cancel() {
        if (finalized)
            return;
        finalized = true;
        saveGeometry();
        Qt.quit();
    }

    function shareCurrent() {
        if (tabs.currentIndex === 0) {
            const screen = selectedScreen();
            if (screen)
                finish("screen:" + screen.name);
        } else if (tabs.currentIndex === 1) {
            const window = selectedWindow();
            if (window)
                finish("window:" + window.handle);
        } else {
            selectRegion();
        }
    }

    function selectRegion() {
        if (!slurpAvailable || finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.visible ? restoreToken.checked : true;
        const screens = screenEntries.map(entry => ({
            "height": entry.height,
            "name": entry.name,
            "width": entry.width,
            "x": entry.x,
            "y": entry.y
        }));
        regionRequestFile.setText(JSON.stringify({
            "allowRestore": allowRestore,
            "screens": screens
        }) + "\n");
        Qt.quit();
    }

    function shareEnabled() {
        if (tabs.currentIndex === 0)
            return selectedScreen() !== null;
        if (tabs.currentIndex === 1)
            return selectedWindow() !== null;
        return slurpAvailable;
    }

    function runSmoke() {
        const smokeRegion = Quickshell.env("QSP_SMOKE_REGION") === "1";
        if (Quickshell.appId !== "io.github.samsaffron.quickshell-share-picker")
            throw new Error("unexpected Quickshell app ID: " + Quickshell.appId);
        if (tabs.currentIndex !== (smokeRegion ? 2 : 1))
            throw new Error("picker did not open on the requested tab");
        if (rebuilding)
            throw new Error("window rebuild guard remained set");
        if (!windowModelReady)
            throw new Error("window model was published before it was ready");
        const stableEntries = windowEntries;
        rebuildWindows();
        if (windowEntries !== stableEntries)
            throw new Error("unchanged window model was unnecessarily replaced");
        if (previewRefreshTimer.interval !== 1000 || !previewRefreshTimer.repeat)
            throw new Error("selected window preview refresh timer is misconfigured");
        if (screenPreviewRefreshTimer.interval !== 1000 || !screenPreviewRefreshTimer.repeat)
            throw new Error("selected screen preview refresh timer is misconfigured");
        if (screenEntries.length > 0 && screenList.currentIndex !== 0)
            throw new Error("first screen was not selected before publication");
        if (!smokeRegion && liveTestMode) {
            if (windowEntries.length !== 3 || !selectedWindow()
                    || selectedWindow().handle !== "1" || selectedWindow().address !== "abc123")
                throw new Error("live-test toplevel rebuild did not complete");
        } else if (!smokeRegion && (windowEntries.length !== 1 || !selectedWindow() || selectedWindow().handle !== "17")) {
            throw new Error("production window-list rebuild did not complete");
        }
        if (restoreToken.visible !== allowTokenSelection)
            throw new Error("restore-token visibility did not follow the environment");
        if (restoreToken.visible && !restoreToken.checked)
            throw new Error("visible restore-token checkbox did not start checked");
        if (Quickshell.env("QSP_SMOKE_UNCHECK_TOKEN") === "1")
            restoreToken.checked = false;
        shareCurrent();
    }

    Component.onCompleted: {
        rebuildScreens();
        const requestedTab = String(Quickshell.env("XDPH_PICKER_DEFAULT_TAB") || "window").toLowerCase();
        tabs.currentIndex = requestedTab === "screen" ? 0 : requestedTab === "region" ? 2 : 1;
        restoreToken.checked = Quickshell.env("QSP_ALLOW_TOKEN") !== "0";
        if (smokeMode) {
            windowModelReady = true;
            rebuildWindows();
            Qt.callLater(runSmoke);
        } else {
            initialWindowTimer.start();
        }
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged() {
            if (picker.windowModelReady)
                picker.rebuildWindows();
        }
    }

    Connections {
        target: Hyprland.toplevels

        function onValuesChanged() {
            if (picker.windowModelReady)
                picker.rebuildWindows();
        }
    }

    FileView {
        id: sessionFile
        path: String(Quickshell.env("QSP_SESSION_FILE") || "")
        blockLoading: true
        printErrors: true
    }

    FileView {
        id: resultFile
        path: String(Quickshell.env("QSP_RESULT_FILE") || "")
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: regionRequestFile
        path: String(Quickshell.env("QSP_REGION_REQUEST_FILE") || "")
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: geometryFile
        path: String(Quickshell.env("QSP_GEOMETRY_FILE") || "")
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    Timer {
        id: initialWindowTimer
        interval: 250
        onTriggered: {
            picker.windowModelReady = true;
            picker.rebuildScreens();
            picker.rebuildWindows();
            rebuildTimer.start();
        }
    }

    Timer {
        id: rebuildTimer
        interval: 250
        repeat: true
        onTriggered: {
            picker.rebuildAttempts += 1;
            picker.rebuildScreens();
            picker.rebuildWindows();
            if (picker.rebuildAttempts >= 12)
                stop();
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: picker.cancel()
    }

    Shortcut {
        sequence: "Ctrl+Return"
        onActivated: {
            if (picker.shareEnabled())
                picker.shareCurrent();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: picker.backgroundColor

        Repeater {
            model: picker.testMode ? null : Hyprland.toplevels

            delegate: Item {
                id: associationDelegate
                required property var modelData
                visible: false
                width: 0
                height: 0

                Connections {
                    target: associationDelegate.modelData

                    function onAddressChanged() {
                        picker.rebuildWindows();
                    }

                    function onWaylandHandleChanged() {
                        picker.rebuildWindows();
                    }

                    function onWorkspaceChanged() {
                        picker.rebuildWindows();
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: picker.surfaceColor
                border.color: picker.borderColor
                border.width: 1
                radius: 6

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    TabBar {
                        id: tabs
                        Layout.fillWidth: true
                        background: Rectangle {
                            color: "#f1f2f4"
                            border.color: picker.borderColor
                            border.width: 1
                        }

                        TabButton { text: "Screen" }
                        TabButton { text: "Window" }
                        TabButton { text: "Region" }
                    }

                    StackLayout {
                        currentIndex: tabs.currentIndex
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Item {
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 280
                                    Layout.minimumWidth: 220
                                    Layout.maximumWidth: 300
                                    Layout.fillHeight: true
                                    color: "#fbfbfc"
                                    border.color: picker.borderColor
                                    border.width: 1
                                    radius: 4

                                    ListView {
                                        id: screenList
                                        readonly property real scrollGutter: screenScrollBar.visible ? screenScrollBar.width + 4 : 0
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        clip: true
                                        spacing: 2
                                        model: picker.screenEntries
                                        activeFocusOnTab: true
                                        keyNavigationEnabled: true
                                        highlightMoveDuration: 80
                                        highlight: Rectangle {
                                            color: picker.selectedColor
                                            border.color: picker.accentColor
                                            border.width: 1
                                            radius: 4
                                        }

                                        delegate: Item {
                                            id: screenDelegate
                                            required property var modelData
                                            required property int index
                                            width: screenList.width - screenList.scrollGutter
                                            height: 54

                                            Column {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 2

                                                Text {
                                                    width: parent.width
                                                    color: picker.textColor
                                                    elide: Text.ElideRight
                                                    font.weight: Font.DemiBold
                                                    text: screenDelegate.modelData.name
                                                }

                                                Text {
                                                    width: parent.width
                                                    color: picker.mutedTextColor
                                                    elide: Text.ElideRight
                                                    font.pixelSize: 12
                                                    text: screenDelegate.modelData.width + "×" + screenDelegate.modelData.height
                                                        + " at " + screenDelegate.modelData.x + ", " + screenDelegate.modelData.y
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: screenList.currentIndex = screenDelegate.index
                                                onDoubleClicked: {
                                                    screenList.currentIndex = screenDelegate.index;
                                                    picker.finish("screen:" + screenDelegate.modelData.name);
                                                }
                                            }
                                        }

                                        ScrollBar.vertical: ScrollBar {
                                            id: screenScrollBar
                                            policy: ScrollBar.AsNeeded
                                            width: 8
                                        }
                                    }
                                }

                                Rectangle {
                                    id: screenPreviewFrame
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumWidth: 200
                                    color: "#17191c"
                                    radius: 4
                                    clip: true

                                    readonly property var selection: picker.selectedScreen()
                                    readonly property real sourceRatio: screenPreview.sourceSize.height > 0
                                        ? screenPreview.sourceSize.width / screenPreview.sourceSize.height : 1

                                    ScreencopyView {
                                        id: screenPreview
                                        anchors.centerIn: parent
                                        captureSource: screenPreviewFrame.selection ? screenPreviewFrame.selection.screen : null
                                        live: false
                                        paintCursor: false
                                        width: hasContent ? Math.min(screenPreviewFrame.width,
                                            screenPreviewFrame.height * screenPreviewFrame.sourceRatio) : 0
                                        height: hasContent ? width / screenPreviewFrame.sourceRatio : 0
                                    }

                                    Timer {
                                        id: screenPreviewRefreshTimer
                                        interval: 1000
                                        repeat: true
                                        running: picker.windowModelReady && tabs.currentIndex === 0
                                            && screenPreview.captureSource !== null
                                        onTriggered: screenPreview.captureFrame()
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 40
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                        color: "#c8cbd0"
                                        visible: !screenPreview.hasContent
                                        text: {
                                            if (!screenPreviewFrame.selection)
                                                return "Select a screen to preview";
                                            if (picker.testMode)
                                                return "Preview unavailable in mock mode";
                                            if (!screenPreviewFrame.selection.screen)
                                                return "No preview available";
                                            return "Loading preview…";
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 300
                                    Layout.minimumWidth: 220
                                    Layout.maximumWidth: 300
                                    Layout.fillHeight: true
                                    color: "#fbfbfc"
                                    border.color: picker.borderColor
                                    border.width: 1
                                    radius: 4

                                    ListView {
                                        id: windowList
                                        readonly property real scrollGutter: windowScrollBar.visible ? windowScrollBar.width + 4 : 0
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        clip: true
                                        spacing: 2
                                        model: picker.windowEntries
                                        activeFocusOnTab: true
                                        keyNavigationEnabled: true
                                        highlightMoveDuration: 80
                                        highlight: Rectangle {
                                            color: picker.selectedColor
                                            border.color: picker.accentColor
                                            border.width: 1
                                            radius: 4
                                        }

                                        delegate: Item {
                                            id: windowDelegate
                                            required property var modelData
                                            required property int index
                                            width: windowList.width - windowList.scrollGutter
                                            height: 46

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 9

                                                Image {
                                                    Layout.preferredWidth: 24
                                                    Layout.preferredHeight: 24
                                                    sourceSize: Qt.size(24, 24)
                                                    source: picker.iconFor(windowDelegate.modelData.className)
                                                    fillMode: Image.PreserveAspectFit
                                                }

                                                Text {
                                                    id: windowTitle
                                                    Layout.fillWidth: true
                                                    color: picker.textColor
                                                    elide: Text.ElideRight
                                                    text: (windowDelegate.modelData.workspaceName ? "[" + windowDelegate.modelData.workspaceName + "] " : "")
                                                        + windowDelegate.modelData.className + ": " + windowDelegate.modelData.title
                                                }
                                            }

                                            MouseArea {
                                                id: windowMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: windowList.currentIndex = windowDelegate.index
                                                onDoubleClicked: {
                                                    windowList.currentIndex = windowDelegate.index;
                                                    picker.finish("window:" + windowDelegate.modelData.handle);
                                                }
                                                onContainsMouseChanged: {
                                                    if (containsMouse && windowTitle.truncated) {
                                                        windowToolTipDelay.restart();
                                                    } else {
                                                        windowToolTipDelay.stop();
                                                        windowToolTipTimeout.stop();
                                                        windowToolTip.visible = false;
                                                    }
                                                }
                                            }

                                            ToolTip {
                                                id: windowToolTip
                                                x: 8
                                                y: windowDelegate.height + 4
                                                width: Math.min(420, Math.max(220, windowTitle.implicitWidth + leftPadding + rightPadding))
                                                padding: 8
                                                visible: false
                                                text: windowTitle.text

                                                contentItem: Text {
                                                    id: windowToolTipText
                                                    width: windowToolTip.width - windowToolTip.leftPadding - windowToolTip.rightPadding
                                                    color: "#f5f6f7"
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 3
                                                    wrapMode: Text.Wrap
                                                    text: windowToolTip.text
                                                }

                                                background: Rectangle {
                                                    color: "#2b2e33"
                                                    border.color: "#545960"
                                                    border.width: 1
                                                    radius: 4
                                                }
                                            }

                                            Timer {
                                                id: windowToolTipDelay
                                                interval: 650
                                                onTriggered: {
                                                    if (windowMouseArea.containsMouse && windowTitle.truncated) {
                                                        windowToolTip.visible = true;
                                                        windowToolTipTimeout.restart();
                                                    }
                                                }
                                            }

                                            Timer {
                                                id: windowToolTipTimeout
                                                interval: 5000
                                                onTriggered: windowToolTip.visible = false
                                            }

                                        }

                                        ScrollBar.vertical: ScrollBar {
                                            id: windowScrollBar
                                            policy: ScrollBar.AsNeeded
                                            width: 8
                                        }
                                    }
                                }

                                Rectangle {
                                    id: previewFrame
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#17191c"
                                    radius: 4
                                    clip: true

                                    readonly property var selection: picker.selectedWindow()
                                    readonly property real sourceRatio: preview.sourceSize.height > 0
                                        ? preview.sourceSize.width / preview.sourceSize.height : 1

                                    ScreencopyView {
                                        id: preview
                                        anchors.centerIn: parent
                                        captureSource: previewFrame.selection ? previewFrame.selection.captureSource : null
                                        live: false
                                        paintCursor: false
                                        width: hasContent ? Math.min(previewFrame.width, previewFrame.height * previewFrame.sourceRatio) : 0
                                        height: hasContent ? width / previewFrame.sourceRatio : 0
                                    }

                                    Timer {
                                        id: previewRefreshTimer
                                        interval: 1000
                                        repeat: true
                                        running: picker.windowModelReady && tabs.currentIndex === 1
                                            && preview.captureSource !== null
                                        onTriggered: preview.captureFrame()
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 40
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                        color: "#c8cbd0"
                                        visible: !preview.hasContent
                                        text: {
                                            if (!previewFrame.selection)
                                                return "Select a window to preview";
                                            if (picker.testMode)
                                                return "Preview unavailable in mock mode";
                                            if (!previewFrame.selection.matched || !previewFrame.selection.captureSource)
                                                return "No preview available";
                                            return "Loading preview…";
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

                                Button {
                                    id: regionButton
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 40
                                    enabled: picker.slurpAvailable
                                    text: picker.slurpAvailable ? "Select Region…" : "Select Region… (slurp is not installed)"
                                    onClicked: picker.selectRegion()
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            CheckBox {
                id: restoreToken
                visible: picker.allowTokenSelection
                text: "Allow a restore token"
                hoverEnabled: true
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: "By selecting this, the application will be given a restore token that it can use to skip prompting you next time.\nOnly select if you trust the application."
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Button {
                    id: shareButton
                    text: "Share"
                    enabled: picker.shareEnabled()
                    highlighted: true
                    onClicked: picker.shareCurrent()
                }

                Button {
                    text: "Cancel"
                    onClicked: picker.cancel()
                }
            }
        }
    }
}
