pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A list of short strings as removable chips, with a field to type another and, when the
 * caller can offer some, a menu of suggestions (running windows, paired devices, known
 * networks…) so the user rarely has to know the exact spelling.
 *
 * The suggestions stay a small dropdown anchored to the Pick button rather than a side
 * sheet: they belong to one field deep inside a form, and a sheet would carry the eye
 * away from the row being filled in.
 */
ColumnLayout {
    id: root

    property var values: []
    property string placeholder: ""
    /// [{ label, value }] — shown under a "Pick" button; empty hides it.
    property var suggestions: []
    /// Maps a stored value to what the chip shows.
    property var display: v => v

    signal changed(var list)

    spacing: ClockStyle.gapSmall - 2

    function add(value) {
        const v = String(value ?? "").trim();
        if (!v.length)
            return;
        const list = Array.from(root.values);
        if (list.indexOf(v) !== -1)
            return;
        list.push(v);
        root.changed(list);
    }

    function removeAt(index) {
        const list = Array.from(root.values);
        list.splice(index, 1);
        root.changed(list);
    }

    Flow {
        Layout.fillWidth: true
        visible: root.values.length > 0
        spacing: ClockStyle.gapTiny + 2

        Repeater {
            model: root.values

            delegate: Rectangle {
                id: chip
                required property string modelData
                required property int index

                implicitWidth: chipRow.implicitWidth + ClockStyle.gap + ClockStyle.gapTiny
                implicitHeight: 32
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colSecondaryContainer

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny

                    StyledText {
                        Layout.leftMargin: 2
                        text: root.display(chip.modelData)
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.Medium
                        color: ClockStyle.colOnSecondaryContainer
                    }

                    RippleButton {
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: 11
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.12)
                        colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.2)
                        onClicked: root.removeAt(chip.index)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 16
                            color: ClockStyle.colOnSecondaryContainer
                        }

                        StyledToolTip {
                            text: Translation.tr("Remove")
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ClockStyle.gapTiny + 2

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: ClockStyle.radiusSmall
            color: entry.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: entry.forceActiveFocus()
            }

            StyledTextInput {
                id: entry
                anchors {
                    fill: parent
                    leftMargin: ClockStyle.gap + 2
                    rightMargin: ClockStyle.gap + 2
                }
                verticalAlignment: TextInput.AlignVCenter
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textNormal
                clip: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.add(entry.text);
                        entry.text = "";
                        event.accepted = true;
                    }
                }
                onEditingFinished: {
                    if (entry.text.trim().length) {
                        root.add(entry.text);
                        entry.text = "";
                    }
                }

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !entry.text.length
                    text: root.placeholder
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: parent.radius / 2
                    rightMargin: parent.radius / 2
                }
                height: 2
                radius: 1
                color: ClockStyle.colPrimary
                opacity: entry.activeFocus ? 1 : 0
            }
        }

        RippleButton {
            id: pickButton
            visible: root.suggestions.length > 0
            implicitHeight: 40
            implicitWidth: pickRow.implicitWidth + ClockStyle.gapLarge * 2
            buttonRadius: ClockStyle.pill(40)
            buttonRadiusPressed: ClockStyle.radiusSmall
            colBackground: suggestionMenu.opened ? ClockStyle.colSecondaryContainer : ClockStyle.colSurfaceHigh
            colBackgroundHover: suggestionMenu.opened ? ClockStyle.colSecondaryContainerHover : ClockStyle.colSurfaceHover
            colRipple: ClockStyle.colSecondaryContainerActive
            onClicked: suggestionMenu.opened ? suggestionMenu.close() : suggestionMenu.open()

            contentItem: Item {
                implicitWidth: pickRow.implicitWidth
                implicitHeight: pickRow.implicitHeight

                RowLayout {
                    id: pickRow
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny

                    StyledText {
                        text: Translation.tr("Pick")
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: suggestionMenu.opened ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    }

                    MaterialSymbol {
                        text: "expand_more"
                        iconSize: ClockStyle.iconSmall + 2
                        rotation: suggestionMenu.opened ? 180 : 0
                        color: suggestionMenu.opened ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant

                        Behavior on rotation {
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                    }
                }
            }

            Popup {
                id: suggestionMenu
                y: parent.height + ClockStyle.gapTiny
                x: parent.width - width
                width: 300
                height: Math.min(320, suggestionList.contentHeight + ClockStyle.gapSmall * 2)
                padding: ClockStyle.gapSmall
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: ClockStyle.motionFast.duration
                    }
                }
                exit: Transition {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: ClockStyle.motionFast.duration
                    }
                }

                background: Rectangle {
                    radius: ClockStyle.radiusLarge
                    color: ClockStyle.colSheet

                    StyledRectangularShadow {
                        target: parent
                    }
                }

                contentItem: StyledListView {
                    id: suggestionList
                    clip: true
                    spacing: 2
                    popin: false
                    animateAppearance: false
                    animatePopulate: false
                    model: root.suggestions

                    delegate: RippleButton {
                        id: suggestion
                        required property var modelData

                        width: suggestionList.width
                        implicitHeight: 44
                        buttonRadius: ClockStyle.radiusSmall
                        colBackground: "transparent"
                        colBackgroundHover: ClockStyle.colFieldHover
                        colRipple: ClockStyle.colSurfaceActive
                        onClicked: {
                            root.add(suggestion.modelData.value);
                            suggestionMenu.close();
                        }

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: ClockStyle.gap
                                rightMargin: ClockStyle.gap
                            }
                            spacing: ClockStyle.gapSmall

                            MaterialSymbol {
                                text: Array.from(root.values).indexOf(String(suggestion.modelData.value)) !== -1 ? "check" : "add"
                                iconSize: ClockStyle.iconSmall
                                color: ClockStyle.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: suggestion.modelData.label
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                color: ClockStyle.colOnSurface
                            }

                            StyledText {
                                visible: suggestion.modelData.label !== suggestion.modelData.value
                                text: suggestion.modelData.value
                                elide: Text.ElideMiddle
                                Layout.maximumWidth: 120
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
