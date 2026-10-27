pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import qs.modules.ii.dock.utilities

/*
 * Favorites: the dock's favorite sites on the desktop, one click each - the
 * same list, edited in Settings → Dock → Favorites. Four slots, as a 2x2 grid
 * (1x1) or a single row (1x0.5). Each favicon sits on a rounded plate that
 * rounds into a circle under the pointer; an empty slot is a "+" that opens
 * the list's editor. Dropping a link from the browser on the card adds it.
 */
ExpressiveCardWidget {
    id: root

    // "grid" (2x2, 1x1) or "row" (1x4, 1x0.5); set by the wrappers.
    property string arrangement: "grid"
    readonly property bool row: root.arrangement === "row"

    designWidth: 240
    designHeight: root.row ? 120 : 240
    cardRadius: root.row ? Appearance.rounding.verylarge : Appearance.rounding.large

    readonly property int slotCount: 4
    readonly property real padding: root.row ? 12 : 14
    readonly property real gap: root.row ? 8 : 10
    readonly property bool showLabels: root.options?.showLabels ?? true

    readonly property var sites: Array.from(Config.options?.dock?.utilities?.favorites?.sites ?? [])
        .filter(site => site && String(site.url ?? "").length > 0)
    property bool dragOver: false

    function urlOf(site) {
        let url = String(site.url).trim();
        if (!/^[a-z][a-z0-9+.-]*:/i.test(url))
            url = "https://" + url;
        return url;
    }
    function open(site) {
        if (root.actionsEnabled)
            Qt.openUrlExternally(root.urlOf(site));
    }
    function editFavorites() {
        if (root.actionsEnabled)
            GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml");
    }
    // A link dropped from a browser joins the list, named after its host.
    function addLinks(urls) {
        if (!root.actionsEnabled)
            return;
        const list = Array.from(Config.options.dock.utilities.favorites.sites ?? []);
        for (const raw of urls) {
            const url = String(raw).trim();
            if (!/^https?:\/\//i.test(url) || list.some(site => site.url === url))
                continue;
            list.push({ title: url.replace(/^https?:\/\/(www\.)?/i, "").split("/")[0], url: url });
        }
        Config.options.dock.utilities.favorites.sites = list;
    }

    onCardTapped: at => {
        const slot = slots.childAt(at.x - slots.x, at.y - slots.y);
        if (slot && slot.empty !== undefined)
            slot.empty ? root.editFavorites() : root.open(slot.site);
    }

    DropArea {
        anchors.fill: parent
        enabled: root.actionsEnabled
        keys: ["text/uri-list"]
        onEntered: drag => {
            root.dragOver = Array.from(drag.urls ?? []).some(url => /^https?:\/\//i.test(String(url)));
        }
        onExited: root.dragOver = false
        onDropped: drop => {
            root.dragOver = false;
            root.addLinks(Array.from(drop.urls ?? []));
            drop.accept(Qt.CopyAction);
        }
    }

    // ── One slot: a site, or the way to add one ──
    component Slot: Item {
        id: slot

        property var site: null
        readonly property bool empty: slot.site === null
        readonly property real plateSize: root.showLabels
            ? Math.min(slot.width, slot.height - labelText.height - 4)
            : Math.min(slot.width, slot.height)
        readonly property bool hovered: slotHover.hovered && root.actionsEnabled

        HoverHandler {
            id: slotHover
            cursorShape: Qt.PointingHandCursor
        }

        Item {
            id: plate
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.showLabels ? 0 : (slot.height - height) / 2
            width: slot.plateSize
            height: slot.plateSize
            scale: slot.hovered && root.pressed ? 0.92 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            SiteIcon {
                anchors.fill: parent
                visible: !slot.empty
                url: slot.site?.url ?? ""
                title: slot.site?.title ?? ""
                colPlate: WidgetColorScheme.pillBgColor
                iconScale: root.row ? 0.68 : 0.6
                // Rounded square at rest; a circle under the pointer.
                radius: slot.hovered ? width / 2 : Math.round(width * 0.3)
                Behavior on radius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: slot.empty
                radius: slot.hovered ? width / 2 : Math.round(width * 0.3)
                color: slot.hovered ? WidgetColorScheme.pillFillColor : WidgetColorScheme.pillBgColor
                Behavior on radius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: Math.round(parent.width * 0.42)
                    color: slot.hovered ? WidgetColorScheme.textColorOnPillFill : WidgetColorScheme.subtextColorOnBg
                }
            }
        }

        StyledText {
            id: labelText
            visible: root.showLabels
            anchors.top: plate.bottom
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            width: slot.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: slot.empty ? Translation.tr("Add") : (slot.site.title || String(slot.site.url).replace(/^https?:\/\/(www\.)?/i, ""))
            color: slot.empty ? WidgetColorScheme.subtextColorOnBg : WidgetColorScheme.textColorOnBg
            font.pixelSize: root.row ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
            font.variableAxes: ({ "wght": 600, "wdth": 90, "ROND": 100 })
        }

        StyledToolTip {
            text: slot.empty ? Translation.tr("Add favorites in Settings") : (slot.site.title || slot.site.url)
            extraVisibleCondition: slot.hovered
        }
    }

    Grid {
        id: slots
        anchors.fill: parent
        anchors.margins: root.padding
        columns: root.row ? root.slotCount : 2
        spacing: root.gap
        opacity: root.dragOver ? 0.2 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        readonly property real cellWidth: (slots.width - slots.spacing * (slots.columns - 1)) / slots.columns
        readonly property real cellHeight: root.row ? slots.height : (slots.height - slots.spacing) / 2

        Repeater {
            model: root.slotCount

            delegate: Slot {
                required property int index
                width: slots.cellWidth
                height: slots.cellHeight
                site: index < root.sites.length ? root.sites[index] : null
            }
        }
    }

    // ── A link held over the card ──
    Item {
        anchors.fill: parent
        opacity: root.dragOver ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialShape {
            anchors.centerIn: parent
            width: root.row ? 76 : 120
            height: width
            shape: MaterialShape.Shape.Clover4Leaf
            color: WidgetColorScheme.accentColor
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "bookmark_add"
            iconSize: root.row ? 32 : 48
            fill: 1
            color: WidgetColorScheme.onAccentColor
        }
    }
}
