pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The bar, edited in the bar.
 *
 * This step used to ask the reader to choose a position and a corner style
 * from two rows of buttons — first blind, then against a drawing of a screen.
 * Both were the same mistake at different sizes: a picture of the shell
 * standing in for the shell, while the real thing — Edit Mode, with the actual
 * bar, the actual widgets, and the same position and shape controls — was one
 * keybind away the whole time.
 *
 * So the page opens Edit Mode and gets out of the way. The host owns that
 * lifecycle exactly as it owns the Sidebar and Search previews: it opens the
 * mode on arrival and closes it on the way out, but only if the mode was not
 * already running before the Welcome asked for it.
 *
 * The window stays where it is. Edit Mode normally parks the desktop on an
 * empty workspace, because windows cover the thing being edited — but here the
 * Welcome is that window, so this entry keeps the workspace. See
 * `GlobalStates.openEditMode`.
 */
Item {
    id: root

    property bool nextButtonHovered: false

    /** Nobody has to rearrange a bar to finish setting up. */
    readonly property string skipLabel: Translation.tr("Skip")

    signal openEditMode()

    readonly property bool editing: GlobalStates.editMode
    /**
     * The same three conditions `GlobalStates.openEditMode` refuses on. Without
     * them the page would offer a button that silently does nothing.
     */
    readonly property bool available: Config.options.background.enable
        && !GlobalStates.screenLocked
        && !GlobalStates.mediaModeActive

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.large
        anchors.rightMargin: Appearance.rounding.large
        spacing: Appearance.rounding.small

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Appearance.rounding.small

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: root.editing ? "edit" : root.available ? "edit_off" : "desktop_access_disabled"
                shape: root.editing ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie7Sided
                iconSize: Appearance.font.pixelSize.huge
                padding: Appearance.rounding.small
                fill: 1
                color: root.editing
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer2
                colSymbol: root.editing
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.editing
                    ? Translation.tr("Edit mode is on")
                    : root.available
                        ? Translation.tr("Edit mode is closed")
                        : Translation.tr("Edit mode is unavailable")
                color: Appearance.colors.colOnLayer0
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.hugeass
                font.weight: Font.Bold
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Appearance.rounding.verysmall
            text: root.editing
                ? Translation.tr("Your real bar is live behind this window. Everything you change out there is the shell itself, not a preview.")
                : root.available
                    ? Translation.tr("Reopen it to arrange your bar, or skip this step — none of it is needed to finish setting up.")
                    : Translation.tr("Edit mode needs the desktop turned on. You can arrange the bar later from Settings, or with its own keybind.")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.normal
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            id: hints

            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Appearance.rounding.normal
            Layout.maximumWidth: Appearance.rounding.verylarge * 19
            spacing: Appearance.rounding.verysmall
            opacity: root.editing ? 1 : 0.45

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(hints)
            }

            Hint {
                hintIcon: "drag_pan"
                hintText: Translation.tr("Drag a widget along the bar to move it. Drop it on the panel to take it off.")
            }

            Hint {
                hintIcon: "tune"
                hintText: Translation.tr("The panel holds the bar's position, size, corner style and auto-hide, plus every widget you can add.")
            }

            Hint {
                hintIcon: "mouse"
                hintText: Translation.tr("Right-click a widget for its own options, or the desktop for wallpaper and colours.")
            }

            // The one thing the mode cannot teach from inside itself: how to
            // get back in. There is no keybind for it by default, so the menu
            // is the answer, and nobody finds a context menu by accident.
            Hint {
                hintIcon: "ads_click"
                hintText: Translation.tr("Later on: right-click anywhere on the desktop and choose Edit layout.")
            }
        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Appearance.rounding.normal
            visible: !root.editing && root.available
            implicitHeight: Appearance.rounding.verylarge + Appearance.rounding.normal
            centerContent: true
            materialIcon: "edit"
            mainText: Translation.tr("Open edit mode")
            mainTextWeight: Font.Bold
            mainTextFontFamily: Appearance.font.family.title
            mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
            textPixelSize: Appearance.font.pixelSize.normal
            buttonRadius: Appearance.rounding.full
            colText: Appearance.colors.colOnPrimary
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colBackgroundActive: Appearance.colors.colPrimaryActive
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: root.openEditMode()
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            visible: root.editing
            text: Translation.tr("This window gets out of the way on its own — bring it back from the pill beside the toolbar. Done there continues the setup.")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.smaller
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    component Hint: RowLayout {
        id: hint

        required property string hintIcon
        required property string hintText

        Layout.fillWidth: true
        spacing: Appearance.rounding.small

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: hint.hintIcon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer2
        }

        StyledText {
            Layout.fillWidth: true
            text: hint.hintText
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.WordWrap
        }
    }
}
