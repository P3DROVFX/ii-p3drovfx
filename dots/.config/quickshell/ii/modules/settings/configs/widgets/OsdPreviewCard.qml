import QtQuick
import QtQuick.Layouts
import "../../../.."
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.onScreenDisplay
import qs.services
import Quickshell

Rectangle {
    id: root

    readonly property string currentStyle: Config.options.osd.style ?? "default"
    readonly property string currentPosition: Config.options.osd.position ?? "right"
    readonly property bool isLeft: currentPosition === "left"
    readonly property real configuredHeight: Config.options.osd.height ?? 500

    property real previewValue: {
        if (Audio.sink && Audio.sink.audio) {
            return Audio.sink.audio.muted ? 0.0 : Math.min(1.0, Audio.sink.audio.volume);
        }
        return 0.75;
    }

    readonly property string previewIcon: {
        const vol = root.previewValue;
        if (vol <= 0.0) return "volume_off";
        if (vol <= 0.33) return "volume_mute";
        if (vol <= 0.66) return "volume_down";
        return "volume_up";
    }

    function triggerRealOsd() {
        if (typeof GlobalStates !== "undefined") {
            GlobalStates.osdCurrentIndicator = "volume";
            GlobalStates.osdVolumeOpen = true;
            GlobalStates.osdInteraction();
        }
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "osd", "trigger"]);
    }

    Layout.fillWidth: true
    implicitHeight: mainLayout.implicitHeight + 28
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    clip: true

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        // Card Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: "desktop_windows"
                shape: MaterialShape.Shape.Cookie4Sided
                iconSize: 20
                padding: 6
                color: Appearance.colors.colPrimary
                colSymbol: Appearance.colors.colOnPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("OSD Live Preview")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (root.currentStyle === "minimalist")
                            return Translation.tr("Minimalist floating pill preview");
                        if (root.currentStyle === "material")
                            return Translation.tr("Material 3 expressive indicator preview");
                        return Translation.tr("Android edge slider preview (%1)").arg(root.isLeft ? Translation.tr("Left") : Translation.tr("Right"));
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.full
                materialIcon: "play_arrow"
                mainText: Translation.tr("Test OSD")
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: {
                    root.triggerRealOsd();
                }
                StyledToolTip {
                    text: Translation.tr("Trigger on-screen display immediately on screen")
                }
            }
        }

        // ==========================================
        // 1. ANDROID STYLE: Taller preview + Side toggles with dynamic radius & background
        // ==========================================
        RowLayout {
            id: androidLayout
            Layout.fillWidth: true
            visible: root.currentStyle === "default" || (root.currentStyle !== "minimalist" && root.currentStyle !== "material")
            spacing: 18

            // Taller Mini Android OSD vertical pill
            Item {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 230
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    id: previewPill
                    anchors.centerIn: parent
                    width: 56
                    height: Math.max(160, Math.min(220, root.configuredHeight * 0.35))
                    radius: Appearance.rounding.full
                    color: Appearance.m3colors.m3surfaceContainer

                    Behavior on height {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        MaterialShapeWrappedMaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.previewIcon
                            shape: MaterialShape.Shape.Circle
                            iconSize: 18
                            padding: 4
                            color: Appearance.colors.colSecondaryContainer
                            colSymbol: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledVerticalSlider {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            configuration: StyledVerticalSlider.Configuration.M
                            shape: MaterialShape.Shape.Cookie7Sided
                            materialSymbol: root.previewIcon
                            showValueLabel: false
                            from: 0
                            to: 1
                            value: root.previewValue
                            onMoved: {
                                root.previewValue = value;
                            }
                        }
                    }
                }
            }

            // Side controls column with dynamic radius & background
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                // Toggle 1: Height Slider Row (Top Item)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: heightRowLayout.implicitHeight + 20
                    color: Appearance.colors.colLayer1
                    topLeftRadius: Appearance.rounding.large
                    topRightRadius: Appearance.rounding.large
                    bottomLeftRadius: Appearance.rounding.verysmall
                    bottomRightRadius: Appearance.rounding.verysmall

                    Behavior on topLeftRadius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: heightRowLayout
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        MaterialSymbol {
                            text: "height"
                            iconSize: 18
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: Translation.tr("Height")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledSlider {
                            id: previewHeightSlider
                            Layout.fillWidth: true
                            from: 300
                            to: 800
                            stepSize: 10
                            value: Config.options.osd.height ?? 500
                            usePercentTooltip: false
                            tooltipContent: `${Math.round(value)}px`
                            onMoved: {
                                Config.options.osd.height = Math.round(value);
                                root.triggerRealOsd();
                            }
                            onPressedChanged: {
                                if (pressed) {
                                    root.triggerRealOsd();
                                }
                            }
                        }

                        StyledText {
                            text: `${Math.round(Config.options.osd.height ?? 500)}px`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Toggle 2: Show Value Numbers Switch (Bottom Item)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: valueNumberRowLayout.implicitHeight + 20
                    color: Appearance.colors.colLayer1
                    topLeftRadius: Appearance.rounding.verysmall
                    topRightRadius: Appearance.rounding.verysmall
                    bottomLeftRadius: Appearance.rounding.large
                    bottomRightRadius: Appearance.rounding.large

                    Behavior on bottomLeftRadius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: valueNumberRowLayout
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        MaterialSymbol {
                            text: "tag"
                            iconSize: 18
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Show value numbers")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledSwitch {
                            checked: Config.options.osd.showValues
                            onCheckedChanged: {
                                Config.options.osd.showValues = checked;
                                root.triggerRealOsd();
                            }
                        }
                    }
                }
            }
        }

        // ==========================================
        // 2. MINIMALIST STYLE
        // ==========================================
        Item {
            Layout.fillWidth: true
            implicitHeight: 110
            visible: root.currentStyle === "minimalist"

            OsdValueIndicator {
                anchors.centerIn: parent
                value: root.previewValue
                icon: root.previewIcon
                name: Translation.tr("Volume")
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }

        // ==========================================
        // 3. MATERIAL STYLE
        // ==========================================
        Item {
            Layout.fillWidth: true
            implicitHeight: 110
            visible: root.currentStyle === "material"

            OsdMaterialValueIndicator {
                anchors.centerIn: parent
                value: root.previewValue
                icon: root.previewIcon
                shape: MaterialShape.Shape.Cookie7Sided
                onMoved: function(newValue) {
                    root.previewValue = newValue;
                }
            }
        }
    }
}
