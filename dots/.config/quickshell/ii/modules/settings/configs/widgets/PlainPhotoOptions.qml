import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.modules.settings.configs.widgets

/*
 * The page of a Plain Photo widget: the picture (live, as the real widget),
 * the buttons to choose or remove it, and the size. From a widget's Edit Mode
 * menu the picture is that instance's; from Settings it is the type's.
 */
ContentPage {
    id: root
    forceWidth: false

    required property string entryName
    required property string pageTitle

    signal goBack

    readonly property var options: Config.options.background.widgets[root.entryName]
    readonly property var registryEntry: WidgetsRegistry.builtinWidgets.find(w => w.widgetId === root.entryName)
    readonly property string currentPath: WidgetPhotoPicker.currentPath(root.entryName)

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: root.pageTitle
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── The picture, live ──
    Rectangle {
        id: stage
        Layout.fillWidth: true
        implicitHeight: 260
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        Loader {
            id: preview
            anchors.centerIn: parent
            // Synchronous: preview hosts load sync (an async swap can crash qs).
            asynchronous: false
            // isPreview has to be there at creation: set later, the entry
            // animation has already started and the preview stays invisible.
            Component.onCompleted: if (root.registryEntry)
                preview.setSource(root.registryEntry.qmlPath, { "isPreview": true })
            readonly property real fit: item ? Math.min(1, (stage.height - 40) / Math.max(1, item.implicitHeight), (stage.width - 40) / Math.max(1, item.implicitWidth)) : 1
            width: item ? item.implicitWidth : 0
            height: item ? item.implicitHeight : 0
            scale: fit
        }
    }

    ContentSection {
        title: Translation.tr("Photo")
        icon: "image"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "folder_open"
                mainText: Translation.tr("Choose Image")
                enabled: !WidgetPhotoPicker.picking
                onClicked: WidgetPhotoPicker.pick(root.entryName)
            }

            StyledText {
                Layout.fillWidth: true
                text: root.currentPath !== ""
                    ? Translation.tr("Current image: %1").arg(root.currentPath)
                    : Translation.tr("No image chosen: the wallpaper is shown.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: root.currentPath !== ""
                materialIcon: "delete"
                mainText: Translation.tr("Remove Custom Image")
                onClicked: WidgetPhotoPicker.clear(root.entryName)
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: root.options?.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: if (root.options) root.options.widgetSize = value
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
