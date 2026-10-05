import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.dockUtilities
import "../../../ii/dock/utilities"
import "../../../ii/dock/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * Dock → Utility widgets. The hero is the strip of widgets on the dock, drawn
 * by the real tiles in the dock's order; under it every widget the dock can
 * hold, grouped, each a card with its two faces. Options of a widget open as a
 * sub-page from its card (dockUtilities/<file>Config.qml).
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var entries: DockUtilityCatalog.normalize(Config.options.dock.utilityWidgets ?? [])
    // The strip follows the dock: keys placed in dock.order first, in that
    // order, then the ones never dragged, in the order they were added.
    readonly property var stripEntries: {
        const order = Config.options.dock.order ?? [];
        const placed = [];
        const rest = [];
        for (const entry of subPageRoot.entries) {
            const at = order.indexOf(DockUtilityCatalog.orderKey(entry.kind));
            if (at >= 0)
                placed.push({ entry: entry, at: at });
            else
                rest.push(entry);
        }
        placed.sort((a, b) => a.at - b.at);
        return placed.map(item => item.entry).concat(rest);
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Utility widgets")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Hero: the widgets on the dock, live ────────────────────────────
        Rectangle {
            id: hero
            Layout.fillWidth: true
            implicitHeight: heroColumn.implicitHeight + 40
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: heroColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 20
                }
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    MaterialShapeWrappedMaterialSymbol {
                        text: "dashboard_customize"
                        iconSize: 24
                        padding: 12
                        fill: 1
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("On your dock")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: subPageRoot.entries.length === 0
                                ? Translation.tr("No utility widgets yet. Turn one on below.")
                                : subPageRoot.entries.length === 1
                                    ? Translation.tr("1 widget · drag it on the dock to move it, right-click it for its menu")
                                    : Translation.tr("%1 widgets · drag them on the dock to move them, right-click one for its menu").arg(subPageRoot.entries.length)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // The widgets as the dock lays them out: real tiles at the
                // dock's size on a bar of the dock's colour; it wraps rather
                // than scrolls on narrow pages.
                Rectangle {
                    Layout.fillWidth: true
                    visible: subPageRoot.entries.length > 0
                    implicitHeight: strip.implicitHeight + 24
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer0

                    Flow {
                        id: strip
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 12
                        }
                        spacing: 8

                        Repeater {
                            model: subPageRoot.stripEntries
                            delegate: UtilityPreview {
                                required property var modelData
                                kind: modelData.kind
                                wide: modelData.wide
                                width: implicitWidth
                                height: implicitHeight
                            }
                        }
                    }
                }
            }
        }

        // ── The catalog, by group ──────────────────────────────────────────
        DockUtilityCardGrid {
            Layout.fillWidth: true
            Layout.topMargin: 12
            onConfigureRequested: info => subPageRoot.activeSubPage = Qt.resolvedUrl("../dockUtilities/" + info.file + "Config.qml")
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
