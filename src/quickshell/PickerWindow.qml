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

    readonly property string themeName: String(Quickshell.env("QSP_THEME") || "light").toLowerCase()
    readonly property bool darkTheme: themeName === "dark"
    readonly property color backgroundColor: darkTheme ? "#181a1f" : "#f7f7f8"
    readonly property color surfaceColor: darkTheme ? "#22252b" : "#ffffff"
    readonly property color borderColor: darkTheme ? "#3a3f47" : "#d8dadd"
    readonly property color textColor: darkTheme ? "#f1f3f5" : "#202124"
    readonly property color mutedTextColor: darkTheme ? "#aab0b8" : "#687078"
    readonly property color accentColor: darkTheme ? "#6ea0ff" : "#2864dc"
    readonly property color selectedColor: darkTheme ? "#2b4168" : "#e7efff"
    readonly property color tabColor: darkTheme ? "#20242a" : "#f1f2f4"
    readonly property color tabHoverColor: darkTheme ? "#2b3038" : "#e6e8eb"
    readonly property color listColor: darkTheme ? "#1e2127" : "#fbfbfc"
    readonly property color previewColor: darkTheme ? "#111318" : "#17191c"
    readonly property color tooltipColor: darkTheme ? "#30343b" : "#2b2e33"
    readonly property color tooltipBorderColor: darkTheme ? "#606875" : "#545960"
    readonly property color tooltipTextColor: "#f5f6f7"
    readonly property color metadataColor: darkTheme ? "#dd181a1f" : "#dd202328"
    readonly property bool testMode: Quickshell.env("QSP_TEST_MODE") === "1"
    readonly property bool liveTestMode: Quickshell.env("QSP_LIVE_TEST_MODE") === "1"
    readonly property bool smokeMode: Quickshell.env("QSP_SMOKE_MODE") === "1"
        && Quickshell.env("QT_QPA_PLATFORM") === "offscreen"
    readonly property bool slurpAvailable: Quickshell.env("QSP_SLURP_AVAILABLE") === "1"
    readonly property bool regionRecovery: Quickshell.env("QSP_REGION_RECOVERY") === "1"
    readonly property bool allowTokenSelection: Quickshell.env("QSP_ALLOW_TOKEN_SELECTION") === "1"
    property var preferredScreen: null
    readonly property var session: loadSession()

    property var screenEntries: []
    property var windowEntries: []
    property var filteredWindowEntries: []
    property string windowFilterText: ""
    property bool windowFilterActive: false
    property bool windowOrderingFrozen: false
    property var identificationScreen: null
    property string identificationLabel: ""
    property bool identificationVisible: false
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

    function resolvePreferredScreen() {
        const screens = [...Quickshell.screens];
        if (screens.length === 0)
            return null;
        const focused = Hyprland.focusedMonitor;
        if (focused) {
            const match = screens.find(screen => String(screen.name) === String(focused.name));
            if (match)
                return match;
        }
        return screens[0];
    }

    function rebuildScreens() {
        const source = session.mock && session.mock.enabled
            ? session.mock.screens
            : [...Quickshell.screens];
        const result = [];
        for (let index = 0; index < source.length; ++index) {
            const screen = source[index];
            const monitor = session.mock && session.mock.enabled ? null : Hyprland.monitorFor(screen);
            const refreshRate = monitor && monitor.lastIpcObject
                ? Number(monitor.lastIpcObject["refreshRate"] || 0) : 0;
            result.push({
                "height": Number(screen.height),
                "index": index,
                "monitor": monitor,
                "name": String(screen.name),
                "refreshRate": refreshRate,
                "scale": monitor ? Number(monitor.scale) : Number(screen.scale || 1),
                "screen": session.mock && session.mock.enabled ? null : screen,
                "width": Number(screen.width),
                "x": Number(screen.x),
                "y": Number(screen.y)
            });
        }
        screenEntries = result;
        if (screenList.currentIndex < 0 && result.length > 0) {
            const preferredName = preferredScreen ? String(preferredScreen.name) : "";
            const preferredIndex = result.findIndex(entry => entry.name === preferredName);
            screenList.currentIndex = preferredIndex >= 0 ? preferredIndex : 0;
        }
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

    function workspaceSection(workspaceId, workspaceName, isCurrent, matched) {
        if (!matched)
            return "Unavailable workspace";
        if (isCurrent)
            return "Current · " + (workspaceName || workspaceId);
        if (workspaceId > 0)
            return "Workspace " + (workspaceName || workspaceId);
        return "Special · " + (workspaceName || "workspace");
    }

    function workspaceSortCategory(workspaceId, isCurrent, matched) {
        if (isCurrent)
            return 0;
        if (matched && workspaceId > 0)
            return 1;
        if (matched)
            return 2;
        return 3;
    }

    function windowKey(entry) {
        return liveTestMode ? entry.address : entry.handle;
    }

    function refreshFilteredWindows() {
        const previous = selectedWindow();
        const previousKey = previous ? windowKey(previous) : "";
        const query = windowFilterText.trim().toLowerCase();
        const result = query ? windowEntries.filter(entry => {
            const haystack = (entry.className + " " + entry.title + " "
                + entry.workspaceName + " " + entry.workspaceId).toLowerCase();
            return haystack.includes(query);
        }) : windowEntries;
        filteredWindowEntries = result;
        let selectedIndex = result.length > 0 ? 0 : -1;
        if (previousKey) {
            const preservedIndex = result.findIndex(entry => windowKey(entry) === previousKey);
            if (preservedIndex >= 0)
                selectedIndex = preservedIndex;
        }
        windowList.currentIndex = selectedIndex;
    }

    function moveWindowSelection(direction) {
        if (direction > 0)
            windowList.incrementCurrentIndex();
        else if (direction < 0)
            windowList.decrementCurrentIndex();
    }

    function focusCurrentTab() {
        Qt.callLater(() => {
            if (tabs.currentIndex === 0)
                screenList.forceActiveFocus();
            else if (tabs.currentIndex === 1)
                (windowFilterActive ? windowFilter : windowList).forceActiveFocus();
            else
                regionButton.forceActiveFocus();
        });
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
                    || a.workspaceName !== b.workspaceName || a.sectionLabel !== b.sectionLabel
                    || a.sortCategory !== b.sortCategory
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
                        "sectionLabel": workspaceSection(workspaceId, workspace ? String(workspace.name) : "",
                            workspaceId === currentWorkspace, true),
                        "sortCategory": workspaceSortCategory(workspaceId, workspaceId === currentWorkspace, true),
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
                        "sectionLabel": workspaceSection(workspaceId, workspaceName,
                            workspaceId === currentWorkspace, match !== null),
                        "sortCategory": workspaceSortCategory(workspaceId,
                            workspaceId === currentWorkspace, match !== null),
                        "isCurrentWorkspace": workspaceId === currentWorkspace
                    });
                }
            }

            const previousOrder = {};
            const previousEntries = {};
            for (let index = 0; index < windowEntries.length; ++index) {
                const key = windowKey(windowEntries[index]);
                previousOrder[key] = index;
                previousEntries[key] = windowEntries[index];
            }
            if (windowOrderingFrozen) {
                for (let index = 0; index < result.length; ++index) {
                    const previousEntry = previousEntries[windowKey(result[index])];
                    if (previousEntry) {
                        result[index].sectionLabel = previousEntry.sectionLabel;
                        result[index].sortCategory = previousEntry.sortCategory;
                    }
                }
            }

            result.sort((left, right) => {
                if (windowOrderingFrozen) {
                    const leftOrder = previousOrder[windowKey(left)];
                    const rightOrder = previousOrder[windowKey(right)];
                    const leftKnown = leftOrder !== undefined;
                    const rightKnown = rightOrder !== undefined;
                    if (leftKnown !== rightKnown)
                        return leftKnown ? -1 : 1;
                    if (leftKnown && leftOrder !== rightOrder)
                        return leftOrder - rightOrder;
                }
                if (left.sortCategory !== right.sortCategory)
                    return left.sortCategory - right.sortCategory;
                if (left.sortCategory === 1 && left.workspaceId !== right.workspaceId)
                    return left.workspaceId - right.workspaceId;
                return left.sourceIndex - right.sourceIndex;
            });

            if (windowModelsEqual(windowEntries, result))
                return;

            windowEntries = result;
            refreshFilteredWindows();
        } finally {
            rebuilding = false;
        }
    }

    function requestScreenIdentification(entry) {
        if (!entry || !entry.screen || testMode || smokeMode)
            return;
        identificationScreen = entry.screen;
        const rate = entry.refreshRate > 0 ? " · " + Math.round(entry.refreshRate) + " Hz" : "";
        identificationLabel = entry.name + "\n" + entry.width + "×" + entry.height
            + " · scale " + entry.scale + rate;
        identificationVisible = false;
        identificationDelay.restart();
    }

    function selectedScreen() {
        const index = screenList.currentIndex;
        return index >= 0 && index < screenEntries.length ? screenEntries[index] : null;
    }

    function selectedWindow() {
        const index = windowList.currentIndex;
        return index >= 0 && index < filteredWindowEntries.length ? filteredWindowEntries[index] : null;
    }

    function finish(selection) {
        if (finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.checked;
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

    function lastRegionAvailable() {
        const region = session.lastRegion;
        if (!region)
            return false;
        const screen = screenEntries.find(entry => entry.name === region.output);
        return screen !== undefined
            && screen.width === region.outputWidth
            && screen.height === region.outputHeight
            && region.x >= 0 && region.y >= 0
            && region.width > 0 && region.height > 0
            && region.x + region.width <= screen.width
            && region.y + region.height <= screen.height;
    }

    function regionScreens() {
        return screenEntries.map(entry => ({
            "height": entry.height,
            "name": entry.name,
            "width": entry.width,
            "x": entry.x,
            "y": entry.y
        }));
    }

    function selectRegion() {
        if (!slurpAvailable || finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.checked;
        regionRequestFile.setText(JSON.stringify({
            "allowRestore": allowRestore,
            "screens": regionScreens()
        }) + "\n");
        Qt.quit();
    }

    function repeatLastRegion() {
        if (!session.lastRegion || finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.checked;
        repeatRegionRequestFile.setText(JSON.stringify({
            "allowRestore": allowRestore,
            "region": session.lastRegion,
            "screens": regionScreens()
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
        const smokeAction = Quickshell.env("QSP_SMOKE_ACTION");
        if (tabs.currentIndex !== (smokeAction === "screen" ? 0 : smokeRegion ? 2 : 1))
            throw new Error("picker did not open on the requested tab");
        if (regionRecovery !== smokeRegion)
            throw new Error("region recovery state did not follow the environment");
        if (rebuilding)
            throw new Error("window rebuild guard remained set");
        if (!windowModelReady)
            throw new Error("window model was published before it was ready");
        if ((Quickshell.env("QSP_THEME") === "dark") !== darkTheme)
            throw new Error("theme selection did not follow the environment");
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
        if (!smokeRegion && windowEntries.length > 0) {
            windowFilterText = windowEntries[0].className.toLowerCase();
            refreshFilteredWindows();
            if (filteredWindowEntries.length === 0)
                throw new Error("window filter hid a matching entry");
            windowFilterText = "";
            refreshFilteredWindows();
            if (filteredWindowEntries.length !== windowEntries.length)
                throw new Error("clearing the window filter did not restore the model");
            const previousIndex = windowList.currentIndex;
            windowList.currentIndex = 0;
            moveWindowSelection(1);
            if (windowList.currentIndex !== Math.min(1, windowEntries.length - 1))
                throw new Error("filter-field down navigation did not move selection");
            moveWindowSelection(-1);
            if (windowList.currentIndex !== 0)
                throw new Error("filter-field up navigation did not move selection");
            windowList.currentIndex = previousIndex;
            if (!windowEntries[0].sectionLabel)
                throw new Error("window workspace section label is missing");
        }
        if (!smokeRegion && liveTestMode) {
            if (windowEntries.length !== 3 || !selectedWindow()
                    || selectedWindow().handle !== "1" || selectedWindow().address !== "abc123")
                throw new Error("live-test toplevel rebuild did not complete");
        } else if (!smokeRegion && (windowEntries.length !== 1 || !selectedWindow() || selectedWindow().handle !== "17")) {
            throw new Error("production window-list rebuild did not complete");
        }
        if (restoreToken.visible !== allowTokenSelection)
            throw new Error("restore-token visibility did not follow the environment");
        if (restoreToken.checked !== (Quickshell.env("QSP_ALLOW_TOKEN") !== "0"))
            throw new Error("restore-token default did not preserve enabled behavior");
        if (Quickshell.env("QSP_SMOKE_CHECK_TOKEN") === "1") {
            if (!restoreToken.visible)
                throw new Error("cannot opt in through a hidden checkbox");
            restoreToken.checked = true;
        }
        if (Quickshell.env("QSP_SMOKE_UNCHECK_TOKEN") === "1")
            restoreToken.checked = false;
        if (smokeAction === "repeat") {
            if (!lastRegionAvailable())
                throw new Error("smoke saved region is unavailable");
            repeatLastRegion();
        } else {
            shareCurrent();
        }
    }

    Component.onCompleted: {
        preferredScreen = resolvePreferredScreen();
        rebuildScreens();
        const requestedTab = regionRecovery ? "region"
            : String(Quickshell.env("XDPH_PICKER_DEFAULT_TAB") || "window").toLowerCase();
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
        id: repeatRegionRequestFile
        path: String(Quickshell.env("QSP_REPEAT_REGION_REQUEST_FILE") || "")
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
        id: identificationDelay
        interval: 500
        onTriggered: {
            picker.identificationVisible = true;
            identificationTimeout.restart();
        }
    }

    Timer {
        id: identificationTimeout
        interval: 1000
        onTriggered: picker.identificationVisible = false
    }

    Timer {
        id: initialWindowTimer
        interval: 250
        onTriggered: {
            picker.windowModelReady = true;
            picker.rebuildScreens();
            picker.rebuildWindows();
            picker.focusCurrentTab();
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
        onActivated: {
            if (picker.windowFilterActive) {
                picker.windowFilterText = "";
                picker.windowFilterActive = false;
                picker.refreshFilteredWindows();
                windowList.forceActiveFocus();
            } else {
                picker.cancel();
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+1"
        onActivated: tabs.currentIndex = 0
    }

    Shortcut {
        sequence: "Ctrl+2"
        onActivated: tabs.currentIndex = 1
    }

    Shortcut {
        sequence: "Ctrl+3"
        onActivated: tabs.currentIndex = 2
    }

    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: tabs.currentIndex = (tabs.currentIndex + 1) % 3
    }

    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: tabs.currentIndex = (tabs.currentIndex + 2) % 3
    }

    Shortcut {
        sequence: "/"
        enabled: tabs.currentIndex === 1 && !picker.windowFilterActive
        onActivated: {
            picker.windowOrderingFrozen = true;
            picker.windowFilterActive = true;
            picker.windowFilterText = "";
            picker.refreshFilteredWindows();
            picker.focusCurrentTab();
        }
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
                        Layout.preferredHeight: 48
                        palette.buttonText: picker.textColor
                        palette.highlight: picker.selectedColor
                        palette.highlightedText: picker.textColor
                        palette.windowText: picker.textColor
                        onCurrentIndexChanged: {
                            if (picker.windowModelReady)
                                picker.focusCurrentTab();
                        }
                        background: Rectangle {
                            color: picker.tabColor
                            border.color: picker.borderColor
                            border.width: 1
                        }

                        TabButton {
                            text: "Screen"
                            hoverEnabled: true
                            background: Rectangle {
                                color: parent.checked ? picker.selectedColor
                                    : parent.hovered ? picker.tabHoverColor : picker.tabColor
                                border.color: picker.borderColor
                                border.width: 1
                            }
                            contentItem: Text {
                                color: picker.textColor
                                font.weight: parent.checked ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: parent.text
                            }
                        }
                        TabButton {
                            text: "Window"
                            hoverEnabled: true
                            background: Rectangle {
                                color: parent.checked ? picker.selectedColor
                                    : parent.hovered ? picker.tabHoverColor : picker.tabColor
                                border.color: picker.borderColor
                                border.width: 1
                            }
                            contentItem: Text {
                                color: picker.textColor
                                font.weight: parent.checked ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: parent.text
                            }
                        }
                        TabButton {
                            text: "Region"
                            hoverEnabled: true
                            background: Rectangle {
                                color: parent.checked ? picker.selectedColor
                                    : parent.hovered ? picker.tabHoverColor : picker.tabColor
                                border.color: picker.borderColor
                                border.width: 1
                            }
                            contentItem: Text {
                                color: picker.textColor
                                font.weight: parent.checked ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: parent.text
                            }
                        }
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
                                    color: picker.listColor
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
                                        Keys.onReturnPressed: event => {
                                            if (picker.selectedScreen())
                                                picker.shareCurrent();
                                            event.accepted = true;
                                        }
                                        highlightMoveDuration: 80
                                        highlight: Rectangle {
                                            color: picker.selectedColor
                                            border.color: screenList.activeFocus ? picker.accentColor : picker.borderColor
                                            border.width: screenList.activeFocus ? 2 : 1
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
                                                hoverEnabled: true
                                                onEntered: picker.requestScreenIdentification(screenDelegate.modelData)
                                                onClicked: {
                                                    screenList.currentIndex = screenDelegate.index;
                                                    picker.requestScreenIdentification(screenDelegate.modelData);
                                                }
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
                                    color: picker.previewColor
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

                                    BusyIndicator {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -18
                                        width: 32
                                        height: 32
                                        running: visible
                                        visible: screenPreviewFrame.selection && screenPreview.captureSource
                                            && !screenPreview.hasContent
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: 22
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

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 52
                                        color: picker.metadataColor
                                        visible: screenPreviewFrame.selection !== null

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 2

                                            Text {
                                                width: parent.width
                                                color: picker.tooltipTextColor
                                                elide: Text.ElideRight
                                                font.weight: Font.DemiBold
                                                text: screenPreviewFrame.selection ? screenPreviewFrame.selection.name : ""
                                            }

                                            Text {
                                                width: parent.width
                                                color: "#c8cbd0"
                                                elide: Text.ElideRight
                                                font.pixelSize: 11
                                                text: screenPreviewFrame.selection
                                                    ? screenPreviewFrame.selection.width + "×" + screenPreviewFrame.selection.height
                                                        + " · scale " + screenPreviewFrame.selection.scale
                                                        + (screenPreviewFrame.selection.refreshRate > 0
                                                            ? " · " + Math.round(screenPreviewFrame.selection.refreshRate) + " Hz" : "")
                                                    : ""
                                            }
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
                                    color: picker.listColor
                                    border.color: picker.borderColor
                                    border.width: 1
                                    radius: 4

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: picker.windowFilterActive
                                            spacing: 6

                                            TextField {
                                                id: windowFilter
                                                Layout.fillWidth: true
                                                placeholderText: "Filter windows…"
                                                palette.base: picker.surfaceColor
                                                palette.text: picker.textColor
                                                palette.placeholderText: picker.mutedTextColor
                                                palette.highlight: picker.accentColor
                                                palette.highlightedText: picker.tooltipTextColor
                                                text: picker.windowFilterText
                                                selectByMouse: true
                                                onTextEdited: {
                                                    picker.windowFilterText = text;
                                                    picker.refreshFilteredWindows();
                                                }
                                                Keys.onDownPressed: event => {
                                                    picker.moveWindowSelection(1);
                                                    event.accepted = true;
                                                }
                                                Keys.onUpPressed: event => {
                                                    picker.moveWindowSelection(-1);
                                                    event.accepted = true;
                                                }
                                                Keys.onEscapePressed: event => {
                                                    if (text.length > 0) {
                                                        clear();
                                                        picker.windowFilterText = "";
                                                        picker.refreshFilteredWindows();
                                                    } else {
                                                        picker.windowFilterActive = false;
                                                        windowList.forceActiveFocus();
                                                    }
                                                    event.accepted = true;
                                                }
                                                Keys.onReturnPressed: event => {
                                                    if (picker.selectedWindow())
                                                        picker.shareCurrent();
                                                    event.accepted = true;
                                                }
                                            }

                                            Text {
                                                color: picker.mutedTextColor
                                                text: picker.filteredWindowEntries.length + " of " + picker.windowEntries.length
                                            }
                                        }

                                        ListView {
                                            id: windowList
                                            readonly property real scrollGutter: windowScrollBar.visible ? windowScrollBar.width + 4 : 0
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                        clip: true
                                        spacing: 2
                                        model: picker.filteredWindowEntries
                                        activeFocusOnTab: true
                                        keyNavigationEnabled: true
                                        highlightMoveDuration: 80
                                        section.property: "sectionLabel"
                                        section.criteria: ViewSection.FullString
                                        section.delegate: Rectangle {
                                            required property string section
                                            width: windowList.width - windowList.scrollGutter
                                            height: 24
                                            color: picker.backgroundColor

                                            Text {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                color: picker.mutedTextColor
                                                elide: Text.ElideRight
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                text: section
                                            }
                                        }
                                        Keys.onReturnPressed: event => {
                                            picker.windowOrderingFrozen = true;
                                            if (picker.selectedWindow())
                                                picker.shareCurrent();
                                            event.accepted = true;
                                        }
                                        highlight: Rectangle {
                                            color: picker.selectedColor
                                            border.color: windowList.activeFocus ? picker.accentColor : picker.borderColor
                                            border.width: windowList.activeFocus ? 2 : 1
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
                                                    text: windowDelegate.modelData.className + ": " + windowDelegate.modelData.title
                                                }

                                                Text {
                                                    visible: !windowDelegate.modelData.matched
                                                    color: picker.mutedTextColor
                                                    font.pixelSize: 10
                                                    text: "No preview"
                                                }
                                            }

                                            MouseArea {
                                                id: windowMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    picker.windowOrderingFrozen = true;
                                                    windowList.currentIndex = windowDelegate.index;
                                                }
                                                onDoubleClicked: {
                                                    picker.windowOrderingFrozen = true;
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
                                                    color: picker.tooltipTextColor
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 3
                                                    wrapMode: Text.Wrap
                                                    text: windowToolTip.text
                                                }

                                                background: Rectangle {
                                                    color: picker.tooltipColor
                                                    border.color: picker.tooltipBorderColor
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

                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width - 32
                                            color: picker.mutedTextColor
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            visible: picker.filteredWindowEntries.length === 0
                                            text: picker.windowFilterText
                                                ? "No windows match this filter"
                                                : "No shareable windows\nTry Screen or Region"
                                        }

                                        ScrollBar.vertical: ScrollBar {
                                            id: windowScrollBar
                                            policy: ScrollBar.AsNeeded
                                            width: 8
                                        }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: previewFrame
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: picker.previewColor
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

                                    BusyIndicator {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -18
                                        width: 32
                                        height: 32
                                        running: visible
                                        visible: previewFrame.selection && preview.captureSource && !preview.hasContent
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: 22
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

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 62
                                        color: picker.metadataColor
                                        visible: previewFrame.selection !== null

                                        Column {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 2

                                            Text {
                                                width: parent.width
                                                color: picker.tooltipTextColor
                                                elide: Text.ElideRight
                                                font.weight: Font.DemiBold
                                                text: previewFrame.selection ? previewFrame.selection.className : ""
                                            }

                                            Text {
                                                width: parent.width
                                                color: "#c8cbd0"
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                                wrapMode: Text.Wrap
                                                text: previewFrame.selection ? previewFrame.selection.title : ""
                                            }
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

                                Text {
                                    Layout.fillWidth: true
                                    visible: picker.regionRecovery
                                    color: picker.mutedTextColor
                                    wrapMode: Text.WordWrap
                                    text: "Region selection was canceled. Choose again, repeat the last region, or use another tab."
                                }

                                Button {
                                    id: regionButton
                                    palette.button: picker.listColor
                                    palette.buttonText: picker.textColor
                                    palette.highlight: picker.accentColor
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 40
                                    enabled: picker.slurpAvailable
                                    text: picker.slurpAvailable ? "Select Region…" : "Select Region… (slurp is not installed)"
                                    onClicked: picker.selectRegion()
                                }

                                Button {
                                    palette.button: picker.listColor
                                    palette.buttonText: picker.textColor
                                    palette.highlight: picker.accentColor
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 40
                                    visible: picker.lastRegionAvailable()
                                    enabled: picker.lastRegionAvailable()
                                    text: picker.session.lastRegion
                                        ? "Repeat " + picker.session.lastRegion.output + " region — "
                                            + picker.session.lastRegion.width + "×" + picker.session.lastRegion.height
                                            + " at " + picker.session.lastRegion.x + "," + picker.session.lastRegion.y
                                        : "Repeat last region"
                                    onClicked: picker.repeatLastRegion()
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            CheckBox {
                id: restoreToken
                palette.buttonText: picker.textColor
                palette.windowText: picker.textColor
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

                Text {
                    color: picker.mutedTextColor
                    font.pixelSize: 11
                    text: tabs.currentIndex === 1
                        ? "↑↓ select   Enter share   / filter   Ctrl+1–3 tabs   Esc cancel"
                        : "↑↓ select   Enter share   Ctrl+1–3 tabs   Esc cancel"
                }

                Item { Layout.fillWidth: true }

                Button {
                    id: shareButton
                    palette.button: picker.listColor
                    palette.buttonText: picker.textColor
                    palette.highlight: picker.accentColor
                    text: "Share"
                    enabled: picker.shareEnabled()
                    highlighted: true
                    onClicked: picker.shareCurrent()
                }

                Button {
                    palette.button: picker.listColor
                    palette.buttonText: picker.textColor
                    text: "Cancel"
                    onClicked: picker.cancel()
                }
            }
        }
    }
}
