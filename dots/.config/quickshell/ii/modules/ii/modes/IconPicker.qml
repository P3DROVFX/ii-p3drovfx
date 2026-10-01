pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

/**
 * Material Symbols picker, as a side sheet beside the editor: the header the icon goes
 * on stays in sight, so each pick shows at once and the sheet stays open to try another.
 * Opens on a curated shelf of icons that suit a mode; typing searches the full catalogue
 * (names and tags), which is only parsed the first time it is needed.
 *
 * Built by a ClockSidePanel (`show(component, { current })`); `picked(name)` fires on
 * every choice, Enter in the search takes the first match.
 */
ClockSheet {
    id: root

    property string current: ""
    property string query: ""
    property var allIcons: []
    property bool loaded: false
    property bool wantLoad: false

    signal picked(string name)

    // Mirrored in AiModesIntegration.iconShelf; the contract test pins the two together.
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

    function choose(name: string): void {
        root.current = name;
        root.picked(name);
    }

    title: Translation.tr("Choose an icon")
    subtitle: root.query.length
        ? (root.loaded ? Translation.tr("%1 match(es)").arg(root.results.length) : Translation.tr("Loading catalogue…"))
        : Translation.tr("Type to search all symbols")
    scrollable: false

    onQueryChanged: {
        if (root.query.length)
            root.wantLoad = true;
    }

    Component.onCompleted: Qt.callLater(search.focusInput)

    FileView {
        id: symbolsFile
        // Bound to nothing until the first search, so the 1.7 MB catalogue is never read
        // for a user who only picks from the shelf.
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

    ClockFormField {
        id: search
        symbol: "search"
        shapeKind: MaterialShape.Shape.Cookie12Sided
        caption: Translation.tr("Search")
        placeholder: Translation.tr("Search symbols")
        onTextChanged: root.query = text
        onAccepted: {
            if (root.results.length)
                root.choose(root.results[0]);
        }
    }

    GridView {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        readonly property int columns: Math.max(4, Math.floor(width / 60))
        cellWidth: Math.floor(width / columns)
        cellHeight: 60
        model: root.results

        delegate: Item {
            id: cell
            required property string modelData
            readonly property bool isCurrent: cell.modelData === root.current

            width: grid.cellWidth
            height: grid.cellHeight

            RippleButton {
                anchors.centerIn: parent
                implicitWidth: 52
                implicitHeight: 52
                buttonRadius: cell.isCurrent ? ClockStyle.radiusNormal : ClockStyle.pill(52)
                buttonRadiusPressed: ClockStyle.radiusSmall
                colBackground: cell.isCurrent ? ClockStyle.colPrimary : "transparent"
                colBackgroundHover: cell.isCurrent ? ClockStyle.colPrimaryHover : ClockStyle.colFieldHover
                colRipple: cell.isCurrent ? ClockStyle.colPrimaryActive : ClockStyle.colSurfaceActive
                onClicked: root.choose(cell.modelData)

                StyledToolTip {
                    text: cell.modelData
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: cell.modelData
                    iconSize: 26
                    fill: cell.isCurrent ? 1 : 0
                    color: cell.isCurrent ? ClockStyle.colOnPrimary : ClockStyle.colOnSurface
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: grid.count === 0
            text: Translation.tr("No symbol matches")
            font.pixelSize: ClockStyle.textNormal
            color: ClockStyle.colSubtext
        }

        TouchpadScrollHandler {
            flickable: grid
        }
    }

    actions: [
        ClockSheetAction {
            primary: true
            symbol: "check"
            label: Translation.tr("Done")
            onClicked: root.close()
        }
    ]
}
