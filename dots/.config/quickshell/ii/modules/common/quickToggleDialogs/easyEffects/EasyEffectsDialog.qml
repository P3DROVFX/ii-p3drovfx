pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The EasyEffects quick toggle's dialog, in the audio output dialog's shape: effects on
 * or off in the header, the output device's presets as a list (a click switches), and
 * Details, which opens the EasyEffects app.
 */
WindowDialog {
    id: root
    property bool closeOwningSidebarOnDetails: true
    property bool showDetailsAction: true
    property bool showAll: false

    signal detailsRequested()

    readonly property var presets: root.showAll ? Array.from(EasyEffects.outputPresets) : EasyEffects.devicePresets
    readonly property bool hasOthers: EasyEffects.devicePresets.length < EasyEffects.outputPresets.length
    readonly property string deviceName: Audio.friendlyDeviceName(EasyEffects.outputDevice)

    backgroundWidth: 380

    Component.onCompleted: {
        EasyEffects.hold("quickDialog", true);
        EasyEffects.refreshPresets();
    }
    Component.onDestruction: EasyEffects.hold("quickDialog", false)

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr("EasyEffects")
        }

        StyledSwitch {
            visible: EasyEffects.available
            enabled: !EasyEffects.starting
            checked: EasyEffects.active
            checkable: false
            onClicked: EasyEffects.toggle()
        }
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        Layout.topMargin: -8
        text: {
            if (!EasyEffects.available)
                return Translation.tr("EasyEffects isn't installed.");
            if (EasyEffects.starting)
                return Translation.tr("Starting EasyEffects…");
            if (!EasyEffects.running)
                return Translation.tr("Not running. Pick a preset to start it with that preset.");
            const preset = EasyEffects.outputPreset.length > 0 ? EasyEffects.outputPreset : Translation.tr("no preset");
            return EasyEffects.bypassed
                ? Translation.tr("%1 · %2, bypassed").arg(root.deviceName).arg(preset)
                : Translation.tr("%1 · %2").arg(root.deviceName).arg(preset);
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: EasyEffects.available
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            text: root.showAll ? Translation.tr("All presets") : Translation.tr("Presets for %1").arg(root.deviceName)
            elide: Text.ElideRight
        }

        RippleButton {
            visible: root.hasOthers || root.showAll
            implicitHeight: 28
            implicitWidth: allText.implicitWidth + 20
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            onClicked: root.showAll = !root.showAll

            contentItem: StyledText {
                id: allText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.showAll ? Translation.tr("This device") : Translation.tr("Show all")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colPrimary
            }
        }
    }

    // Bounded: a long preset list scrolls here instead of pushing the buttons away.
    StyledFlickable {
        id: listFlick
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(presetColumn.implicitHeight, 340)
        visible: EasyEffects.available
        contentWidth: width
        contentHeight: presetColumn.implicitHeight
        interactive: contentHeight > height
        clip: true

        ColumnLayout {
            id: presetColumn
            width: listFlick.width
            spacing: 4

            Repeater {
                model: root.presets

                RippleButton {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property bool current: row.modelData === EasyEffects.outputPreset
                    readonly property bool isDefault: row.modelData === EasyEffects.outputDeviceDefault

                    Layout.fillWidth: true
                    implicitHeight: 52
                    topLeftRadius: row.index === 0 ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: row.index === root.presets.length - 1 ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                    bottomRightRadius: bottomLeftRadius
                    colBackground: row.current ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: row.current ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: row.current ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: EasyEffects.loadPreset(row.modelData, "output", true)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        MaterialSymbol {
                            text: EasyEffects.iconFor(row.modelData)
                            iconSize: Appearance.font.pixelSize.larger
                            fill: row.current ? 1 : 0
                            color: row.current ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: root.showAll ? row.modelData : EasyEffects.shortName(row.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                                color: row.current ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                visible: row.isDefault
                                text: Translation.tr("Default for this device")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: row.current ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        MaterialSymbol {
                            visible: row.current
                            text: EasyEffects.bypassed ? "do_not_disturb_on" : "check"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 8
                visible: root.presets.length === 0
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("No presets yet. Create them in the EasyEffects app.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }

    WindowDialogButtonRow {
        Layout.leftMargin: 0
        Layout.rightMargin: 0
        Layout.bottomMargin: -8

        // Details, outlined like the audio dialog's: the EasyEffects app.
        RippleButton {
            id: detailsBtn
            visible: root.showDetailsAction && (Config.options.easyEffects?.appEnable ?? true)
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: "transparent"
            implicitHeight: 36
            implicitWidth: detailsText.implicitWidth + 48

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                radius: parent.buttonEffectiveRadius

                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }
            }

            contentItem: StyledText {
                id: detailsText
                text: Translation.tr("Details")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 500
                    })
                color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            onClicked: {
                GlobalStates.openEasyEffectsApp("presets");
                root.detailsRequested();
                if (root.closeOwningSidebarOnDetails)
                    GlobalStates.sidebarRightOpen = false;
                root.dismiss();
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RippleButton {
            id: doneBtn
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 48

            contentItem: StyledText {
                id: doneText
                text: Translation.tr("Done")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 700
                    })
                color: Appearance.colors.colOnPrimary
            }
            onClicked: root.dismiss()
        }
    }
}
