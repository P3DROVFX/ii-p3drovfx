pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "at_a_glance"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "at_a_glance")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options.background.widgets.at_a_glance
    readonly property int widthCells: Math.max(2, Math.min(4, options.widthCells ?? 3))
    readonly property real contentScale: (options.widgetSize ?? 100) / 100.0
    readonly property bool dualColumn: (options.dualColumnMode ?? false) && targetsList.length > 1

    implicitWidth:  (dualColumn ? 480 : (widthCells === 2 ? 250 : (widthCells === 4 ? 450 : 350))) * contentScale
    implicitHeight: 76 * contentScale

    readonly property var targetsList: AtAGlanceService.activeTargetsList
    property int selectedTargetIndex: 0

    onTargetsListChanged: {
        if (selectedTargetIndex >= targetsList.length)
            selectedTargetIndex = 0;
    }

    readonly property string currentServiceKey: targetsList[selectedTargetIndex] || "fallback"
    readonly property var currentData: AtAGlanceService.getTargetData(currentServiceKey)

    readonly property string dualServiceKey: targetsList[(selectedTargetIndex + 1) % targetsList.length] || "fallback"
    readonly property var dualData: AtAGlanceService.getTargetData(dualServiceKey)

    Behavior on implicitWidth {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    function triggerAction(serviceName) {
        if (serviceName === "media") {
            if (AtAGlanceService.player) AtAGlanceService.player.togglePlaying();
        } else if (serviceName === "calendar") {
            calendarIpc.running = true;
        } else if (serviceName === "todo") {
            todoIpc.running = true;
        } else if (serviceName === "email") {
            emailIpc.running = true;
        } else if (serviceName === "fallback") {
            Weather.getData(true);
        }
    }

    function handleDroppedFiles(urls) {
        const paths = [];
        for (let i = 0; i < urls.length; i++) {
            let path = String(urls[i]);
            if (path.startsWith("file://")) path = path.substring(7);
            paths.push(decodeURIComponent(path));
        }
        if (paths.length === 0) return;

        if (LocalSend.available) {
            LocalSend.sendFiles(paths);
        } else if (KdeConnectService.available && KdeConnectService.activeDevice) {
            for (let j = 0; j < paths.length; j++) {
                KdeConnectService.shareFile(KdeConnectService.activeDeviceId, paths[j]);
            }
        }
    }

    Process {
        id: calendarIpc
        command: ["qs", "ipc", "-c", "ii", "call", "cheatsheet", "toggle"]
    }

    Process {
        id: todoIpc
        command: ["qs", "ipc", "-c", "ii", "call", "sidebarDashboard", "openTab", "todo"]
    }

    Process {
        id: emailIpc
        command: ["qs", "ipc", "-c", "ii", "call", "cheatsheet", "toggle"]
    }

    Item {
        id: container
        anchors.fill: parent

        // ── DropArea for File Drag-and-Drop ──────────────────────────────────
        DropArea {
            id: dropArea
            anchors.fill: parent
            keys: ["text/uri-list"]

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(1, 1, 1, 0.12)
                radius: Appearance.rounding.normal
                visible: dropArea.containsDrag
                border.width: 0

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Drop files to share via LocalSend / KDE Connect")
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Math.round(14 * root.contentScale)
                    font.weight: Font.Bold
                }
            }

            onDropped: drop => {
                if (drop.hasUrls) {
                    root.handleDroppedFiles(drop.urls);
                }
            }
        }

        // ── Transparent Background Click & Drag Handler ─────────────────────────
        MouseArea {
            id: dragAndClickHandler
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            propagateComposedEvents: true

            property real pressX: 0
            property real pressY: 0

            onPressed: mouse => {
                pressX = mouse.x;
                pressY = mouse.y;
                mouse.accepted = false; // Pass press event to AbstractBackgroundWidget so desktop drag works!
            }

            onClicked: mouse => {
                const dx = Math.abs(mouse.x - pressX);
                const dy = Math.abs(mouse.y - pressY);
                if (dx < 6 && dy < 6) {
                    root.triggerAction(root.currentServiceKey);
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8 * root.contentScale
            anchors.rightMargin: 8 * root.contentScale
            anchors.topMargin: 4 * root.contentScale
            anchors.bottomMargin: 4 * root.contentScale
            spacing: 16 * root.contentScale

            // ── COLUMN 1 (Primary Target) ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12 * root.contentScale

                // Media Cover Art Thumbnail (Rounded Corners)
                Item {
                    id: coverArtBox1
                    visible: root.currentData.service === "media" && root.currentData.artUrl !== ""
                    implicitWidth:  46 * root.contentScale
                    implicitHeight: 46 * root.contentScale
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: Qt.rgba(0, 0, 0, 0.3)
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.currentData.artUrl
                            fillMode: Image.PreserveAspectCrop
                            mipmap: true
                        }
                    }
                }

                // Text Content
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2 * root.contentScale

                    // Line 1: Headline
                    Text {
                        Layout.fillWidth: true
                        text: root.currentData.title
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.main
                        font.pixelSize: Math.round(19 * root.contentScale)
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    // Line 2: Subtitle / Icon
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6 * root.contentScale

                        Item {
                            implicitWidth:  18 * root.contentScale
                            implicitHeight: 18 * root.contentScale
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                anchors.fill: parent
                                visible: root.currentData.service === "fallback" && AtAGlanceService.weatherAvailable
                                source: WeatherIcons.getWeatherIcon(AtAGlanceService.weatherCode, false)
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !(root.currentData.service === "fallback" && AtAGlanceService.weatherAvailable)
                                text: root.currentData.icon
                                iconSize: Math.round(16 * root.contentScale)
                                color: Appearance.colors.colOnLayer0
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.currentData.subtitle
                            color: Appearance.colors.colOnLayer0
                            font.family: Appearance.font.family.main
                            font.pixelSize: Math.round(15 * root.contentScale)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            opacity: 0.90
                        }
                    }
                }
            }

            // ── COLUMN 2 (Secondary Target in Dual-Column Mode) ──────────────
            RowLayout {
                visible: root.dualColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12 * root.contentScale

                // Divider line between columns
                Rectangle {
                    implicitWidth: 1
                    implicitHeight: 36 * root.contentScale
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.25
                    Layout.alignment: Qt.AlignVCenter
                }

                // Text Content Column 2
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2 * root.contentScale

                    Text {
                        Layout.fillWidth: true
                        text: root.dualData.title
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.main
                        font.pixelSize: Math.round(19 * root.contentScale)
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6 * root.contentScale

                        MaterialSymbol {
                            text: root.dualData.icon
                            iconSize: Math.round(16 * root.contentScale)
                            color: Appearance.colors.colOnLayer0
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.dualData.subtitle
                            color: Appearance.colors.colOnLayer0
                            font.family: Appearance.font.family.main
                            font.pixelSize: Math.round(15 * root.contentScale)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            opacity: 0.90
                        }
                    }
                }
            }

            // ── Manual Target Switcher Buttons (Bottom Right) ─────────────────
            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                spacing: 2 * root.contentScale
                visible: root.targetsList.length > 1

                RippleButton {
                    implicitWidth:  24 * root.contentScale
                    implicitHeight: 24 * root.contentScale
                    topLeftRadius:    Appearance.rounding.full
                    topRightRadius:   Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius:Appearance.rounding.full
                    colBackground:      "transparent"
                    colBackgroundHover: Qt.rgba(1, 1, 1, 0.12)
                    colRipple:          Qt.rgba(1, 1, 1, 0.24)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: Math.round(16 * root.contentScale)
                        color: Appearance.colors.colOnLayer0
                    }

                    onClicked: {
                        root.selectedTargetIndex = (root.selectedTargetIndex - 1 + root.targetsList.length) % root.targetsList.length;
                    }
                }

                RippleButton {
                    implicitWidth:  24 * root.contentScale
                    implicitHeight: 24 * root.contentScale
                    topLeftRadius:    Appearance.rounding.full
                    topRightRadius:   Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius:Appearance.rounding.full
                    colBackground:      "transparent"
                    colBackgroundHover: Qt.rgba(1, 1, 1, 0.12)
                    colRipple:          Qt.rgba(1, 1, 1, 0.24)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: Math.round(16 * root.contentScale)
                        color: Appearance.colors.colOnLayer0
                    }

                    onClicked: {
                        root.selectedTargetIndex = (root.selectedTargetIndex + 1) % root.targetsList.length;
                    }
                }
            }
        }
    }
}
