import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * Main pane: pick a sport, then tap competitions to follow them. Names and
 * crests come from ESPN; the ones popular in your region come first, the full
 * list after (searchable, folded until asked). The header subtitle states the
 * current value and names a competition while the pointer is over it.
 */
Rectangle {
    id: root

    property var model: null
    property var catalog: null
    property string sport: "soccer"
    property string hoveredName: ""
    property bool showAll: false

    readonly property var entry: root.catalog?.leagues[root.sport] ?? null
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var popular: root.entry?.popular ?? []
    readonly property var everything: root.entry?.all ?? []
    readonly property var filtered: root.query === "" ? [] : root.everything.filter(item => item.name.toLowerCase().indexOf(root.query) !== -1
        || item.short.toLowerCase().indexOf(root.query) !== -1 || item.slug.toLowerCase().indexOf(root.query) !== -1)
    readonly property var rest: root.everything.filter(item => !root.popular.some(other => other.slug === item.slug))
    readonly property int foldedCount: 18
    readonly property int followedHere: (root.model?.leagues ?? []).filter(item => item?.sport === root.sport).length

    // Grid geometry: balanced columns so no group ends with a lone card.
    readonly property real gridWidth: width - 40
    readonly property int maxCols: Math.max(1, Math.floor((root.gridWidth + 8) / (200 + 8)))

    implicitHeight: column.implicitHeight + 40
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    onSportChanged: {
        root.showAll = false;
        search.text = "";
        root.catalog?.load(root.sport);
    }
    Component.onCompleted: root.catalog?.load(root.sport)
    onVisibleChanged: if (visible) root.catalog?.load(root.sport)

    // Fix names saved as slugs ("Eng 1") once the real ones are known.
    onEverythingChanged: {
        const followed = (root.model?.leagues ?? []).filter(item => item?.sport === root.sport);
        followed.forEach(item => {
            const known = root.everything.find(other => other.slug === item.league);
            if (known && (known.name !== item.name || (known.logo ?? "") !== (item.logo ?? "")))
                Qt.callLater(() => root.model.refreshName(root.sport, known));
        });
    }

    component LeagueGrid: Flow {
        id: grid
        property var items: []
        readonly property int rows: Math.max(1, Math.ceil(grid.items.length / root.maxCols))
        readonly property int cols: Math.max(1, Math.ceil(grid.items.length / grid.rows))
        readonly property real cellWidth: Math.floor((width - 8 * (grid.cols - 1)) / grid.cols)
        Layout.fillWidth: true
        spacing: 8
        visible: grid.items.length > 0

        Repeater {
            model: grid.items
            delegate: RippleButton {
                id: card
                required property var modelData
                readonly property bool followed: root.model?.isFollowed(root.sport, card.modelData.slug) ?? false
                width: grid.cellWidth
                implicitHeight: 64
                buttonRadius: card.followed ? Appearance.rounding.normal : Appearance.rounding.large
                buttonRadiusPressed: Appearance.rounding.small
                toggled: card.followed
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                onClicked: root.model?.toggle(root.sport, card.modelData)
                onHoveredChanged: root.hoveredName = card.hovered ? card.modelData.name : (root.hoveredName === card.modelData.name ? "" : root.hoveredName)

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 21
                        color: Appearance.m3colors.m3surfaceContainerHighest
                        CrestImage {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            url: card.modelData.logo
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                            cache: true
                            visible: card.modelData.logo !== ""
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: card.modelData.logo === ""
                            text: root.catalog?.sportById(root.sport)?.icon ?? "sports"
                            iconSize: 20
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.name
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: card.followed ? Font.Bold : Font.Medium
                        color: card.followed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                    MaterialSymbol {
                        visible: card.followed
                        text: "check_circle"
                        fill: 1
                        iconSize: 22
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }

    component GroupLabel: StyledText {
        Layout.topMargin: 6
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.variableAxes: ({ "wght": 800, "wdth": 120, "ROND": 0 })
        font.letterSpacing: 1.5
        color: Appearance.colors.colOnSurfaceVariant
    }

    ColumnLayout {
        id: column
        x: 20
        y: 20
        width: root.width - 40
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            MaterialShapeWrappedMaterialSymbol {
                text: root.catalog?.sportById(root.sport)?.icon ?? "sports"
                iconSize: 24
                padding: 12
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Competitions")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.hoveredName !== "" ? root.hoveredName
                        : root.followedHere === 0 ? Translation.tr("%1 · nothing followed yet").arg(root.catalog?.sportById(root.sport)?.label ?? "")
                        : Translation.tr("%1 · %2 followed").arg(root.catalog?.sportById(root.sport)?.label ?? "").arg(root.followedHere)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Sports
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.catalog?.sports ?? []
                delegate: ColorsChip {
                    required property var modelData
                    readonly property int followed: (root.model?.leagues ?? []).filter(item => item?.sport === modelData.id).length
                    symbol: modelData.icon
                    label: modelData.label
                    chosen: root.sport === modelData.id
                    count: followed > 0 ? followed : -1
                    onClicked: root.sport = modelData.id
                }
            }
        }

        // Search
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: search.activeFocus ? Appearance.rounding.large : height / 2
            color: search.activeFocus ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.colors.colLayer2
            Behavior on radius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 10
                spacing: 8
                MaterialShapeWrappedMaterialSymbol {
                    text: "search"
                    iconSize: 18
                    padding: 8
                    shape: search.activeFocus ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Clover4Leaf
                    color: Appearance.colors.colSecondaryContainer
                    colSymbol: Appearance.colors.colOnSecondaryContainer
                }
                ToolbarTextField {
                    id: search
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    colBackground: "transparent"
                    placeholderText: Translation.tr("Search %1 competitions").arg(root.everything.length > 0 ? root.everything.length : "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: root.entry?.loading === true
        }
        StyledText {
            visible: (root.entry?.error ?? "") !== ""
            text: root.entry?.error ?? ""
            color: Appearance.colors.colSubtext
        }

        // Search results
        GroupLabel {
            visible: root.query !== ""
            text: (root.filtered.length > 0 ? Translation.tr("%1 matches").arg(root.filtered.length) : Translation.tr("No competition with that name")).toUpperCase()
        }
        LeagueGrid {
            items: root.query !== "" ? root.filtered.slice(0, 60) : []
        }

        // Popular in your region
        GroupLabel {
            visible: root.query === "" && root.popular.length > 0
            text: Translation.tr("Popular in your region").toUpperCase()
        }
        LeagueGrid {
            items: root.query === "" ? root.popular : []
        }

        // Everything else
        GroupLabel {
            visible: root.query === "" && root.rest.length > 0
            text: (root.popular.length > 0 ? Translation.tr("More competitions") : Translation.tr("All competitions")).toUpperCase()
        }
        LeagueGrid {
            items: root.query !== "" ? [] : (root.showAll ? root.rest : root.rest.slice(0, root.foldedCount))
        }
        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignHCenter
            visible: root.query === "" && root.rest.length > root.foldedCount
            materialIcon: root.showAll ? "expand_less" : "expand_more"
            mainText: root.showAll ? Translation.tr("Show fewer") : Translation.tr("Show all %1").arg(root.rest.length)
            onClicked: root.showAll = !root.showAll
        }
    }
}
