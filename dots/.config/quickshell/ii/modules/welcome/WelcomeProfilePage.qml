pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The step that asks who is using this computer.
 *
 * The shell already puts a name and an avatar on the dashboard header and the
 * lock screen, and until now the only way to fill either in was to find them
 * in Settings. A phone asks for this before it asks for a wallpaper.
 *
 * The shape catalogue here is a shortlist rather than the full set Settings
 * offers: this is the taste of the thing, not the whole drawer.
 */
Item {
    id: root

    property bool nextButtonHovered: false

    readonly property string systemName: SystemInfo.username || ""
    readonly property string effectiveName: Config.options.userProfile.customName.length > 0
        ? Config.options.userProfile.customName
        : root.systemName

    readonly property var shapeOptions: [
        "Cookie9Sided", "Circle", "Clover4Leaf", "Sunny",
        "Flower", "Heart", "Gem", "Square"
    ].map(shapeName => ({
        "displayName": "",
        "shape": shapeName,
        "value": shapeName
    }))

    UserProfileImagePicker {
        id: imagePicker
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.large
        anchors.rightMargin: Appearance.rounding.large
        spacing: Appearance.rounding.small

        Item { Layout.fillHeight: true }

        UserProfileAvatar {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Appearance.font.pixelSize.hugeass * 8
            implicitHeight: Appearance.font.pixelSize.hugeass * 8
            fontPixelSize: Appearance.font.pixelSize.hugeass * 3
            fontWeight: Font.Black
            active: GlobalStates.welcomeOpen
            interactive: Config.options.userProfile.imageStyle === "custom"
            onClicked: {
                if (Config.options.userProfile.imageStyle === "custom")
                    imagePicker.pick();
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Appearance.rounding.verysmall
            text: root.effectiveName.length > 0
                ? Translation.tr("Hello, %1").arg(root.effectiveName)
                : Translation.tr("Tell II what to call you")
            color: Appearance.colors.colOnLayer0
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.hugeass
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("This name and picture appear on your dashboard and lock screen.")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // The heading above already says what this field is for, so the input
        // carries no second label of its own — only the name it would fall
        // back to, as its placeholder.
        MaterialTextField {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Appearance.rounding.verysmall
            Layout.preferredWidth: Math.min(root.width, Appearance.rounding.verylarge * 14)
            horizontalAlignment: TextInput.AlignHCenter
            placeholderText: root.systemName.length > 0
                ? root.systemName
                : Translation.tr("Your name")
            text: Config.options.userProfile.customName
            onTextChanged: Config.options.userProfile.customName = text
            Accessible.name: Translation.tr("Your name")
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: Appearance.rounding.verysmall
            columns: root.width >= Appearance.rounding.verylarge * 24 ? 3 : 1
            columnSpacing: Appearance.rounding.normal
            rowSpacing: Appearance.rounding.verysmall

            PickerColumn {
                pickerLabel: Translation.tr("Picture")

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    currentValue: Config.options.userProfile.imageStyle
                    onSelected: value => {
                        Config.options.userProfile.imageStyle = value;
                        if (value === "custom")
                            imagePicker.pick();
                    }
                    options: [{
                        "displayName": Translation.tr("Initial"), "icon": "title", "value": "initial"
                    }, {
                        "displayName": Translation.tr("Shape"), "icon": "cookie", "value": "expressive"
                    }, {
                        "displayName": Translation.tr("Photo"), "icon": "image", "value": "custom"
                    }]
                }
            }

            PickerColumn {
                pickerLabel: Translation.tr("Shape")

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    currentValue: Config.options.userProfile.avatarShape
                    onSelected: value => Config.options.userProfile.avatarShape = value
                    options: root.shapeOptions
                }
            }

            PickerColumn {
                pickerLabel: Translation.tr("Colour")

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    currentValue: Config.options.userProfile.avatarColor
                    onSelected: value => Config.options.userProfile.avatarColor = value
                    options: [{
                        "displayName": Translation.tr("Primary"), "icon": "circle",
                        "color": Appearance.colors.colPrimary.toString(), "value": "primary"
                    }, {
                        "displayName": Translation.tr("Secondary"), "icon": "circle",
                        "color": Appearance.colors.colSecondary.toString(), "value": "secondary"
                    }, {
                        "displayName": Translation.tr("Tertiary"), "icon": "circle",
                        "color": Appearance.colors.colTertiary.toString(), "value": "tertiary"
                    }, {
                        "displayName": Translation.tr("Error"), "icon": "circle",
                        "color": Appearance.colors.colError.toString(), "value": "error"
                    }]
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    component PickerColumn: ColumnLayout {
        id: pickerColumn

        required property string pickerLabel

        Layout.fillWidth: true
        Layout.preferredWidth: 0
        spacing: Appearance.rounding.unsharpen

        StyledText {
            Layout.fillWidth: true
            text: pickerColumn.pickerLabel
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
        }
    }
}
