pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string title: ""
    property string icon: ""
    property bool accent: false
    property string statusText: ""
    property var primaryHint: ({})
    property var hints: []
    property var onBack: null
    // Panels are selected by the Search field, so repeating their icon and
    // title immediately below it wastes the most valuable vertical space.
    // Keep these opt-in for the rare panel that truly needs in-panel context.
    property bool showHeader: false
    property bool showStatus: false
    property real minimumContentHeight: Config.options.search.appearance.panelBodyHeight
    readonly property real contentMargin: Appearance.sizes.elevationMargin
    default property alias content: contentSlot.data

    implicitWidth: contentColumn.implicitWidth + root.contentMargin * 2
    implicitHeight: contentColumn.implicitHeight + root.contentMargin * 2

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root.contentMargin
        spacing: Appearance.sizes.elevationMargin / 2

        RowLayout {
            Layout.fillWidth: true
            visible: root.showHeader

            RippleButton {
                visible: typeof root.onBack === "function"
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                onClicked: root.onBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                }
            }

            MaterialSymbol {
                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                color: root.accent ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }
        }

        Item {
            id: contentSlot
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Hosted panels deliberately have a stable viewport. Deriving
            // this from childrenRect would loop as panel content fills the
            // slot's height, and was the source of sporadic panel shrinkage.
            implicitHeight: root.minimumContentHeight
        }

        RowLayout {
            Layout.fillWidth: true
            visible: (root.showStatus && root.statusText.length > 0)
                || (Config.options.search.appearance.showKeyHintBar
                    && (root.hints.length > 0 || Object.keys(root.primaryHint).length > 0))

            StyledText {
                Layout.fillWidth: true
                visible: root.showStatus && root.statusText.length > 0
                text: root.statusText
                elide: Text.ElideRight
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            Item {
                Layout.fillWidth: true
                visible: !root.showStatus || root.statusText.length === 0
            }

            KeyHintBar {
                visible: Config.options.search.appearance.showKeyHintBar
                hints: root.primaryHint.label ? [root.primaryHint].concat(root.hints) : root.hints
                showKeys: Config.options.search.appearance.showKeyHints
                surface: root.accent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                onSurface: root.accent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
            }
        }
    }
}
