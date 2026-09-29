pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * EasyEffects, expanded inside the auxiliary bubble's card.
 *
 * The preset in use and the device it plays on, then the device's presets as chips
 * (the family of its default preset, or all of them, as the app's settings say): a click
 * switches. The corner buttons bypass every effect and open the app.
 *
 * Self-contained on purpose: the bubble loads faces by URL, and such a file gets none of
 * its directory's types. It asks EasyEffects to keep its state fresh only while it
 * exists, which is while the card is open.
 */
Item {
    id: root

    readonly property var presets: EasyEffects.devicePresets
    readonly property string current: EasyEffects.outputPreset
    readonly property var heroItems: [badge]

    // ── Geometry: declared, so the box answers to the content and not to the card ──
    readonly property real margin: 14
    readonly property real preferredExpandedWidth: 312
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    Component.onCompleted: EasyEffects.hold("islandCard", true)
    Component.onDestruction: EasyEffects.hold("islandCard", false)

    // Resting on the bubble opens this card under a pointer that may have come to
    // scroll it, so the card switches presets on a scroll just like the bubble does.
    property real wheelDelta: 0

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            root.wheelDelta += event.angleDelta.y;
            if (Math.abs(root.wheelDelta) < 120)
                return;
            EasyEffects.cyclePreset(root.wheelDelta > 0 ? -1 : 1);
            root.wheelDelta = 0;
        }
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item {
                id: badge
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40

                MaterialCookie {
                    anchors.centerIn: parent
                    implicitSize: 40
                    sides: 9
                    color: EasyEffects.bypassed ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colPrimaryContainer
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: EasyEffects.iconFor(root.current)
                    iconSize: 22
                    fill: EasyEffects.bypassed ? 0 : 1
                    color: EasyEffects.bypassed ? Appearance.colors.colSubtext : Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.current.length > 0 ? root.current : Translation.tr("No preset")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: EasyEffects.bypassed ? Translation.tr("Effects bypassed")
                        : Audio.friendlyDeviceName(EasyEffects.outputDevice)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            CornerButton {
                glyph: "power_settings_new"
                active: !EasyEffects.bypassed
                tip: EasyEffects.bypassed ? Translation.tr("Turn effects back on") : Translation.tr("Bypass all effects")
                onClicked: EasyEffects.toggleBypass()
            }

            CornerButton {
                glyph: "open_in_new"
                tip: Translation.tr("Open EasyEffects")
                onClicked: GlobalStates.openEasyEffectsApp("presets")
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.presets

                RippleButton {
                    id: chip
                    required property string modelData
                    readonly property bool selected: chip.modelData === root.current

                    implicitHeight: 32
                    implicitWidth: chipRow.implicitWidth + 24
                    buttonRadius: chip.selected ? Appearance.rounding.small : Appearance.rounding.full
                    colBackground: chip.selected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: chip.selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighest
                    colRipple: chip.selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: EasyEffects.loadPreset(chip.modelData, "output", true)

                    contentItem: Item {
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialSymbol {
                                text: EasyEffects.iconFor(chip.modelData)
                                iconSize: 16
                                fill: chip.selected ? 1 : 0
                                color: chip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                text: EasyEffects.shortName(chip.modelData)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: chip.selected ? Font.DemiBold : Font.Normal
                                color: chip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.presets.length === 0
            wrapMode: Text.WordWrap
            text: Translation.tr("No presets yet. Create one in the EasyEffects app.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    component CornerButton: RippleButton {
        id: cornerButton
        property string glyph
        property string tip
        property bool active: false

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: cornerButton.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: cornerButton.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighest

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: cornerButton.glyph
                iconSize: 18
                color: cornerButton.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
            }
        }

        StyledToolTip {
            text: cornerButton.tip
        }
    }
}
