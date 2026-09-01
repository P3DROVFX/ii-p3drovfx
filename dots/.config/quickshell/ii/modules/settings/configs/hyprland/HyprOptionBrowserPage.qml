pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The whole option list, filtered by section and by search.
 *
 * This is the tab's escape hatch, so it is deliberately the one page in the hub that does not
 * explain anything: the curated tabs are where an option gets a name, a range and a sentence
 * about what it does. Here the key is the label, because the key is what Hyprland's own
 * documentation is written in and what a search for help will turn up.
 *
 * The values come from `hyprctl getoption`, one batch per screenful of new keys rather than one
 * call per row, and only for keys nothing has asked about yet - so scrolling back over a section
 * costs nothing and re-filtering costs nothing either.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    /// Which section the tab opened this on. "" is everything.
    property string section: ""
    property string rawQuery: ""
    readonly property string query: subPageRoot.rawQuery.trim()
    /// One row is open at a time: two editors on screen at once is two places to look.
    property string expandedKey: ""

    readonly property var chips: [{ "id": "", "title": "Everything", "icon": "list", "count": 0 }]
        .concat(Array.from(HyprlandCatalog.sections)
            .filter(entry => entry.id !== "debug" || HyprlandCatalog.showDebug))

    readonly property var filtered: {
        const all = HyprlandCatalog.search(subPageRoot.query, HyprlandCatalog.showDebug);
        if (subPageRoot.section === "") return all;
        return all.filter(entry => entry.section === subPageRoot.section);
    }

    readonly property int hiddenDebug: HyprlandCatalog.showDebug ? 0
        : HyprlandCatalog.search(subPageRoot.query, true)
            .filter(entry => entry.section === "debug").length

    /**
     * Fetch the effective value of everything on the list that nothing has fetched yet.
     *
     * Skipping what is already known is what makes typing in the search box free: the same keys
     * come back round on every keystroke, and asking hyprctl about them again would be a process
     * per letter.
     */
    function fetch(force: bool) {
        const wanted = subPageRoot.filtered.map(entry => entry.key)
            .filter(key => force || HyprlandGui.effective[key] === undefined);
        if (wanted.length === 0) return;
        HyprlandGui.refreshEffective(wanted);
    }

    onFilteredChanged: fetchDebounce.restart()

    Timer {
        id: fetchDebounce
        interval: 140
        onTriggered: subPageRoot.fetch(false)
    }

    /**
     * A reload changes values this page is showing, and it does not go through the hub's own
     * watch list: these keys are read for as long as the browser is open and dropped when it
     * closes, instead of being added to what the whole hub re-reads after every write.
     */
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "configreloaded") return;
            reloadDebounce.restart();
        }
    }

    Timer {
        id: reloadDebounce
        interval: 300
        onTriggered: subPageRoot.fetch(true)
    }

    component SectionChip: RippleButton {
        id: chip

        required property var entry

        readonly property bool current: chip.entry.id === subPageRoot.section

        implicitHeight: 34
        implicitWidth: chipRow.implicitWidth + 24
        buttonRadius: Appearance.rounding.full
        colBackground: chip.current ? Appearance.colors.colPrimaryContainer
            : Appearance.colors.colLayer2
        colBackgroundHover: chip.current ? Appearance.colors.colPrimaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: chip.current ? Appearance.colors.colPrimaryContainerActive
            : Appearance.colors.colLayer2Active
        onClicked: subPageRoot.section = chip.entry.id

        contentItem: RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: chip.entry.icon
                iconSize: 16
                color: chip.current ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colSubtext
            }

            StyledText {
                text: Translation.tr(chip.entry.title)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.current ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer2
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                visible: subPageRoot.showBackButton
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

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Every option")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: subPageRoot.filtered.length === HyprlandCatalog.entries.length
                        ? Translation.tr("%1 options, straight from the compositor")
                            .arg(HyprlandCatalog.entries.length)
                        : Translation.tr("%1 of %2 options")
                            .arg(subPageRoot.filtered.length).arg(HyprlandCatalog.entries.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        MaterialTextField {
            Layout.fillWidth: true
            wrapMode: TextInput.NoWrap
            placeholderText: Translation.tr("Search every option")
            onTextChanged: subPageRoot.rawQuery = text
        }

        // Twenty-two of these do not fit at any window width worth having, so the row scrolls
        // rather than wrapping into four lines of chips above a short list.
        Flickable {
            Layout.fillWidth: true
            implicitHeight: 34
            contentWidth: chipStrip.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: chipStrip
                spacing: 6

                Repeater {
                    model: subPageRoot.chips

                    delegate: SectionChip {
                        required property var modelData

                        entry: modelData
                    }
                }
            }
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2
            clip: true
            // Three hundred rows re-entering on every letter typed is not an animation, it is a
            // stutter. Rows appear as they are scrolled to instead.
            animateAppearance: false
            model: subPageRoot.filtered

            delegate: HyprOptionRow {
                required property var modelData

                width: list.width
                entry: modelData
                showSection: subPageRoot.section === ""
                expanded: subPageRoot.expandedKey === modelData.key
                onToggled: subPageRoot.expandedKey =
                    subPageRoot.expandedKey === modelData.key ? "" : modelData.key
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: subPageRoot.filtered.length === 0
            text: Translation.tr("Nothing matches “%1”.").arg(subPageRoot.query)
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            visible: subPageRoot.hiddenDebug > 0
            text: Translation.tr("%1 debugging options are hidden. They are switched on under Advanced, back on the All options tab.")
                .arg(subPageRoot.hiddenDebug)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    /// Land where the tab asked for, opened and in view. Done here rather than through bindings
    /// so that the first tap on a chip takes the page over for good.
    Component.onCompleted: {
        const key = HyprlandCatalog.browseKey;
        const entry = key === "" ? null : HyprlandCatalog.entryFor(key);
        subPageRoot.section = entry !== null ? entry.section : HyprlandCatalog.browseSection;
        subPageRoot.expandedKey = entry !== null ? entry.key : "";
        subPageRoot.fetch(false);
        if (entry === null) return;
        const at = subPageRoot.filtered.findIndex(item => item.key === entry.key);
        if (at >= 0) list.positionViewAtIndex(at, ListView.Center);
    }
}
