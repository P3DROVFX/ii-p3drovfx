pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A connected Bluetooth device, expanded inside the auxiliary bubble's card.
 *
 * What the connection strip on the island leaves out: the battery of each part (left,
 * right, case; a single cell for anything BlueZ only reports as one), the noise control
 * where the device has one, and the way out - disconnect, or the device's own settings.
 * The noise modes are one connected button group; the selected one carries its label, so
 * four modes fit the card's width without any being cut.
 *
 * Nothing here is headset-specific: EarbudsControlService falls back to the BlueZ battery
 * and reports no noise control for a device it has no provider for, so a phone gets the
 * same card less the modes. One file serves both bubbles: the bubble hands it the
 * activity it opened for, and the device is whatever that bubble's glance draws, so a
 * card and its ring are never about two different devices. (Two thin wrappers around a
 * shared card would not load: the bubble loads a face by URL, and a directory nothing
 * imports gives such a file none of its siblings' types.)
 *
 * Like every expanded face: the face declares its own box from its content and never
 * from the card it is given; the descriptor in IslandRegistry is the fallback.
 */
Item {
    id: root

    // ── Content ──────────────────────────────────────────────────────────────
    /** Set by AuxiliaryBubble: "earbuds" or "btPhone". */
    property string activityId: ""
    readonly property var device: root.activityId === "earbuds" ? EarbudsControlService.glanceDevice
        : root.activityId === "btPhone" ? BluetoothStatus.phoneDevice : null
    readonly property string deviceName: root.device ? (root.device.name || root.device.alias || "") : ""
    readonly property var battery: EarbudsControlService.batteryInfo(root.device)
    readonly property var parts: {
        const info = root.battery;
        if (!info || !info.available)
            return [];
        return info.components.filter(c => c && c.available && c.level !== null && c.level !== undefined);
    }
    readonly property var noise: EarbudsControlService.noiseControl(root.device)
    readonly property bool hasNoise: root.noise && root.noise.available && root.noise.modes.length > 0
    readonly property string imageSource: BluetoothDeviceImages.sourceFor(root.device)
    /** The avatar the glance's battery ring lands on (see AuxiliaryBubble's heroes). */
    readonly property var heroItems: [avatar]

    // Short on purpose: three cells share 260 px, and a charging bolt takes a label's room.
    function partLabel(part) {
        switch (part.id) {
        case "left": return Translation.tr("L");
        case "right": return Translation.tr("R");
        case "case": return Translation.tr("Case");
        }
        return Translation.tr("Battery");
    }

    function openSettings() {
        if (EarbudsControlService.providerForDevice(root.device) === "budslink")
            EarbudsControlService.openDeviceSettings(root.device);
        else
            Quickshell.execDetached(["blueman-manager"]);
    }

    // ── Geometry: declared, so the box answers to the content and not to the card ──
    readonly property real margin: 14
    // Room for a device name beside the photo and the two corner buttons.
    readonly property real preferredExpandedWidth: 288
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    readonly property color cellColor: Appearance.colors.colSurfaceContainer

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 12

        // ── The device ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item {
                id: avatar
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40

                MaterialCookie {
                    anchors.centerIn: parent
                    implicitSize: 40
                    sides: 9
                    color: Appearance.colors.colPrimaryContainer
                }

                Image {
                    id: photo
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    source: root.imageSource
                    sourceSize: Qt.size(Math.ceil(34 * Screen.devicePixelRatio), Math.ceil(34 * Screen.devicePixelRatio))
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    visible: root.imageSource !== "" && status === Image.Ready
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !photo.visible
                    text: root.device ? Icons.getBluetoothDeviceMaterialSymbol(root.device.icon || "") : "bluetooth"
                    fill: 1
                    iconSize: 22
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.deviceName !== "" ? root.deviceName : Translation.tr("Bluetooth device")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                }

                RowLayout {
                    spacing: 5

                    MaterialSymbol {
                        text: "bluetooth_connected"
                        iconSize: 15
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Connected")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            // The way out, in the corner the name leaves empty: no row of its own.
            RowLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 4

                CornerButton {
                    glyph: "bluetooth_disabled"
                    tip: Translation.tr("Disconnect")
                    glyphColor: Appearance.m3colors.m3onErrorContainer
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.colors.colErrorContainerActive
                    onClicked: root.device?.disconnect()
                }
                CornerButton {
                    glyph: "settings"
                    tip: Translation.tr("Device settings")
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.openSettings()
                }
            }
        }

        // ── Battery: one cell per part ──────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.parts.length > 0
            spacing: 6

            Repeater {
                model: root.parts

                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property int level: Math.round(cell.modelData.level)
                    readonly property bool low: cell.level <= 15

                    // Grown from what each cell holds, so a charging case's bolt widens its
                    // own cell instead of squeezing the label out of three equal ones.
                    Layout.fillWidth: true
                    implicitWidth: cellColumn.implicitWidth + 18
                    implicitHeight: cellColumn.implicitHeight + 14
                    Layout.minimumWidth: cell.implicitWidth
                    radius: Appearance.rounding.normal
                    color: root.cellColor

                    ColumnLayout {
                        id: cellColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 9
                            rightMargin: 9
                        }
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: root.partLabel(cell.modelData)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            MaterialSymbol {
                                visible: cell.modelData.charging === true
                                text: "bolt"
                                fill: 1
                                iconSize: 13
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: cell.level + "%"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                font.features: ({ "tnum": 1 })
                                color: cell.low ? Appearance.m3colors.m3error : Appearance.colors.colOnSurface
                            }
                        }

                        StyledProgressBar {
                            // Fills whatever the text row makes the cell; its own 120 px
                            // default would make every cell ask for the same width again.
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            Layout.preferredHeight: 5
                            valueBarHeight: 5
                            from: 0
                            to: 100
                            value: cell.level
                            highlightColor: cell.low ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            trackColor: Appearance.colors.colSurfaceContainerHighest
                        }
                    }
                }
            }
        }

        // ── Noise control ───────────────────────────────────────────────────
        RowLayout {
            id: noiseGroup
            Layout.fillWidth: true
            visible: root.hasNoise
            spacing: 3

            Repeater {
                model: root.hasNoise ? root.noise.modes : []

                delegate: RippleButton {
                    id: modeButton
                    required property var modelData
                    required property int index
                    readonly property bool selected: root.noise.currentMode === modeButton.modelData.key
                    readonly property bool first: modeButton.index === 0
                    readonly property bool last: modeButton.index === root.noise.modes.length - 1
                    // Vendors name ANC in full ("Noise Cancellation"), which the selected button
                    // can't hold next to three others; the tooltip keeps the full name.
                    readonly property string shortLabel: modeButton.modelData.key === "anc"
                        ? Translation.tr("ANC") : modeButton.modelData.label

                    Layout.fillWidth: modeButton.selected
                    Layout.preferredWidth: modeButton.selected ? -1 : 40
                    implicitHeight: 36
                    implicitWidth: modeRow.implicitWidth + 20
                    // The connected group's shape: outer ends round, inner joins square,
                    // the selected one fully round. Half the height rather than `full`:
                    // the radii animate, and 9999 → 8 would spend the whole move off-shape.
                    readonly property real round: modeButton.implicitHeight / 2
                    topLeftRadius: (modeButton.selected || modeButton.first) ? modeButton.round : 8
                    bottomLeftRadius: modeButton.topLeftRadius
                    topRightRadius: (modeButton.selected || modeButton.last) ? modeButton.round : 8
                    bottomRightRadius: modeButton.topRightRadius
                    colBackground: modeButton.selected ? Appearance.colors.colPrimary
                        : Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: modeButton.selected ? Appearance.colors.colPrimaryHover
                        : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: modeButton.selected ? Appearance.colors.colPrimaryActive
                        : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: EarbudsControlService.setNoiseMode(root.device, modeButton.modelData.key)

                    StyledToolTip {
                        text: modeButton.modelData.label
                    }

                    contentItem: Item {
                        RowLayout {
                            id: modeRow
                            anchors.centerIn: parent
                            // Bounded, so any other long name elides inside the button.
                            width: Math.min(implicitWidth, parent.width)
                            spacing: 6

                            MaterialSymbol {
                                text: modeButton.modelData.icon || "tune"
                                iconSize: 18
                                color: modeButton.selected ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: modeButton.selected
                                text: modeButton.shortLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    /** A round icon button for the header's corner. */
    component CornerButton: RippleButton {
        id: cornerButton
        property string glyph
        property string tip
        property color glyphColor: Appearance.colors.colOnSurface

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full

        StyledToolTip {
            text: cornerButton.tip
        }
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: cornerButton.glyph
            iconSize: 17
            color: cornerButton.glyphColor
        }
    }
}
