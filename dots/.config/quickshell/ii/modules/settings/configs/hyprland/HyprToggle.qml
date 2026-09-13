import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A switch whose value is owned by something else - a Hyprland option, a device override, a
 * window rule - rather than by the switch.
 *
 * ConfigSwitch flips its own `checked` when it is clicked, and a handler written at the call site
 * runs *after* that one rather than instead of it. Two things follow, and both had gone wrong in
 * this hub: the handler sees `checked` already holding the new value, so reading `!checked` there
 * writes back the value the setting already had; and the assignment has overwritten whatever
 * `checked` was bound to, so from the first click onwards the switch shows what it assumed rather
 * than what happened.
 *
 * So the value goes in through `switchOn` and the request comes out through `requested`, and the
 * binding is put back afterwards. A write that is refused therefore snaps the switch back, which
 * is the honest outcome.
 *
 * The row is drawn here too, rather than inherited: a line under the title that says what the
 * current state does, and a pill that says who set it. A row that only names the option leaves
 * the reader to work out what "off" means from a sentence written for "on".
 */
ConfigSwitch {
    id: root

    /// What the switch shows. Bind it to wherever the truth actually lives.
    property bool switchOn: false

    /// The state the user just asked for.
    signal requested(bool wanted)

    /// The line under the title. `textOn` and `textOff` replace it while the switch is on or off,
    /// so a row can describe what its state does rather than what the option is called.
    property string description: ""
    property string textOn: ""
    property string textOff: ""
    /// A small pill before the switch. The hub puts who set the option in it.
    property string badgeText: ""

    /**
     * Keeps the line under the title in basic mode.
     *
     * A settings page where every row carries a sentence is a page nobody reads: eight rows of
     * title-plus-explanation is a wall, and the eight titles alone are a list you can scan. So
     * the sentence is part of advanced mode, and a row sets this only when its title genuinely
     * cannot be understood on its own.
     */
    property bool alwaysExplain: false

    readonly property bool explains: root.alwaysExplain || Config.options.hyprland.advancedSettings

    readonly property string subtitle: !root.explains ? ""
        : (root.checked
            ? (root.textOn !== "" ? root.textOn : root.description)
            : (root.textOff !== "" ? root.textOff : root.description))

    checked: root.switchOn
    implicitHeight: toggleLayout.implicitHeight + 20

    onClicked: {
        const wanted = root.checked;
        root.requested(wanted);
        // Restored after the request, not before: putting it back first would show the old value
        // for the frame between the two, which reads as the switch bouncing.
        root.checked = Qt.binding(() => root.switchOn);
    }

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            id: toggleLayout
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            Loader {
                active: root.buttonIcon.length > 0
                visible: active
                Layout.alignment: Qt.AlignVCenter
                opacity: root.enabled ? 1 : 0.4

                sourceComponent: MaterialShapeWrappedMaterialSymbol {
                    text: root.buttonIcon
                    shape: root.checked ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Circle
                    iconSize: root.iconSize
                    padding: 6
                    fill: root.checked ? 1 : 0
                    color: root.checked ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                    colSymbol: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 4
                opacity: root.enabled ? 1 : 0.4

                StyledText {
                    Layout.fillWidth: true
                    text: root.text
                    font.pixelSize: root.font.pixelSize
                    color: Appearance.colors.colOnLayer2
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }

            Loader {
                active: root.extraComponent !== null
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: root.extraComponent
            }

            HyprBadge {
                Layout.alignment: Qt.AlignVCenter
                text: root.badgeText
            }

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: switchWidget.implicitWidth
                implicitHeight: switchWidget.implicitHeight

                StyledSwitch {
                    id: switchWidget
                    anchors.centerIn: parent
                    checked: root.checked
                    enabled: false
                    isPressed: root.isPressed
                    opacity: root.enabled ? 1 : 0.4
                }

                // Keeps the hand cursor over the disabled visual switch without taking the
                // click, which the row handles.
                MouseArea {
                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
    }
}
