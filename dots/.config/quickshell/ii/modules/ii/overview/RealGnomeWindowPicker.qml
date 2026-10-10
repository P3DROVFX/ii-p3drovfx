import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

/**
 * Real Gnome window picker: the input half.
 *
 * The window captures live on the transition layer below the overview, which
 * takes no input. That layer publishes each window's slot at full open
 * (`GlobalStates.realGnomePickerSlots`, screen coordinates); this item lays a
 * hit area over every slot and draws GNOME Shell's affordances on top of the
 * capture: the app icon on the bottom edge, the title under it on hover and
 * the close button in the corner. Hover is published back so the capture
 * lifts with the pointer.
 */
Item {
    id: root

    required property string screenName
    /** Screen coordinates -> this item's coordinates. */
    property real offsetX: 0
    property real offsetY: 0
    property bool shown: false

    readonly property var slots: GlobalStates.realGnomePickerSlots[root.screenName] ?? []

    opacity: root.shown ? 1 : 0
    visible: opacity > 0.001
    enabled: root.shown
    Behavior on opacity {
        NumberAnimation {
            duration: Math.round((root.shown ? 220 : 120) * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }
    onShownChanged: {
        if (!root.shown)
            GlobalStates.realGnomeHoveredWindow = "";
    }
    Component.onDestruction: GlobalStates.realGnomeHoveredWindow = ""

    Repeater {
        model: ScriptModel {
            values: root.slots
            objectProp: "address"
        }

        delegate: Item {
            id: slot
            required property var modelData

            readonly property string address: slot.modelData.address
            readonly property bool hovered: slotHover.hovered
            readonly property string iconSource: {
                const _ = TaskbarApps.iconThemeRevision;
                return Quickshell.iconPath(AppSearch.guessIcon(slot.modelData.appClass), "image-missing");
            }

            x: slot.modelData.x + root.offsetX
            y: slot.modelData.y + root.offsetY
            width: slot.modelData.width
            height: slot.modelData.height

            HoverHandler {
                id: slotHover
                onHoveredChanged: {
                    if (slotHover.hovered)
                        GlobalStates.realGnomeHoveredWindow = slot.address;
                    else if (GlobalStates.realGnomeHoveredWindow === slot.address)
                        GlobalStates.realGnomeHoveredWindow = "";
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${slot.address}" })`);
                        return;
                    }
                    Hyprland.dispatch(`hl.dsp.focus({ window = "address:${slot.address}" })`);
                    GlobalStates.overviewOpen = false;
                }
            }

            // App icon straddling the bottom edge, always shown.
            IconImage {
                id: appIcon
                readonly property real size: Math.round(Math.max(28, Math.min(48, slot.height * 0.22)))
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.bottom
                implicitSize: appIcon.size
                source: slot.iconSource
                scale: slot.hovered ? 1.08 : 1.0
                Behavior on scale {
                    NumberAnimation { duration: Math.round(200 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }
            }

            // Title under the icon on hover.
            Rectangle {
                id: titleChip
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: appIcon.bottom
                anchors.topMargin: 6
                width: Math.min(Math.max(slot.width, 160), titleText.implicitWidth + 24)
                height: titleText.implicitHeight + 10
                radius: height / 2
                color: Appearance.m3colors.m3surfaceContainerHighest
                opacity: slot.hovered && slot.modelData.title.length > 0 ? 1 : 0
                visible: opacity > 0.001
                Behavior on opacity {
                    NumberAnimation { duration: Math.round(160 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }

                StyledText {
                    id: titleText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, titleChip.width - 24)
                    text: slot.modelData.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                }
            }

            // Close button in the top-right corner on hover.
            RippleButton {
                id: closeButton
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -width / 3
                anchors.topMargin: -height / 3
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.m3colors.m3surfaceContainerHighest
                colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
                opacity: slot.hovered ? 1 : 0
                visible: opacity > 0.001
                scale: slot.hovered ? 1 : 0.8
                Behavior on opacity {
                    NumberAnimation { duration: Math.round(160 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: Math.round(200 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }
                onClicked: Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${slot.address}" })`)

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.m3colors.m3onSurface
                }
            }
        }
    }
}
