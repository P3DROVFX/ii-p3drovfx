pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

/**
 * Material Symbols picker. Opens on a curated shelf of icons that suit a
 * mode; typing searches the full catalogue (names and tags), which is only
 * parsed the first time it is needed.
 */
Popup {
    id: root

    property string current: ""
    property string query: ""
    property var allIcons: []
    property bool loaded: false

    signal picked(string name)

    readonly property var shelf: [
        "tune", "bedtime", "work", "center_focus_strong", "sports_esports", "theaters", "co_present", "spa",
        "school", "menu_book", "headphones", "music_note", "movie", "videocam", "mic", "podcasts",
        "fitness_center", "directions_run", "self_improvement", "coffee", "restaurant", "nightlight",
        "wb_sunny", "flight", "home", "apartment", "commute", "directions_car", "pets", "child_care",
        "code", "terminal", "science", "biotech", "psychology", "edit_note", "draw", "brush", "palette",
        "camera", "photo_camera", "savings", "shopping_cart", "celebration", "favorite", "star", "bolt",
        "do_not_disturb_on", "notifications_off", "battery_saver", "power", "speed", "eco", "lock",
        "visibility_off", "auto_awesome", "rocket_launch", "public", "schedule", "alarm", "timer"
    ]

    readonly property var results: {
        const q = root.query.trim().toLowerCase();
        if (!q.length)
            return root.shelf;
        if (!root.loaded)
            return root.shelf.filter(n => n.indexOf(q) !== -1);
        const starts = [];
        const contains = [];
        const tagged = [];
        for (const icon of root.allIcons) {
            const n = icon.n;
            if (n.startsWith(q))
                starts.push(n);
            else if (n.indexOf(q) !== -1)
                contains.push(n);
            else if (Array.isArray(icon.t) && icon.t.some(t => t.toLowerCase().startsWith(q)))
                tagged.push(n);
            if (starts.length + contains.length + tagged.length >= 240)
                break;
        }
        return starts.concat(contains, tagged).slice(0, 240);
    }

    property bool wantLoad: false

    function ensureLoaded() {
        root.wantLoad = true;
    }

    onOpened: {
        root.query = "";
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    onQueryChanged: {
        if (root.query.length)
            root.ensureLoaded();
    }

    FileView {
        id: symbolsFile
        // Bound to nothing until the first search, so the 1.7 MB catalogue
        // is never read for a user who only picks from the shelf.
        path: root.wantLoad ? Directories.assetsPath + "/data/material_symbols.json" : ""
        onLoaded: {
            try {
                const data = JSON.parse(symbolsFile.text());
                root.allIcons = Array.isArray(data) ? data : [];
                root.loaded = true;
            } catch (e) {
                console.warn(`[IconPicker] could not parse symbol catalogue: ${e}`);
            }
        }
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 560
    height: 480
    padding: 16
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle {
        color: Appearance.colors.colScrim
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 150
        }
        NumberAnimation {
            property: "scale"
            from: 0.94
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: 120
        }
    }

    background: Rectangle {
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    contentItem: ColumnLayout {
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                text: Translation.tr("Choose an icon")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: root.query.length
                    ? (root.loaded ? Translation.tr("%1 match(es)").arg(root.results.length)
                        : Translation.tr("Loading catalogue…"))
                    : Translation.tr("Type to search all symbols")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 14
                    rightMargin: 14
                }
                spacing: 8

                MaterialSymbol {
                    text: "search"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: searchField
                    Layout.fillWidth: true
                    text: root.query
                    color: Appearance.colors.colOnLayer2
                    onTextChanged: root.query = text
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.results.length) {
                                root.picked(root.results[0]);
                                root.close();
                            }
                            event.accepted = true;
                        }
                    }

                    StyledText {
                        anchors.fill: parent
                        visible: !searchField.text.length
                        text: Translation.tr("Search symbols")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: 64
            cellHeight: 64
            model: root.results

            delegate: Item {
                id: cell
                required property string modelData
                readonly property bool isCurrent: cell.modelData === root.current

                width: grid.cellWidth
                height: grid.cellHeight

                RippleButton {
                    anchors.centerIn: parent
                    implicitWidth: 56
                    implicitHeight: 56
                    buttonRadius: Appearance.rounding.normal
                    colBackground: cell.isCurrent ? Appearance.colors.colPrimaryContainer : "transparent"
                    colBackgroundHover: cell.isCurrent ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: {
                        root.picked(cell.modelData);
                        root.close();
                    }

                    StyledToolTip {
                        text: cell.modelData
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: cell.modelData
                        iconSize: 28
                        color: cell.isCurrent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: grid.count === 0
                text: Translation.tr("No symbol matches")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
