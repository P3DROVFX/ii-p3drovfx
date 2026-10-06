pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.dock
import qs.modules.settings.configs.dockUtilities
import "../../../ii/dock/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * Dock → Widgets & buttons: everything on the dock that is not an app.
 *
 * The hero is the dock live with its apps left out, so what this page changes is
 * all that is on it. Under it every widget the dock can hold — its own (media,
 * weather…) and the utility tiles — then its buttons, each a card that draws the
 * real item; then the widget stack and the small details in their original
 * sections, and the folders. Options of an item open as a sub-page from its card.
 * Search indexes sections/DockWidgetsSection.qml for the cards.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var dock: Config.options.dock
    readonly property int itemCount: stage.count

    function cleanDockFolderPath(path: string): string {
        let cleanPath = String(path ?? "").trim().replace(/^file:\/\//, "");
        try {
            cleanPath = decodeURIComponent(cleanPath);
        } catch (error) {
            // Keep the original path if a file manager returns malformed URI data.
        }
        if (cleanPath.length > 1)
            cleanPath = cleanPath.replace(/\/+$/, "");
        return cleanPath;
    }
    function addDockFolder(path: string) {
        const cleanPath = subPageRoot.cleanDockFolderPath(path);
        if (cleanPath)
            TaskbarApps.addPinnedFile(cleanPath);
    }
    function removeDockFolder(index: int) {
        const folders = Array.from(Config.options.dock.pinnedFiles ?? []);
        if (index >= 0 && index < folders.length)
            TaskbarApps.removePinnedFile(folders[index]);
    }
    function moveDockFolder(index: int, direction: int) {
        const folders = Config.options.dock.pinnedFiles ?? [];
        const targetIndex = index + direction;
        if (targetIndex < 0 || targetIndex >= folders.length)
            return;
        TaskbarApps.reorderPinnedFileByIndex(index, targetIndex);
    }

    FolderDialog {
        id: dockFolderDialog
        title: Translation.tr("Choose a folder for the dock")
        currentFolder: "file://" + Quickshell.env("HOME")
        onAccepted: subPageRoot.addDockFolder(selectedFolder.toString())
    }

    // Geometry for the cards' items: the dock's own, laid out flat.
    DockPreviewContext {
        id: cardContext
        live: stage.live
        dockPos: "bottom"
        dockWidgetsActive: subPageRoot.visible
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
                text: Translation.tr("Widgets & buttons")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Hero: the dock without its apps, live ──────────────────────────
        DockPreviewStage {
            id: stage
            Layout.fillWidth: true
            Layout.preferredHeight: stage.preferredHeight
            hiddenTypes: ["app", "appGroup"]

            Rectangle {
                id: heroTag
                anchors.left: parent.left
                anchors.margins: 11
                y: stage.pillEdge === "top" ? 11 : stage.height - height - 11
                height: tagColumn.implicitHeight + 12
                width: Math.min(stage.width - 22, tagColumn.implicitWidth + 36)
                radius: Math.min(height / 2, Appearance.rounding.large)
                color: Appearance.colors.colSurfaceContainerHigh

                ColumnLayout {
                    id: tagColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("On your dock")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: !stage.dockOn ? Translation.tr("The dock is off")
                            : subPageRoot.itemCount === 0 ? Translation.tr("Only apps so far · turn something on below")
                            : subPageRoot.itemCount === 1 ? Translation.tr("1 item besides the apps · drag on the dock to move it")
                            : Translation.tr("%1 items besides the apps · drag on the dock to move them").arg(subPageRoot.itemCount)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ── The dock's own widgets ─────────────────────────────────────────
        CardGroup {
            title: Translation.tr("Widgets")
            minCard: 260

            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "media" })
                slots: 3
                symbol: "play_circle"
                title: Translation.tr("Media")
                hasContent: MprisController.activePlayer !== null
                emptyHint: Translation.tr("Nothing playing")
                summary: Translation.tr("The playing track with its controls; shown while a player is active")
                stateText: (subPageRoot.dock.widgetStackItems ?? []).indexOf("media") >= 0 && subPageRoot.dock.enableWidgetStack ? Translation.tr("In the stack") : Translation.tr("On the dock")
                checked: subPageRoot.dock.enableMediaWidget
                onToggled: value => Config.options.dock.enableMediaWidget = value
            }
            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "weather" })
                slots: 3
                symbol: "cloud"
                title: Translation.tr("Weather")
                summary: Translation.tr("Current conditions for your location")
                stateText: (subPageRoot.dock.widgetStackItems ?? []).indexOf("weather") >= 0 && subPageRoot.dock.enableWidgetStack ? Translation.tr("In the stack") : Translation.tr("On the dock")
                checked: subPageRoot.dock.enableWeatherWidget
                onToggled: value => Config.options.dock.enableWeatherWidget = value
            }
            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "tasks" })
                slots: 3
                symbol: "checklist"
                title: Translation.tr("Tasks")
                summary: Translation.tr("Open tasks from the provider set in Tasks & Accounts; complete them from the dock")
                stateText: (subPageRoot.dock.widgetStackItems ?? []).indexOf("tasks") >= 0 && subPageRoot.dock.enableWidgetStack ? Translation.tr("In the stack") : Translation.tr("On the dock")
                checked: subPageRoot.dock.enableTasksWidget ?? false
                onToggled: value => Config.options.dock.enableTasksWidget = value
            }
            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "sports" })
                slots: 4
                symbol: "sports_soccer"
                title: Translation.tr("Sports")
                hasContent: SportsService.allGames.length > 0
                emptyHint: Translation.tr("No games right now")
                summary: Translation.tr("Live scores; shown while a monitored league has games, on a horizontal dock")
                stateText: SportsService.allGames.length > 0 ? Translation.tr("On the dock") : Translation.tr("Waiting for games")
                checked: subPageRoot.dock.enableSportsWidget ?? true
                onToggled: value => Config.options.dock.enableSportsWidget = value
            }
            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "livePreview" })
                slots: Math.max(2, Math.min(6, subPageRoot.dock.livePreviewSlots ?? 2))
                symbol: "live_tv"
                title: Translation.tr("Live Preview")
                summary: Translation.tr("A live picture of one app's window; the most demanding widget")
                stateText: String(subPageRoot.dock.livePreviewAppId ?? "").length > 0 ? subPageRoot.dock.livePreviewAppId : Translation.tr("No app chosen")
                checked: subPageRoot.dock.enableLivePreviewWidget ?? false
                configurable: true
                onConfigureRequested: subPageRoot.activeSubPage = Qt.resolvedUrl("DockLivePreviewConfig.qml")
                onToggled: value => Config.options.dock.enableLivePreviewWidget = value
            }
            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "phone" })
                slots: 1
                symbol: "smartphone"
                title: Translation.tr("Phone mirror")
                summary: Translation.tr("Your phone's screen in a window, from the dock")
                stateText: Translation.tr("On the dock")
                checked: subPageRoot.dock.showPhoneButton ?? true
                onToggled: value => Config.options.dock.showPhoneButton = value
            }
        }

        // ── Utility widgets, by group ──────────────────────────────────────
        DockUtilityCardGrid {
            Layout.fillWidth: true
            Layout.topMargin: 12
            onConfigureRequested: info => subPageRoot.activeSubPage = Qt.resolvedUrl("../dockUtilities/" + info.file + "Config.qml")
        }

        // ── Buttons ────────────────────────────────────────────────────────
        CardGroup {
            title: Translation.tr("Buttons")
            minCard: 220

            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "action", "actionId": "overview" })
                symbol: "apps"
                title: Translation.tr("Overview")
                summary: Translation.tr("Opens the overview; its icon and shape are yours to pick")
                stateText: Translation.tr("On the dock")
                checked: subPageRoot.dock.showOverviewButton
                configurable: true
                onConfigureRequested: subPageRoot.activeSubPage = Qt.resolvedUrl("DockOverviewButtonConfig.qml")
                onToggled: value => Config.options.dock.showOverviewButton = value
            }
            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "action", "actionId": "pin" })
                symbol: "keep"
                title: Translation.tr("Pin")
                summary: Translation.tr("Keeps the dock on screen, or lets it hide again")
                stateText: Translation.tr("On the dock")
                checked: subPageRoot.dock.showPinButton
                onToggled: value => Config.options.dock.showPinButton = value
            }
            DockWidgetCard {
                context: cardContext
                itemData: ({ "type": "action", "actionId": "trash" })
                symbol: "delete"
                title: Translation.tr("Trash")
                summary: Translation.tr("Drop files on it to delete them; click to open the trash")
                stateText: Translation.tr("On the dock")
                checked: subPageRoot.dock.showTrashButton
                onToggled: value => Config.options.dock.showTrashButton = value
            }
        }

        // ── Widget stack ───────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Widget stack")
            icon: "stacks"
            tooltip: Translation.tr("Put several widgets in one slot and turn between them with the mouse wheel.")

            ConfigSwitch {
                buttonIcon: "stacks"
                text: Translation.tr("Stack widgets")
                checked: subPageRoot.dock.enableWidgetStack ?? false
                onCheckedChanged: Config.options.dock.enableWidgetStack = checked
                StyledToolTip {
                    text: Translation.tr("Widgets in the stack share one slot and leave their own place on the dock. Scroll over the stack to turn the page; only the page on show is loaded")
                }
            }

            ContentSubsection {
                visible: subPageRoot.dock.enableWidgetStack ?? false
                title: Translation.tr("Widgets in the stack")
                icon: "widgets"

                ConfigRow {
                    uniform: true
                    StackMemberSwitch {
                        member: "media"
                        buttonIcon: "play_circle"
                        text: Translation.tr("Media")
                        tooltipText: Translation.tr("Shown while a player is active")
                    }
                    StackMemberSwitch {
                        member: "weather"
                        buttonIcon: "cloud"
                        text: Translation.tr("Weather")
                        tooltipText: Translation.tr("Current conditions for your location")
                    }
                }
                ConfigRow {
                    uniform: true
                    StackMemberSwitch {
                        member: "tasks"
                        buttonIcon: "checklist"
                        text: Translation.tr("Tasks")
                        tooltipText: Translation.tr("Open tasks; complete or delete them from the dock")
                    }
                    StackMemberSwitch {
                        member: "sports"
                        buttonIcon: "sports_soccer"
                        text: Translation.tr("Sports")
                        tooltipText: Translation.tr("Shown while a monitored league has games")
                    }
                }
                ConfigRow {
                    uniform: true
                    StackMemberSwitch {
                        member: "livePreview"
                        buttonIcon: "live_tv"
                        text: Translation.tr("Live Preview")
                        tooltipText: Translation.tr("Its capture runs only while its page is on show")
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // ── Details ────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Details")
            icon: "tune"

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Notification badges")
                    checked: subPageRoot.dock.showNotificationBadges
                    onCheckedChanged: Config.options.dock.showNotificationBadges = checked
                    StyledToolTip {
                        text: Translation.tr("A count on the icon of an app with unread notifications")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "vertical_split"
                    text: Translation.tr("Dividers")
                    checked: subPageRoot.dock.showDividers
                    onCheckedChanged: Config.options.dock.showDividers = checked
                    StyledToolTip {
                        text: Translation.tr("Lines between the apps, the widgets and the buttons. The Islands style never draws them")
                    }
                }
            }
        }

        // ── Folders ────────────────────────────────────────────────────────
        Rectangle {
            id: foldersPane
            Layout.fillWidth: true
            Layout.topMargin: 12
            readonly property var folders: subPageRoot.dock.pinnedFiles ?? []
            implicitHeight: foldersColumn.implicitHeight + 40
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: foldersColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    MaterialShapeWrappedMaterialSymbol {
                        text: "folder_special"
                        iconSize: 24
                        padding: 12
                        fill: 1
                        shape: addFolderButton.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie7Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Folders")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: foldersPane.folders.length === 0 ? Translation.tr("Directories on the dock, a click away")
                                : foldersPane.folders.length === 1 ? Translation.tr("1 folder on the dock")
                                : Translation.tr("%1 folders on the dock, in this order").arg(foldersPane.folders.length)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                    RippleButton {
                        id: addFolderButton
                        implicitHeight: 44
                        implicitWidth: foldersPane.width < 460 ? implicitHeight : addRow.implicitWidth + 36
                        buttonRadius: height / 2
                        buttonRadiusPressed: Appearance.rounding.small
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: dockFolderDialog.open()
                        StyledToolTip {
                            visible: foldersPane.width < 460 && addFolderButton.hovered
                            text: Translation.tr("Add folder")
                        }
                        contentItem: Item {
                            RowLayout {
                                id: addRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: "create_new_folder"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    visible: foldersPane.width >= 460
                                    text: Translation.tr("Add folder")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }
                }

                // One grouped shape: outer corners large, joins small.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: foldersPane.folders.length > 0
                    spacing: 3

                    Repeater {
                        model: foldersPane.folders

                        delegate: Rectangle {
                            id: folderRow
                            required property string modelData
                            required property int index
                            readonly property bool first: folderRow.index === 0
                            readonly property bool last: folderRow.index === foldersPane.folders.length - 1

                            Layout.fillWidth: true
                            implicitHeight: 62
                            topLeftRadius: folderRow.first ? Appearance.rounding.large : Appearance.rounding.verysmall
                            topRightRadius: folderRow.first ? Appearance.rounding.large : Appearance.rounding.verysmall
                            bottomLeftRadius: folderRow.last ? Appearance.rounding.large : Appearance.rounding.verysmall
                            bottomRightRadius: folderRow.last ? Appearance.rounding.large : Appearance.rounding.verysmall
                            color: rowHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                            HoverHandler {
                                id: rowHover
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                spacing: 12

                                MaterialShapeWrappedMaterialSymbol {
                                    text: "folder"
                                    iconSize: 18
                                    padding: 8
                                    fill: 1
                                    shape: rowHover.hovered ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                                    color: Appearance.colors.colSecondaryContainer
                                    colSymbol: Appearance.colors.colOnSecondaryContainer
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const parts = folderRow.modelData.split("/").filter(part => part.length > 0);
                                            return parts[parts.length - 1] ?? folderRow.modelData;
                                        }
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: folderRow.modelData
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideMiddle
                                    }
                                }

                                RowAction {
                                    symbol: "arrow_upward"
                                    enabled: !folderRow.first
                                    tip: Translation.tr("Move folder up")
                                    onClicked: subPageRoot.moveDockFolder(folderRow.index, -1)
                                }
                                RowAction {
                                    symbol: "arrow_downward"
                                    enabled: !folderRow.last
                                    tip: Translation.tr("Move folder down")
                                    onClicked: subPageRoot.moveDockFolder(folderRow.index, 1)
                                }
                                RowAction {
                                    symbol: "close"
                                    danger: true
                                    tip: Translation.tr("Remove folder from dock")
                                    onClicked: subPageRoot.removeDockFolder(folderRow.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }

    // A titled group of cards in columns balanced over the rows they need, so no
    // row ends with a lone straggler; every card carries its own width.
    component CardGroup: ColumnLayout {
        id: group
        property string title: ""
        property real minCard: 260
        default property alias cards: cardFlow.data
        readonly property real gap: 10
        readonly property int count: cardFlow.children.length
        readonly property int maxCols: Math.max(1, Math.floor((width + gap) / (minCard + gap)))
        readonly property int rows: Math.max(1, Math.ceil(group.count / group.maxCols))
        readonly property int cols: Math.max(1, Math.ceil(group.count / group.rows))
        /** Rows as even as the count allows (7 over three rows is 3 + 2 + 2, never 3 + 3 + 1). */
        function widthAt(index) {
            const base = Math.floor(group.count / group.rows);
            const extra = group.count % group.rows;
            let start = 0;
            for (let row = 0; row < group.rows; row++) {
                const inRow = base + (row < extra ? 1 : 0);
                if (index < start + inRow)
                    return Math.floor((group.width - group.gap * (inRow - 1)) / inRow);
                start += inRow;
            }
            return group.width;
        }
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 10

        StyledText {
            Layout.leftMargin: 4
            text: group.title
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer0
        }
        Flow {
            id: cardFlow
            Layout.fillWidth: true
            spacing: group.gap
            onChildrenChanged: {
                for (let i = 0; i < cardFlow.children.length; i++) {
                    const index = i;
                    cardFlow.children[i].width = Qt.binding(() => group.widthAt(index));
                }
            }
        }
    }

    // A small row action tinted with the row's content; `danger` turns error on hover.
    component RowAction: RippleButton {
        id: action
        property string symbol: ""
        property string tip: ""
        property bool danger: false
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: height / 2
        opacity: action.enabled ? 1 : 0.35
        colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.06)
        colBackgroundHover: action.danger ? Appearance.colors.colErrorContainer : ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.14)
        colRipple: action.danger ? Appearance.colors.colErrorContainerActive : ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.22)
        contentItem: MaterialSymbol {
            text: action.symbol
            iconSize: 18
            horizontalAlignment: Text.AlignHCenter
            color: action.danger && action.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
        }
        StyledToolTip {
            text: action.tip
        }
    }

    // One stack membership: adds or removes `member` from
    // dock.widgetStackItems, keeping the order the members were added in.
    component StackMemberSwitch: ConfigSwitch {
        id: memberSwitch
        property string member: ""
        property string tooltipText: ""
        checked: (Config.options.dock.widgetStackItems ?? []).indexOf(memberSwitch.member) >= 0
        onCheckedChanged: {
            const items = Array.from(Config.options.dock.widgetStackItems ?? []);
            const index = items.indexOf(memberSwitch.member);
            if (checked && index < 0)
                items.push(memberSwitch.member);
            else if (!checked && index >= 0)
                items.splice(index, 1);
            else
                return;
            Config.options.dock.widgetStackItems = items;
        }
        StyledToolTip {
            text: memberSwitch.tooltipText
        }
    }
}
