import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Main pane: the power profile (the same one the Power Profile quick toggle cycles) as a
 * connected button group of tall segments, and under it the thermals strip that opens the
 * fan / turbo / TCC sub-page (`thermalsRequested`).
 */
Rectangle {
    id: root

    signal thermalsRequested()
    signal frameworkRequested()

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: content.implicitHeight + 40

    readonly property var modes: {
        const list = [
            { "profile": PowerProfile.PowerSaver, "symbol": "energy_savings_leaf", "shape": MaterialShape.Shape.Clover4Leaf,
              "label": Translation.tr("Saver"), "caption": Translation.tr("Longest battery"),
              "about": Translation.tr("Power Saver · slower, cooler, the longest battery life") },
            { "profile": PowerProfile.Balanced, "symbol": "airwave", "shape": MaterialShape.Shape.Cookie9Sided,
              "label": Translation.tr("Balanced"), "caption": Translation.tr("Speed when needed"),
              "about": Translation.tr("Balanced · full speed on demand, quiet when idle") }
        ];
        if (PowerProfiles.hasPerformanceProfile)
            list.push({ "profile": PowerProfile.Performance, "symbol": "local_fire_department", "shape": MaterialShape.Shape.SoftBurst,
                        "label": Translation.tr("Performance"), "caption": Translation.tr("Maximum speed"),
                        "about": Translation.tr("Performance · highest clocks and fans, more heat and drain") });
        return list;
    }
    property int hoveredIndex: -1
    readonly property var current: root.modes.find(m => m.profile === PowerProfiles.profile) ?? root.modes[1]

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 16

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                text: "speed"
                iconSize: 24
                padding: 12
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("Power mode")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.hoveredIndex >= 0 ? root.modes[root.hoveredIndex].about : root.current.about
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // the connected group
        RowLayout {
            Layout.fillWidth: true
            spacing: 3

            Repeater {
                model: root.modes
                delegate: RippleButton {
                    id: segment
                    required property var modelData
                    required property int index
                    readonly property bool first: index === 0
                    readonly property bool last: index === root.modes.length - 1
                    readonly property bool currentMode: PowerProfiles.profile === modelData.profile
                    readonly property real outer: Appearance.rounding.verylarge
                    property real inner: segment.currentMode ? segment.outer : Appearance.rounding.verysmall
                    Behavior on inner { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
                    readonly property color colContent: segment.currentMode ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 112
                    topLeftRadius: segment.first ? segment.outer : segment.inner
                    bottomLeftRadius: segment.first ? segment.outer : segment.inner
                    topRightRadius: segment.last ? segment.outer : segment.inner
                    bottomRightRadius: segment.last ? segment.outer : segment.inner

                    toggled: segment.currentMode
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: PowerProfiles.profile = modelData.profile
                    onHoveredChanged: root.hoveredIndex = hovered ? index : (root.hoveredIndex === index ? -1 : root.hoveredIndex)

                    contentItem: Item {
                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16
                            anchors.rightMargin: 12
                            spacing: 6

                            MaterialShapeWrappedMaterialSymbol {
                                text: segment.modelData.symbol
                                iconSize: 22
                                padding: 8
                                fill: segment.currentMode ? 1 : 0
                                shape: segment.currentMode ? segment.modelData.shape : MaterialShape.Shape.Circle
                                color: segment.currentMode ? Appearance.colors.colOnPrimary : ColorUtils.applyAlpha(Appearance.colors.colOnSecondaryContainer, 0.1)
                                colSymbol: segment.currentMode ? Appearance.colors.colPrimary : segment.colContent
                                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: segment.modelData.label
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.large
                                color: segment.colContent
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: segment.width >= 130
                                text: segment.modelData.caption
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: segment.colContent
                                opacity: 0.8
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // thermals strip → fan / turbo / TCC sub-page
        RippleButton {
            id: thermals
            Layout.fillWidth: true
            implicitHeight: 64
            buttonRadius: Appearance.rounding.large
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.thermalsRequested()

            readonly property string detail: {
                if (!FanControl.ready)
                    return Translation.tr("Fan curve, turbo boost and TCC offset");
                const parts = [];
                if (FanControl.hottest > 0)
                    parts.push(`${Math.round(FanControl.hottest)} °C`);
                const fan = FanControl.fans[0];
                if (fan)
                    parts.push(Translation.tr("%1 RPM").arg(fan.rpm));
                parts.push(FanControl.daemonRunning && FanControl.config.enabled ? Translation.tr("Custom curve") : Translation.tr("Firmware curve"));
                if (FanControl.turboAvailable && !FanControl.turboEnabled)
                    parts.push(Translation.tr("Turbo off"));
                return parts.join(" · ");
            }

            contentItem: Item {
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 16
                    spacing: 12

                    MaterialShapeWrappedMaterialSymbol {
                        text: "mode_fan"
                        iconSize: 20
                        padding: 9
                        shape: thermals.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie7Sided
                        color: Appearance.colors.colTertiaryContainer
                        colSymbol: Appearance.colors.colOnTertiaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Thermals & fans")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: thermals.detail
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        // Framework Laptop strip → charge limit, fingerprint light, firmware (only on a Framework)
        RippleButton {
            id: framework
            Layout.fillWidth: true
            visible: FanControl.isFramework
            implicitHeight: 64
            buttonRadius: Appearance.rounding.large
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.frameworkRequested()

            readonly property string detail: {
                if (!FanControl.frameworkReady)
                    return Translation.tr("Setup needed");
                const fw = FanControl.frameworkStatus;
                const parts = [];
                if (fw?.chargeLimit)
                    parts.push(fw.chargeLimit < 100 ? Translation.tr("Charges to %1 %").arg(fw.chargeLimit) : Translation.tr("Charges to 100 %"));
                if (fw?.privacy && (!fw.privacy.microphone || !fw.privacy.camera))
                    parts.push(Translation.tr("Privacy slider on"));
                return parts.length > 0 ? parts.join(" · ") : Translation.tr("Charge limit, fingerprint light and firmware");
            }

            contentItem: Item {
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 16
                    spacing: 12

                    MaterialShapeWrappedMaterialSymbol {
                        text: "laptop"
                        iconSize: 20
                        padding: 9
                        shape: framework.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie7Sided
                        color: Appearance.colors.colSecondaryContainer
                        colSymbol: Appearance.colors.colOnSecondaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Framework Laptop")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: framework.detail
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: FanControl.frameworkReady ? Appearance.colors.colSubtext : Appearance.colors.colError
                            elide: Text.ElideRight
                        }
                    }
                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }
}
