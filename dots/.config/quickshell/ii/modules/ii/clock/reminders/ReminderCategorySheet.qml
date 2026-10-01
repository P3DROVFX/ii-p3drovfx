pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A category's name, colour and icon — new, or one being edited. */
ClockSheet {
    id: root

    /// The category being edited, or "" for a new one.
    property string categoryId: ""

    readonly property bool editing: root.categoryId.length > 0
    readonly property var category: root.editing ? RemindersService.category(root.categoryId) : null
    readonly property bool isDefault: root.categoryId === "default"

    property string draftColor: RemindersStyle.palette[RemindersService.categories.length % RemindersStyle.palette.length]
    property string draftIcon: "list"
    property bool draftPinned: false

    function save(): void {
        const name = nameField.text.trim();
        if (name.length === 0 && !root.isDefault) {
            nameField.focusInput();
            return;
        }
        if (root.editing)
            RemindersService.updateCategory(root.categoryId, { name: name || root.category.name, color: root.draftColor, icon: root.draftIcon, pinned: root.draftPinned });
        else
            RemindersService.addCategory(name, root.draftColor, root.draftIcon);
        root.close();
    }

    title: root.editing ? Translation.tr("Edit category") : Translation.tr("New category")

    Component.onCompleted: {
        if (root.category) {
            nameField.text = RemindersService.categoryName(root.categoryId);
            root.draftColor = root.category.color;
            root.draftIcon = root.category.icon;
            root.draftPinned = root.category.pinned;
        }
        Qt.callLater(nameField.focusInput);
    }

    headerActions: [
        ClockIconButton {
            visible: root.editing && !root.isDefault
            symbol: "delete"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            colIcon: ClockStyle.colError
            tooltip: Translation.tr("Delete category and move its reminders to the recycle bin")
            onClicked: {
                RemindersService.deleteCategory(root.categoryId);
                root.close();
            }
        }
    ]

    ClockFormField {
        id: nameField
        symbol: root.draftIcon
        caption: Translation.tr("Name")
        placeholder: Translation.tr("Home, Work, Shopping…")
        onAccepted: root.save()
    }

    StyledText {
        Layout.topMargin: 4
        text: Translation.tr("Colour")
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8

        Swatch {
            swatch: ""
        }

        Repeater {
            model: RemindersStyle.palette

            Swatch {
                required property string modelData
                swatch: modelData
            }
        }
    }

    StyledText {
        Layout.topMargin: 4
        text: Translation.tr("Icon")
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: RemindersStyle.categoryIcons

            ClockIconButton {
                required property string modelData
                symbol: modelData
                size: 40
                iconSize: ClockStyle.iconSmall + 4
                toggled: root.draftIcon === modelData
                onClicked: root.draftIcon = modelData
            }
        }
    }

    ClockFormToggle {
        visible: !root.isDefault
        symbol: "keep"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        label: Translation.tr("Pin to top")
        description: Translation.tr("Listed before the other categories")
        checked: root.draftPinned
        onToggled: checked => root.draftPinned = checked
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Cancel")
            symbol: "close"
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            label: root.editing ? Translation.tr("Save changes") : Translation.tr("Add category")
            symbol: "check"
            onClicked: root.save()
        }
    ]

    component Swatch: Rectangle {
        id: swatchItem
        property string swatch: ""
        readonly property color fill: swatchItem.swatch.length > 0 ? swatchItem.swatch : ClockStyle.colPrimary
        readonly property bool on: root.draftColor === swatchItem.swatch

        width: 36
        height: 36
        radius: swatchItem.on ? ClockStyle.radiusSmall : 18
        color: swatchItem.fill
        border.width: swatchItem.on ? 3 : 0
        border.color: ClockStyle.colOnSurface

        Behavior on radius {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: swatchItem.on || swatchItem.swatch.length === 0
            text: swatchItem.on ? "check" : "palette"
            iconSize: 18
            color: RemindersStyle.onColor(swatchItem.fill)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.draftColor = swatchItem.swatch
        }
    }
}
