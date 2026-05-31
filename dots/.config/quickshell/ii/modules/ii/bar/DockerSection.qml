pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Docker section for ExpressiveResourcesPopup.
 * Material 3 Expressive design — no borders, no plain number grids,
 * uses chips, mini arc gauges, sparkline-style bars and ripple buttons.
 */
Item {
    id: root
    implicitWidth: 380
    implicitHeight: mainCol.implicitHeight

    // Uptime tick force-reactive update
    property int uptimeUpdateTick: 0
    Timer {
        interval: 1000
        running: root.visible && DockerService.dockerRunning
        repeat: true
        onTriggered: uptimeUpdateTick++
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    function stateColor(c) {
        if (c.isPaused)
            return Appearance.colors.colTertiary;
        if (c.isRunning)
            return Appearance.colors.colPrimary;
        return Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.38);
    }

    function stateLabel(c) {
        if (c.isPaused)
            return "Paused";
        if (c.isRunning)
            return "Running";
        return "Stopped";
    }

    function uptimeShort(startedAt) {
        if (!startedAt || startedAt === "0001-01-01T00:00:00Z")
            return "—";
        const ms = Date.now() - new Date(startedAt).getTime();
        if (ms < 0)
            return "—";
        const s = Math.floor(ms / 1000);
        if (s < 60)
            return s + "s";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h";
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        // ── Header row ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Docker icon + label block
            RowLayout {
                spacing: 10

                CustomIcon {
                    source: "docker.svg"
                    width: 36
                    height: 36
                    colorize: true
                    color: Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    spacing: -2
                    StyledText {
                        text: "Docker"
                        font.pixelSize: Appearance.font.pixelSize.normal + 2
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: DockerService.dockerAvailable ? DockerService.runningCount + " running" : (DockerService.dockerRunning ? "loading..." : "stopped")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.6
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Total Docker RAM usage pill
            Rectangle {
                visible: DockerService.dockerRunning && DockerService.totalMemoryMb > 0
                radius: Appearance.rounding.full
                color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.12)
                implicitHeight: 32
                implicitWidth: ramPillRow.implicitWidth + 24

                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                RowLayout {
                    id: ramPillRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "memory"
                        iconSize: 14
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: DockerService.totalMemoryMb >= 1024 ? (DockerService.totalMemoryMb / 1024).toFixed(1) + " GB" : Math.round(DockerService.totalMemoryMb) + " MB"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Service on/off toggle pill
            RippleButton {
                id: serviceToggle
                implicitWidth: serviceToggleRow.implicitWidth + 24
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: DockerService.dockerRunning ? Appearance.colors.colPrimary : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.12)
                colBackgroundHover: DockerService.dockerRunning ? Appearance.colors.colPrimaryHover : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.18)
                onClicked: DockerService.toggleDockerService(!DockerService.dockerRunning)

                Behavior on colBackground {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                RowLayout {
                    id: serviceToggleRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: DockerService.dockerRunning ? "power_settings_new" : "power_off"
                        iconSize: 14
                        color: DockerService.dockerRunning ? Appearance.m3colors.m3onPrimary : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.6)
                    }
                    StyledText {
                        text: DockerService.dockerRunning ? "On" : "Off"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: DockerService.dockerRunning ? Appearance.m3colors.m3onPrimary : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.6)
                    }
                }
            }
        }

        // ── Loading state ──────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: 80
            visible: DockerService.isLoading

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    id: spinnerIcon
                    Layout.alignment: Qt.AlignHCenter
                    text: "progress_activity"
                    iconSize: 24
                    color: Appearance.colors.colPrimary

                    RotationAnimator on rotation {
                        from: 0
                        to: 360
                        duration: 1000
                        running: DockerService.isLoading
                        loops: Animation.Infinite
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Fetching container states..."
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.6
                }
            }
        }

        // ── Empty / unavailable state ──────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: 90
            visible: !DockerService.isLoading && (!DockerService.dockerAvailable || DockerService.containers.length === 0)

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh
                border.width: 1
                border.color: Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.05)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    MaterialShape {
                        shapeString: "Cookie6Sided"
                        implicitSize: 42
                        color: DockerService.dockerRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: DockerService.dockerRunning ? "deployed_code" : "cloud_off"
                            iconSize: 22
                            color: DockerService.dockerRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: DockerService.dockerRunning ? "No active containers" : "Docker service offline"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: DockerService.dockerRunning ? "Spin up some containers to manage them here." : "Click the power button to start the system daemon."
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.5
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // ── Scrollable Container cards area (Extreme Conditions safe) ────────
        ListView {
            id: containersListView
            visible: !DockerService.isLoading && DockerService.dockerAvailable && DockerService.containers.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            clip: true

            // Restrict height to exactly 3 items (196px) when count > 3
            implicitHeight: {
                let count = DockerService.containers.length;
                if (count <= 3) {
                    return count > 0 ? (count * 60 + (count - 1) * 8) : 0;
                } else {
                    // 3 full items: 3 * 60px + 2 * 8px spacing = 196px
                    return 196;
                }
            }

            model: DockerService.containers
            spacing: 8

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                active: containersListView.moving || containersListView.hovered
            }

            delegate: ContainerCard {
                required property var modelData
                required property int index
                width: containersListView.width
                containerData: modelData
            }

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                }
            }
        }
    }

    // ── Container card component ───────────────────────────────────────────
    component ContainerCard: Item {
        id: card
        property var containerData: null
        property bool actionPanelOpen: false

        implicitWidth: parent ? parent.width : 360
        implicitHeight: 60

        // ── List of action items for this container ────────────────────────
        property var allActionItems: {
            let items = [];
            // Collapse Button (arrow back)
            items.push({
                icon: "arrow_back",
                isCollapse: true,
                tooltip: "Collapse actions",
                color: Appearance.colors.colOnSurfaceVariant,
                execute: () => {
                    card.actionPanelOpen = false;
                }
            });
            if (card.containerData?.isRunning) {
                // Stop Container
                items.push({
                    icon: "stop",
                    tooltip: "Stop container",
                    color: Appearance.colors.colError,
                    execute: () => {
                        DockerService.containerAction(card.containerData.id, "stop");
                    }
                });
                // Shell
                items.push({
                    icon: "terminal",
                    isSecondaryContainer: true,
                    tooltip: "Open shell",
                    color: Appearance.colors.colOnSecondaryContainer,
                    execute: () => {
                        DockerService.openShell(card.containerData.id);
                    }
                });
            } else {
                // Start Container
                items.push({
                    icon: "play_arrow",
                    tooltip: "Start container",
                    color: Appearance.colors.colSuccess,
                    execute: () => {
                        DockerService.containerAction(card.containerData.id, "start");
                    }
                });
            }
            // Logs
            items.push({
                icon: "description",
                isSecondaryContainer: true,
                tooltip: "Open logs",
                color: Appearance.colors.colOnSecondaryContainer,
                execute: () => {
                    DockerService.openLogs(card.containerData.id);
                }
            });
            if (card.containerData?.ports?.length > 0) {
                items.push({
                    icon: "open_in_new",
                    isSecondaryContainer: true,
                    tooltip: "Open in browser (http://localhost:" + card.containerData.ports[0].hostPort + ")",
                    color: Appearance.colors.colOnSecondaryContainer,
                    execute: () => {
                        DockerService.openInBrowser(card.containerData.ports[0].hostPort);
                    }
                });
            }
            if (card.containerData?.isRunning) {
                // RAM Gauge quick button (moved to the end)
                items.push({
                    isRamGauge: true,
                    tooltip: "RAM: " + (card.containerData?.memMb >= 1024 ? (card.containerData.memMb / 1024).toFixed(2) + " GB" : (card.containerData?.memMb ?? 0).toFixed(1) + " MB"),
                    memMb: card.containerData?.memMb ?? 0,
                    execute: () => {}
                });
            }
            return items;
        }

        Item {
            id: cardWrapper
            anchors.fill: parent
            clip: true

            Row {
                id: slideRow
                anchors.fill: parent
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                // ── Main Card ────────────────────────────────────────────────
                Rectangle {
                    id: itemRect
                    width: card.actionPanelOpen ? 185 : cardWrapper.width
                    height: 60
                    radius: Appearance.rounding.large
                    anchors.verticalCenter: parent.verticalCenter
                    color: card.containerData?.isRunning ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh

                    Behavior on width {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    // Click whole card to collapse when open
                    MouseArea {
                        anchors.fill: parent
                        visible: card.actionPanelOpen
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.actionPanelOpen = false
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        // Container Icon Chip - Uses official Docker icon for visual premium excellence!
                        MaterialShape {
                            shapeString: "Cookie9Sided"
                            implicitSize: 32
                            color: card.containerData?.isRunning ? Appearance.colors.colPrimaryContainer : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.08)

                            CustomIcon {
                                anchors.centerIn: parent
                                source: "docker.svg"
                                width: 16
                                height: 16
                                colorize: true
                                color: card.containerData?.isRunning ? Appearance.colors.colOnPrimaryContainer : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.38)
                            }
                        }

                        // Text Content Column
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true

                            RowLayout {
                                spacing: 4

                                StyledText {
                                    text: card.containerData?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: card.containerData?.isRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                // Uptime pill (hidden when action panel is open)
                                Rectangle {
                                    visible: (card.containerData?.isRunning ?? false) && !card.actionPanelOpen
                                    radius: Appearance.rounding.full
                                    color: card.containerData?.isRunning ? Qt.rgba(Appearance.m3colors.m3onPrimary.r, Appearance.m3colors.m3onPrimary.g, Appearance.m3colors.m3onPrimary.b, 0.15) : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.07)
                                    implicitHeight: 16
                                    implicitWidth: uptimeTextRow.implicitWidth + 8

                                    RowLayout {
                                        id: uptimeTextRow
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            text: "schedule"
                                            iconSize: 8
                                            color: card.containerData?.isRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                            opacity: 0.8
                                        }
                                        StyledText {
                                            id: uptimeText
                                            text: (root.uptimeUpdateTick, root.uptimeShort(card.containerData?.startedAt))
                                            font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                            font.weight: Font.Bold
                                            color: card.containerData?.isRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                            opacity: 0.9
                                        }
                                    }
                                }
                            }

                            // Sub-Chips row (hidden when action panel is open)
                            RowLayout {
                                spacing: 4
                                visible: !card.actionPanelOpen

                                // Image name chip
                                Rectangle {
                                    radius: Appearance.rounding.full
                                    color: card.containerData?.isRunning ? Qt.rgba(Appearance.m3colors.m3onPrimary.r, Appearance.m3colors.m3onPrimary.g, Appearance.m3colors.m3onPrimary.b, 0.12) : Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.07)
                                    implicitHeight: 14
                                    implicitWidth: imageText.implicitWidth + 10
                                    Layout.maximumWidth: 90

                                    StyledText {
                                        id: imageText
                                        anchors.centerIn: parent
                                        text: card.containerData?.image ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                        color: card.containerData?.isRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                                        opacity: 0.8
                                        elide: Text.ElideRight
                                        width: parent.width - 10
                                    }
                                }

                                // Port chip
                                Repeater {
                                    model: (card.containerData?.ports ?? []).slice(0, 2)
                                    delegate: MouseArea {
                                        id: portMouseArea
                                        required property var modelData
                                        hoverEnabled: true
                                        implicitHeight: 14
                                        implicitWidth: portChipText.implicitWidth + 12
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            DockerService.openInBrowser(modelData.hostPort);
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Appearance.rounding.full
                                            color: portMouseArea.containsMouse ? (card.containerData?.isRunning ? Qt.rgba(Appearance.m3colors.m3onPrimary.r, Appearance.m3colors.m3onPrimary.g, Appearance.m3colors.m3onPrimary.b, 0.22) : Appearance.colors.colPrimaryContainerHover) : (card.containerData?.isRunning ? Qt.rgba(Appearance.m3colors.m3onPrimary.r, Appearance.m3colors.m3onPrimary.g, Appearance.m3colors.m3onPrimary.b, 0.12) : Appearance.colors.colPrimaryContainer)

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 100
                                                }
                                            }

                                            StyledText {
                                                id: portChipText
                                                anchors.centerIn: parent
                                                text: modelData.hostPort
                                                font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                                font.weight: Font.Bold
                                                color: card.containerData?.isRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnPrimaryContainer
                                            }
                                        }

                                        StyledToolTip {
                                            alternativeVisibleCondition: portMouseArea.containsMouse
                                            extraVisibleCondition: false
                                            text: "Open http://localhost:" + modelData.hostPort + " in browser"
                                        }
                                    }
                                }
                            }
                        }

                        // Right-Arrow Button to open panel (only when NOT open)
                        RippleButton {
                            visible: !card.actionPanelOpen
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: card.containerData?.isRunning ? Qt.rgba(Appearance.m3colors.m3onPrimary.r, Appearance.m3colors.m3onPrimary.g, Appearance.m3colors.m3onPrimary.b, 0.15) : Appearance.colors.colPrimaryContainer
                            colBackgroundHover: card.containerData?.isRunning ? Qt.rgba(Appearance.m3colors.m3onPrimary.r, Appearance.m3colors.m3onPrimary.g, Appearance.m3colors.m3onPrimary.b, 0.25) : Appearance.colors.colPrimaryContainerHover
                            onClicked: card.actionPanelOpen = true

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_forward"
                                iconSize: 16
                                color: card.containerData?.isRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnPrimaryContainer
                            }

                            StyledToolTip {
                                text: "Manage actions"
                            }
                        }
                    }
                }

                // ── Circular Action Buttons Scrollable Drawer ────────────────
                Flickable {
                    id: actionsFlickable
                    visible: card.actionPanelOpen || itemRect.width < cardWrapper.width
                    height: 60
                    width: Math.max(0, cardWrapper.width - itemRect.width - slideRow.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    contentWidth: buttonsRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => {
                            var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                            actionsFlickable.contentX = Math.max(0, Math.min(actionsFlickable.contentWidth - actionsFlickable.width, actionsFlickable.contentX - delta * 0.5));
                            wheel.accepted = true;
                        }
                    }

                    Row {
                        id: buttonsRow
                        spacing: 8
                        height: 60
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            id: actionRepeater
                            model: card.allActionItems

                            delegate: RippleButton {
                                required property var modelData
                                required property int index

                                implicitWidth: 60
                                implicitHeight: 60
                                anchors.verticalCenter: parent.verticalCenter
                                buttonRadius: Appearance.rounding.full

                                colBackground: modelData.isCollapse ? Appearance.colors.colSurfaceContainerHighest : (modelData.isRamGauge ? Appearance.colors.colTertiaryContainer : (modelData.isSecondaryContainer ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary))
                                colBackgroundHover: modelData.isCollapse ? Appearance.colors.colSurfaceContainerLowest : (modelData.isRamGauge ? ColorUtils.transparentize(Appearance.colors.colTertiary, 0.2) : (modelData.isSecondaryContainer ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryHover))

                                onClicked: modelData.execute()

                                // Material symbol for generic actions
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !modelData.isRamGauge
                                    text: modelData.icon || ""
                                    iconSize: 24
                                    color: modelData.isCollapse ? Appearance.colors.colOnSurface : (modelData.isSecondaryContainer ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onPrimary)
                                }

                                // Custom circular RAM Usage Gauge quick button
                                Loader {
                                    anchors.centerIn: parent
                                    active: modelData.isRamGauge || false
                                    visible: active
                                    sourceComponent: ClippedFilledCircularProgress {
                                        id: ramGaugeProgress
                                        implicitSize: 60
                                        lineWidth: 4
                                        value: {
                                            const totalSysMb = (ResourceUsage.memoryTotal || 16777216) / 1024;
                                            return Math.min(1.0, Math.max(0.005, (modelData.memMb || 0) / totalSysMb));
                                        }
                                        colPrimary: Appearance.colors.colTertiary
                                        colSecondary: Qt.rgba(Appearance.colors.colTertiary.r, Appearance.colors.colTertiary.g, Appearance.colors.colTertiary.b, 0.15)
                                        accountForLightBleeding: false

                                        Item {
                                            anchors.centerIn: parent
                                            width: ramGaugeProgress.implicitSize
                                            height: ramGaugeProgress.implicitSize

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: {
                                                    const m = modelData.memMb || 0;
                                                    if (m < 0.1)
                                                        return Math.round(m * 1024) + "K";
                                                    if (m < 1.0)
                                                        return (m * 1024).toFixed(0) + "K";
                                                    if (m < 10.0)
                                                        return m.toFixed(1) + "M";
                                                    return Math.round(m) + "M";
                                                }
                                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                                font.weight: Font.Bold
                                                color: Appearance.colors.colOnTertiaryContainer
                                            }
                                        }
                                    }
                                }

                                // Tooltips for all quick actions to describe behavior
                                StyledToolTip {
                                    text: modelData.tooltip || ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
