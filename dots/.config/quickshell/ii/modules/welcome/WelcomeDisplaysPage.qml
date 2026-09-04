import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.hyprland
import qs.services

Item {
    id: root

    MonitorConfigOption {
        id: monitorConfig
    }

    readonly property var selectedMonitor: monitorConfig.monitors.length > 0
        ? monitorConfig.monitors[arrangement.selectedIndex]
        : null

    function updateSelected(changes) {
        if (!root.selectedMonitor)
            return;
        monitorConfig.updateMonitor(arrangement.selectedIndex, changes);
        monitorConfig.applyAndSave(arrangement.selectedIndex);
    }

    function moveSelectedMonitor(deltaX, deltaY) {
        const index = arrangement.selectedIndex;
        if (index < 0 || index >= monitorConfig.monitors.length)
            return;

        arrangement.nudgeOffset = Qt.point(deltaX === 0 ? 0 : (deltaX > 0 ? 1 : -1),
            deltaY === 0 ? 0 : (deltaY > 0 ? 1 : -1));
        arrangement.nudgeToken += 1;

        const monitor = monitorConfig.monitors[index];
        if (!monitor || monitor.disabled)
            return;

        const nextX = (monitor.x || 0) + deltaX;
        const nextY = (monitor.y || 0) + deltaY;
        const normalized = arrangement.computeNormalized(monitorConfig.monitors, index, nextX, nextY);
        if (!arrangement.checkOverlap(normalized, index))
            arrangement.commitPosition(index, nextX, nextY);
    }

    property bool nextButtonHovered: false

    /**
     * The page names each screen on the screen itself for a few seconds on
     * arrival, and again on request. Automatic the first time because the
     * question — which rectangle is the panel in front of me — is asked by the
     * page before the reader knows there is a button that answers it.
     */
    Timer {
        id: identifyTimer
        interval: 3200
        repeat: false
        onTriggered: GlobalStates.displayIdentifyActive = false
    }

    function identify(): void {
        GlobalStates.displayIdentifyActive = true;
        identifyTimer.restart();
    }

    Component.onCompleted: root.identify()
    Component.onDestruction: {
        identifyTimer.stop();
        GlobalStates.displayIdentifyActive = false;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.small

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignHCenter
            visible: monitorConfig.monitors.length > 1
            implicitHeight: Appearance.rounding.verylarge + Appearance.rounding.verysmall
            centerContent: true
            materialIcon: "pin"
            mainText: Translation.tr("Identify displays")
            textPixelSize: Appearance.font.pixelSize.small
            iconPixelSize: Appearance.font.pixelSize.large
            buttonRadius: Appearance.rounding.full
            colText: Appearance.colors.colOnSecondaryContainer
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.identify()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            Layout.minimumHeight: 220
            spacing: Appearance.rounding.small

            MonitorArrangement {
                id: arrangement

                Layout.fillWidth: true
                Layout.fillHeight: true
                // Qt Quick Layouts treat preferredWidth as pixels, not a
                // flex ratio. Keep enough room for the canvas and let the
                // right-hand panel use its own bounded column.
                Layout.minimumWidth: Appearance.rounding.large * 18
                Layout.preferredWidth: Appearance.rounding.large * 29
                monitorConfig: monitorConfig
                expressive: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: Appearance.rounding.large * 13
                Layout.preferredWidth: Appearance.rounding.large * 14
                Layout.maximumWidth: Appearance.rounding.large * 16
                Layout.alignment: Qt.AlignTop
                spacing: Appearance.rounding.unsharpenmore

                Rectangle {
                    id: selectedMonitorCard

                    Layout.fillWidth: true
                    implicitHeight: selectedMonitorCol.implicitHeight + Appearance.rounding.large
                    color: Appearance.colors.colLayer2Base
                    radius: Appearance.rounding.large

                    RowLayout {
                        id: selectedMonitorCol
                        anchors.fill: parent
                        anchors.margins: Appearance.rounding.normal
                        spacing: Appearance.rounding.unsharpenmore

                        MaterialShapeWrappedMaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: "monitor"
                            shape: MaterialShape.Shape.Cookie7Sided
                            iconSize: Appearance.font.pixelSize.large
                            padding: Appearance.rounding.small
                            fill: 1
                            color: Appearance.colors.colSecondaryContainer
                            colSymbol: Appearance.colors.colOnSecondaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Selected Monitor")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.selectedMonitor
                                    ? (root.selectedMonitor.description || root.selectedMonitor.name || Translation.tr("None"))
                                    : Translation.tr("None")
                                color: Appearance.colors.colOnLayer1
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Bold
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: !!root.selectedMonitor
                                text: root.selectedMonitor
                                    ? (root.selectedMonitor.currentMode
                                        || ((root.selectedMonitor.width || 0) + " × " + (root.selectedMonitor.height || 0)))
                                    : ""
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                            }
                        }

                        Pill {
                            id: primaryPill
                            visible: !!root.selectedMonitor && !!root.selectedMonitor.primary
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: primaryPillLabel.implicitWidth + Appearance.rounding.normal
                            implicitHeight: Appearance.font.pixelSize.small + Appearance.rounding.small
                            color: Appearance.colors.colPrimaryContainer

                            StyledText {
                                id: primaryPillLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Primary")
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                            }
                        }
                    }
                }

                Rectangle {
                    id: positionControlsCard

                    Layout.fillWidth: true
                    color: Appearance.colors.colLayer2Base
                    radius: Appearance.rounding.large
                    implicitHeight: manualPositionRow.implicitHeight + Appearance.rounding.large

                    RowLayout {
                        id: manualPositionRow
                        anchors.centerIn: parent
                        spacing: Appearance.rounding.unsharpenmore

                        RippleButton {
                            enabled: !!root.selectedMonitor && !root.selectedMonitor.disabled
                            implicitWidth: Appearance.rounding.large + Appearance.rounding.small
                            implicitHeight: Appearance.rounding.large + Appearance.rounding.small
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_back"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            onClicked: root.moveSelectedMonitor(-100, 0)
                        }

                        RippleButton {
                            enabled: !!root.selectedMonitor && !root.selectedMonitor.disabled
                            implicitWidth: Appearance.rounding.large + Appearance.rounding.small
                            implicitHeight: Appearance.rounding.large + Appearance.rounding.small
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_forward"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            onClicked: root.moveSelectedMonitor(100, 0)
                        }

                        RippleButton {
                            enabled: !!root.selectedMonitor && !root.selectedMonitor.disabled
                            implicitWidth: Appearance.rounding.large + Appearance.rounding.small
                            implicitHeight: Appearance.rounding.large + Appearance.rounding.small
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_upward"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            onClicked: root.moveSelectedMonitor(0, -100)
                        }

                        RippleButton {
                            enabled: !!root.selectedMonitor && !root.selectedMonitor.disabled
                            implicitWidth: Appearance.rounding.large + Appearance.rounding.small
                            implicitHeight: Appearance.rounding.large + Appearance.rounding.small
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_downward"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            onClicked: root.moveSelectedMonitor(0, 100)
                        }
                    }
                }
            }
        }

        ContentSection {
            Layout.fillWidth: true
            visible: !!root.selectedMonitor
            icon: "settings"
            title: Translation.tr("Monitor Settings")

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.rounding.unsharpenmore

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: Appearance.rounding.large * 18
                    title: Translation.tr("Resolution & Refresh Rate")
                    icon: "aspect_ratio"

                    StyledComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "aspect_ratio"
                        model: root.selectedMonitor ? (root.selectedMonitor.availableModes || []).map(mode => ({
                            display: mode,
                            value: mode
                        })) : []
                        textRole: "display"
                        currentIndex: root.selectedMonitor
                            ? (root.selectedMonitor.availableModes || []).indexOf(root.selectedMonitor.currentMode || "")
                            : -1
                        onActivated: index => {
                            if (!root.selectedMonitor)
                                return;
                            const mode = root.selectedMonitor.availableModes[index];
                            const parts = mode.match(/(\d+)x(\d+)@([\d.]+)Hz/);
                            if (parts) {
                                root.updateSelected({
                                    currentMode: mode,
                                    width: parseInt(parts[1]),
                                    height: parseInt(parts[2]),
                                    refreshRate: parseFloat(parts[3])
                                });
                            }
                        }
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: Appearance.rounding.large * 18
                    title: Translation.tr("Orientation")
                    icon: "screen_rotation_alt"

                    ConfigSelectionArray {
                        Layout.fillWidth: true
                        currentValue: root.selectedMonitor ? (root.selectedMonitor.transform || 0) : 0
                        options: [
                            { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: 0 },
                            { displayName: "90°", icon: "rotate_90_degrees_cw", value: 1 },
                            { displayName: "180°", icon: "screen_rotation", value: 2 },
                            { displayName: "270°", icon: "rotate_90_degrees_ccw", value: 3 }
                        ]
                        onSelected: value => root.updateSelected({ transform: Number(value) })
                    }
                }
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "zoom_in"
                text: Translation.tr("Scale") + ` (${(value || 1.0).toFixed(2)}x)`
                value: root.selectedMonitor ? (root.selectedMonitor.scale || 1.0) : 1.0
                from: 0.5
                to: 3.0
                stepSize: 0.25
                snapMode: Slider.SnapAlways
                stopIndicatorValues: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0]
                usePercentTooltip: false
                tooltipContent: (value || 1.0).toFixed(2) + "x"
                onValueChanged: {
                    if (!root.selectedMonitor)
                        return;
                    const currentValue = root.selectedMonitor.scale || 1.0;
                    if (Math.abs(value - currentValue) > 0.01)
                        root.updateSelected({ scale: value });
                }
            }

        }
    }
}
