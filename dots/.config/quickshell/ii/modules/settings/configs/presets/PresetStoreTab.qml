import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The Store tab: whatever GitHub answers for the preset topic, right now.
 *
 * There is no index and no server behind this. Every listing is a live search,
 * which is why the tab says what it is doing rather than showing an empty grid
 * while it waits, and why a refused search reports the reason instead of
 * looking like a store with nothing in it.
 */
ColumnLayout {
    id: root
    spacing: 12
    Layout.fillWidth: true

    signal openDetails(var entry)

    // 0 stars · 1 recently updated · 2 name
    property int sortMode: 0

    readonly property var results: {
        let rows = PresetStore.discoverResults.slice();
        if (root.sortMode === 1)
            rows.sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)));
        else if (root.sortMode === 2)
            rows.sort((a, b) => String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase()));
        else
            rows.sort((a, b) => (b.stars || 0) - (a.stars || 0));
        return rows;
    }

    Component.onCompleted: {
        PresetStore.ensureLoaded();
        PresetStore.discover("", 30);
        PresetStore.checkUpdates(false);
    }

    // Typing must not fire a search per keystroke: GitHub allows ten a minute
    // to a signed-out shell, and a store that stops answering halfway through
    // a word is worse than one that waits.
    Timer {
        id: searchDebounce
        interval: 700
        repeat: false
        onTriggered: PresetStore.discover(searchField.text, 30)
    }

    NoticeBox {
        Layout.fillWidth: true
        materialIcon: "warning"
        text: Translation.tr("Presets here are published by other people and are not reviewed by this project. Applying one changes your settings and can hand it whatever those settings are allowed to run. Use them at your own discretion — no responsibility is taken for what one does to your system.")
    }

    ConfigRow {
        Layout.fillWidth: true
        Layout.preferredHeight: 48

        ToolbarTextField {
            id: searchField
            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholderText: Translation.tr("Search presets…")
            font.pixelSize: Appearance.font.pixelSize.normal
            onTextChanged: searchDebounce.restart()
            onAccepted: {
                searchDebounce.stop();
                PresetStore.discover(searchField.text, 30, true);
            }
        }

        RippleButtonWithIcon {
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh")
            Layout.fillHeight: true
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            enabled: !PresetStore.discovering
            onClicked: {
                searchDebounce.stop();
                PresetStore.discover(searchField.text, 30, true);
                PresetStore.checkUpdates(true);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            text: Translation.tr("Sort by")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }

        Repeater {
            model: [
                { "mode": 0, "icon": "star", "label": Translation.tr("Stars") },
                { "mode": 1, "icon": "schedule", "label": Translation.tr("Recently updated") },
                { "mode": 2, "icon": "sort_by_alpha", "label": Translation.tr("Name") }
            ]

            delegate: RippleButtonWithIcon {
                required property var modelData
                readonly property bool picked: root.sortMode === modelData.mode

                materialIcon: modelData.icon
                mainText: modelData.label
                colBackground: picked ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: picked ? Appearance.colors.colPrimaryContainerHover
                    : Appearance.colors.colLayer2Hover
                colRipple: picked ? Appearance.colors.colPrimaryContainerActive
                    : Appearance.colors.colLayer2Active
                colText: picked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                onClicked: root.sortMode = modelData.mode
            }
        }

        Item { Layout.fillWidth: true }

        StyledText {
            visible: !PresetStore.discovering && PresetStore.discoverError.length === 0
            text: Translation.tr("%1 found").arg(root.results.length)
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    StyledIndeterminateProgressBar {
        Layout.fillWidth: true
        visible: PresetStore.discovering
    }

    Rectangle {
        Layout.fillWidth: true
        visible: PresetStore.discoverError.length > 0
        implicitHeight: errorRow.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.colors.colErrorContainer

        RowLayout {
            id: errorRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12
            spacing: 8

            MaterialSymbol {
                text: "cloud_off"
                iconSize: 18
                color: Appearance.colors.colOnErrorContainer
            }

            StyledText {
                Layout.fillWidth: true
                text: PresetStore.discoverError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 20
        spacing: 6
        visible: !PresetStore.discovering && PresetStore.discoverError.length === 0
            && root.results.length === 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "travel_explore"
            iconSize: 44
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: searchField.text.length > 0
                ? Translation.tr("Nothing published under that name yet.")
                : Translation.tr("No presets have been published yet. Yours could be the first.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: resultFlow.implicitHeight
        visible: root.results.length > 0

        Flow {
            id: resultFlow
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 15

            readonly property int minWidth: 250
            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (minWidth + spacing)))
            readonly property real itemWidth: Math.floor((width - (columns - 1) * spacing) / columns)

            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Repeater {
                model: root.results

                delegate: StoreResultCard {
                    required property var modelData
                    entry: modelData
                    width: resultFlow.itemWidth
                    onActivated: root.openDetails(modelData)
                }
            }
        }
    }
}
