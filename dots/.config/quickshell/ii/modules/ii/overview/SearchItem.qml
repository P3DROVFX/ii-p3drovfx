import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland

RippleButton {
    id: root
    property var entry
    property string query
    property bool entryShown: entry?.shown ?? true
    property string itemType: entry?.type ?? Translation.tr("App")
    property string itemName: entry?.name ?? ""
    property var iconType: entry?.iconType
    property string iconName: entry?.iconName ?? ""
    property var itemExecute: entry?.execute
    property var fontType: switch (entry?.fontType) {
    case LauncherSearchResult.FontType.Monospace:
        return "monospace";
    case LauncherSearchResult.FontType.Normal:
        return "main";
    default:
        return "main";
    }
    property string itemClickActionName: entry?.verb ?? "Open"
    property string bigText: entry?.iconType === LauncherSearchResult.IconType.Text ? entry?.iconName ?? "" : ""
    property string materialSymbol: entry?.iconType === LauncherSearchResult.IconType.Material ? entry?.iconName ?? "" : ""
    property string cliphistRawString: entry?.rawValue ?? ""
    property string filePath: Images.isValidImageByName(entry?.name) ? entry?.name : ""
    property bool blurImage: entry?.blurImage ?? false

    readonly property string artUrl: MprisController.artUrl || ""
    readonly property bool isLocalArt: artUrl.startsWith("file://")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`

    // Art is downloaded by SearchWidget. We just reference the cached file path.
    readonly property string artSource: {
        if (!artUrl) return "";
        if (isLocalArt) return artUrl;
        return Qt.resolvedUrl(artFilePath); // SearchWidget ensures this exists
    }

    onArtFilePathChanged: {
        // Art downloading is managed by SearchWidget
    }

    function formatMathResult(raw) {
        if (!raw)
            return {
                expression: "",
                value: ""
            };
        let parts = raw.split("=");
        if (parts.length >= 2) {
            let lhs = parts[0].trim();
            let rhs = parts.slice(1).join("=").trim();

            // Clean up LHS
            lhs = lhs.replace(/\s*\*\s*/g, " ").replace(/\bdeg\s*\*\s*/gi, "°").replace(/\bdeg\b/gi, "°");

            // Clean up RHS
            rhs = rhs.replace(/\s*\*\s*/g, " ").replace(/\bdeg\s*\*\s*/gi, "°").replace(/\bdeg\b/gi, "°").replace(/\bapprox\.\s*/gi, "≈ ");

            return {
                expression: lhs,
                value: rhs
            };
        }
        return {
            expression: "",
            value: raw
        };
    }

    property bool actionPanelOpen: false
    readonly property bool isNowPlaying: root.itemType === Translation.tr("Now Playing")
    readonly property bool isBuiltinItem: (root.entry?.key?.startsWith("mock:") || root.entry?.key?.startsWith("shortcut:")) || !!root.entry?.isBuiltin
    readonly property var entryActions: entry?.actions ?? []
    readonly property bool hasCustomActions: root.entryActions.length > 0
    readonly property bool hasActions: root.hasCustomActions || root.itemType === Translation.tr("App")

    visible: root.entryShown
    property int horizontalMargin: 10
    property int buttonHorizontalPadding: 10
    property int buttonVerticalPadding: 8
    property bool keyboardDown: false
    opacity: 1
    scale: 1.0

    property int listIndex: 0
    property int listCount: ListView.view ? ListView.view.count : 1
    property int listCurrentIndex: ListView.view ? ListView.view.currentIndex : -1

    readonly property bool isFirst: listIndex === 0
    readonly property bool isLast: listIndex === listCount - 1
    readonly property bool isSelected: listIndex === listCurrentIndex
    readonly property bool isAboveSelected: listCurrentIndex === listIndex + 1 && listCurrentIndex !== -1
    readonly property bool isBelowSelected: listCurrentIndex === listIndex - 1 && listCurrentIndex !== -1
    readonly property real pillRadius: Math.min(height / 2, Appearance.rounding.large)
    readonly property int activeHIndex: root.actionPanelOpen ? root.actionSelectedIndex + 1 : 0

    readonly property real contractedWidth: 160
    readonly property real actionBtnSpacing: 4
    readonly property real actionBtnPadY: 4

    property var allActionItems: {
        // Lazy: only compute when this item is selected or action panel is open.
        // Avoids creating closures for every off-screen / unselected item.
        if (!root.isSelected && !root.actionPanelOpen)
            return [];

        let items = [];
        items.push({
            name: root.itemClickActionName || Translation.tr("Open"),
            icon: "open_in_new",
            execute: () => {
                const isSystemControl = root.entry?.key?.startsWith("sys:");
                const cmdKey = isSystemControl ? root.entry.key.slice(4) : "";
                const isConfirming = isSystemControl && LauncherSearch.confirmKey !== cmdKey;
                const isModeSwitch = (root.entry?.key?.startsWith("mock:") && root.entry?.key !== "mock:settings") || (root.entry?.key?.startsWith("shortcut:") && root.entry?.key !== "shortcut:openSettings") || root.itemType === Translation.tr("Folder Alias");

                root.actionPanelOpen = false;
                if (!isConfirming && !isModeSwitch) {
                    GlobalStates.overviewOpen = false;
                }
                root.itemExecute();
            }
        });
        if (root.entry?.type === Translation.tr("App")) {
            const isPinned = TaskbarApps.isPinned(root.entry.id);
            items.push({
                name: isPinned ? Translation.tr("Unpin from Dock") : Translation.tr("Pin to Dock"),
                icon: isPinned ? "keep_off" : "keep",
                execute: () => {
                    TaskbarApps.togglePin(root.entry.id);
                    root.actionPanelOpen = false;
                }
            });
            items.push({
                name: Translation.tr("Copy ID"),
                icon: "content_copy",
                execute: () => {
                    Quickshell.clipboardText = root.entry.id;
                    root.actionPanelOpen = false;
                }
            });
            items.push({
                name: Translation.tr("Reset"),
                icon: "restart_alt",
                execute: () => {
                    AppUsage.resetRanking(root.entry.id);
                    root.actionPanelOpen = false;
                }
            });
        }
        if (root.contentType === "filepath" || root.itemType === Translation.tr("Directory") || root.itemType === Translation.tr("Folder Alias")) {
            const isDir = root.itemType === Translation.tr("Directory") || root.itemType === Translation.tr("Folder Alias") || FileUtils.isDirectory(root.itemName);
            if (isDir) {
                const pinnedFiles = Config.options?.dock?.pinnedFiles ?? [];
                const cleanPath = root.itemName.toString().replace(/^file:\/\//, "");
                const isPinned = pinnedFiles.includes(cleanPath);

                items.push({
                    name: isPinned ? Translation.tr("Unpin folder from Dock") : Translation.tr("Pin folder to Dock"),
                    icon: isPinned ? "folder_off" : "create_new_folder",
                    execute: () => {
                        if (isPinned) {
                            TaskbarApps.removePinnedFile(root.itemName);
                        } else {
                            TaskbarApps.addPinnedFile(root.itemName);
                        }
                        root.actionPanelOpen = false;
                    }
                });
            }
        }
        const ea = root.entry?.actions ?? [];
        for (const action of ea) {
            items.push({
                name: action.name,
                icon: action.iconName || "play_arrow",
                nativeIcon: action.iconType === LauncherSearchResult.IconType.System,
                execute: () => {
                    root.actionPanelOpen = false;
                    GlobalStates.overviewOpen = false;
                    action.execute();
                }
            });
        }
        return items;
    }

    property int actionSelectedIndex: 0

    property real normalHeight: 48
    onActionPanelOpenChanged: {
        if (actionPanelOpen) {
            normalHeight = root.height > 0 ? root.height : contentRow.implicitHeight + buttonVerticalPadding * 2;
        }
    }

    function executeSelectedAction() {
        if (actionSelectedIndex >= 0 && actionSelectedIndex < allActionItems.length)
            allActionItems[actionSelectedIndex].execute();
    }

    implicitHeight: {
        if (isNowPlaying)
            return nowPlayingLoader.item ? nowPlayingLoader.item.implicitHeight + buttonVerticalPadding * 2 : 80;
        if (root.actionPanelOpen)
            return normalHeight;
        return contentRow.implicitHeight + buttonVerticalPadding * 2;
    }
    implicitWidth: contentRow.implicitWidth + root.buttonHorizontalPadding * 2

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 350
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    buttonRadius: 0

    colBackground: root.isBuiltinItem ? ((root.down || root.keyboardDown || isSelected) ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colTertiaryContainer) : ((root.down || root.keyboardDown) ? Appearance.colors.colPrimaryContainerActive : (isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh))
    colBackgroundHover: root.isBuiltinItem ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colPrimaryContainerActive
    property color colForeground: root.isBuiltinItem ? Appearance.colors.colOnTertiaryContainer : (isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface)

    readonly property string highlightPrefix: `<u><font color="${Appearance.colors.colPrimary}">`
    readonly property string highlightSuffix: `</font></u>`
    function highlightContent(content, query) {
        if (!query || query.length === 0 || content == query || fontType === "monospace")
            return StringUtils.escapeHtml(content);
        let contentLower = content.toLowerCase();
        let queryLower = query.toLowerCase();
        let result = "";
        let lastIndex = 0;
        let qIndex = 0;
        for (let i = 0; i < content.length && qIndex < query.length; i++) {
            if (contentLower[i] === queryLower[qIndex]) {
                if (i > lastIndex)
                    result += StringUtils.escapeHtml(content.slice(lastIndex, i));
                result += root.highlightPrefix + StringUtils.escapeHtml(content[i]) + root.highlightSuffix;
                lastIndex = i + 1;
                qIndex++;
            }
        }
        if (lastIndex < content.length)
            result += StringUtils.escapeHtml(content.slice(lastIndex));
        return result;
    }
    property string displayContent: {
        // Skip highlight computation when selected — text shows itemName directly
        if (root.isSelected) return "";
        return highlightContent(root.itemName, root.query);
    }

    property list<string> urls: {
        if (!root.itemName)
            return [];
        const urlRegex = /https?:\/\/[^\s<>"{}|\\^`[\]]+/gi;
        const matches = root.itemName?.match(urlRegex)?.filter(url => !url.includes("…"));
        return matches ? matches : [];
    }

    property string contentType: entry?.category ?? ""

    PointingHandInteraction {}

    background: Rectangle {
        id: bgRect
        anchors.fill: root
        anchors.leftMargin: root.horizontalMargin
        anchors.rightMargin: root.horizontalMargin
        color: "transparent"
        antialiasing: true
        clip: true

        topLeftRadius: root.isFirst ? Appearance.rounding.large : (root.isSelected || root.isBelowSelected ? root.pillRadius : Appearance.rounding.small)
        topRightRadius: topLeftRadius
        bottomLeftRadius: root.isLast ? Appearance.rounding.large : (root.isSelected || root.isAboveSelected ? root.pillRadius : Appearance.rounding.small)
        bottomRightRadius: bottomLeftRadius

        Behavior on topLeftRadius {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }
        Behavior on bottomLeftRadius {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
            }
        }

        Row {
            id: slideRow
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: root.actionBtnSpacing

            x: {
                if (!root.actionPanelOpen)
                    return 0;
                let visibleW = bgRect.width;
                let itemW = itemRect.width + root.actionBtnSpacing;
                let btnX = itemW;
                for (let i = 0; i < root.actionSelectedIndex; i++) {
                    let btn = actionRepeater.itemAt(i);
                    btnX += (btn ? btn.width : 0) + root.actionBtnSpacing;
                }
                let selBtn = actionRepeater.itemAt(root.actionSelectedIndex);
                let selW = selBtn ? selBtn.width : 0;
                let selRight = btnX + selW;
                if (selRight <= visibleW)
                    return 0;
                return -(selRight - visibleW + 4);
            }

            Behavior on x {
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            Rectangle {
                id: itemRect
                width: root.actionPanelOpen ? root.contractedWidth : bgRect.width
                height: slideRow.height
                y: 0
                topLeftRadius: bgRect.topLeftRadius
                topRightRadius: root.actionPanelOpen ? (root.activeHIndex === 0 || root.activeHIndex === 1 ? root.pillRadius : Appearance.rounding.small) : bgRect.topRightRadius
                bottomLeftRadius: bgRect.bottomLeftRadius
                bottomRightRadius: root.actionPanelOpen ? (root.activeHIndex === 0 || root.activeHIndex === 1 ? root.pillRadius : Appearance.rounding.small) : bgRect.bottomRightRadius
                color: root.actionPanelOpen ? (root.isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh) : root.colBackground
                clip: true
                antialiasing: true

                Behavior on width {
                    NumberAnimation {
                        duration: 375
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.15
                    }
                }

                // Only animate topLeft - the other radii mirror it and
                // animating all 4 independently costs 4x animation overhead per item
                Behavior on topLeftRadius {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on topRightRadius {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on bottomLeftRadius {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on bottomRightRadius {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    visible: root.actionPanelOpen
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.actionPanelOpen = false
                }

                RowLayout {
                    id: contentRow
                    spacing: root.actionPanelOpen ? 6 : 10
                    anchors.fill: parent
                    anchors.leftMargin: root.buttonHorizontalPadding
                    anchors.rightMargin: root.buttonHorizontalPadding
                    visible: !root.isNowPlaying

                    Item {
                        id: iconContainer
                        Layout.preferredWidth: iconVisible ? 36 : 0
                        Layout.preferredHeight: 36
                        visible: iconVisible
                        readonly property bool iconVisible: root.iconType !== LauncherSearchResult.IconType.None

                        Item {
                            anchors.fill: parent
                            visible: root.iconType === LauncherSearchResult.IconType.System

                            MaterialShape {
                                id: iconShapeBg
                                anchors.fill: parent
                                shape: MaterialShape.Shape.Cookie7Sided
                                color: (root.isSelected || root.actionPanelOpen) ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 80
                                    }
                                }

                                transform: Scale {
                                    origin.x: iconContainer.width / 2
                                    origin.y: iconContainer.height / 2
                                    xScale: root.isSelected && !root.actionPanelOpen ? 1.06 : 1.0
                                    yScale: root.isSelected && !root.actionPanelOpen ? 1.06 : 1.0
                                    Behavior on xScale {
                                        NumberAnimation {
                                            duration: 80
                                            easing.type: Easing.OutBack
                                        }
                                    }
                                    Behavior on yScale {
                                        NumberAnimation {
                                            duration: 80
                                            easing.type: Easing.OutBack
                                        }
                                    }
                                }
                            }

                            IconImage {
                                source: Quickshell.iconPath(root.iconName, "image-missing")
                                anchors.centerIn: parent
                                implicitSize: 22
                                smooth: true
                                Behavior on implicitSize {
                                    NumberAnimation {
                                        duration: 150
                                    }
                                }
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.iconType === LauncherSearchResult.IconType.Material
                            text: root.materialSymbol
                            iconSize: 26
                            color: root.colForeground
                            Behavior on iconSize {
                                NumberAnimation {
                                    duration: 150
                                }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            visible: root.iconType === LauncherSearchResult.IconType.Text

                            MaterialShape {
                                anchors.fill: parent
                                shape: MaterialShape.Shape.Sunny
                                color: root.isSelected ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSurfaceContainerHighest
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 80
                                    }
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: root.bigText
                                font.pixelSize: root.actionPanelOpen ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.normal
                                color: root.isSelected ? Appearance.colors.colOnTertiaryContainer : root.colForeground
                            }
                        }
                    }

                    Rectangle {
                        width: 14
                        height: 14
                        radius: Appearance.rounding.full
                        color: root.itemName || "transparent"
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant
                        visible: root.contentType === "hex-color" && !root.actionPanelOpen
                    }

                    ColumnLayout {
                        id: contentColumn
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0
                        visible: !root.actionPanelOpen

                        RowLayout {
                            spacing: 4
                            visible: (root.itemType && root.itemType != Translation.tr("App") && !root.entry?.isMath) || (!!root.entry?.comment && !root.entry?.isMath)

                            StyledText {
                                text: root.itemType
                                color: root.isBuiltinItem ? Appearance.colors.colOnTertiaryContainer : (root.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.main
                                opacity: (root.isBuiltinItem || root.isSelected) ? 1.0 : 0.7
                                visible: root.itemType && root.itemType != Translation.tr("App") && !root.entry?.isMath
                            }

                            StyledText {
                                text: "•"
                                color: root.isBuiltinItem ? Appearance.colors.colOnTertiaryContainer : (root.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                opacity: 0.5
                                visible: (root.itemType && root.itemType != Translation.tr("App") && !root.entry?.isMath) && (!!root.entry?.comment && !root.entry?.isMath)
                            }

                            StyledText {
                                text: root.entry?.comment ?? ""
                                color: root.isBuiltinItem ? Appearance.colors.colOnTertiaryContainer : (root.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.main
                                visible: !!root.entry?.comment && !root.entry?.isMath
                                opacity: 0.7
                            }
                        }

                        RowLayout {
                            visible: !root.entry?.isMath
                            Rectangle {
                                implicitWidth: activeText.implicitHeight
                                implicitHeight: activeText.implicitHeight
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colPrimary
                                visible: itemName == Quickshell.clipboardText && root.cliphistRawString
                                MaterialSymbol {
                                    id: activeText
                                    anchors.centerIn: parent
                                    text: "check"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.m3colors.m3onPrimary
                                }
                            }

                            MaterialSymbol {
                                visible: root.contentType !== "" && root.contentType !== "hex-color" && root.contentType !== "clipboard"
                                text: {
                                    switch (root.contentType) {
                                    case "url":
                                        return "link";
                                    case "email":
                                        return "alternate_email";
                                    case "phone":
                                        return "phone";
                                    case "json":
                                        return "data_object";
                                    case "filepath":
                                        return "folder_open";
                                    case "markdown":
                                        return "markdown";
                                    case "number":
                                        return "tag";
                                    case "multiline":
                                        return "notes";
                                    default:
                                        return "";
                                    }
                                }
                                iconSize: Appearance.font.pixelSize.normal
                                color: root.colForeground
                            }

                            Repeater {
                                model: root.query == root.itemName ? [] : root.urls
                                Favicon {
                                    required property var modelData
                                    size: parent.height
                                    url: modelData
                                }
                            }

                            StyledText {
                                id: nameText
                                Layout.fillWidth: true
                                textFormat: Text.StyledText
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: (root.fontType === "monospace" || root.contentType === "json") ? Appearance.font.family.monospace : Appearance.font.family.main
                                color: root.colForeground
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                text: root.isSelected ? root.itemName : root.displayContent
                            }
                        }

                        // Structured Math & Unit Conversion breakdown
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !!root.entry?.isMath
                            spacing: 4

                            StyledText {
                                text: Translation.tr("Math & Unit Converter")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                font.family: Appearance.font.family.main
                                opacity: 0.7
                            }

                            RowLayout {
                                spacing: 8
                                Layout.fillWidth: true

                                // Input Expression
                                StyledText {
                                    text: {
                                        let parsed = root.formatMathResult(root.itemName);
                                        return parsed.expression || root.query;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.monospace
                                    color: root.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }

                                // Elegant Arrow Indicator
                                MaterialSymbol {
                                    text: "arrow_forward"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colPrimary
                                }

                                // Evaluated Result
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        let parsed = root.formatMathResult(root.itemName);
                                        return parsed.value;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.monospace
                                    font.bold: true
                                    color: root.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                                }
                            }
                        }

                        Loader {
                            active: root.cliphistRawString && Cliphist.entryIsImage(root.cliphistRawString)
                            sourceComponent: CliphistImage {
                                Layout.fillWidth: true
                                entry: root.cliphistRawString
                                maxWidth: contentColumn.width
                                maxHeight: 140
                                blur: root.blurImage
                            }
                        }

                        Loader {
                            active: root.filePath != ""
                            sourceComponent: FileSearchImage {
                                Layout.fillWidth: true
                                imagePath: root.filePath
                                maxWidth: contentColumn.width
                                maxHeight: 140
                                blur: Config.options.search.blurFileSearchResultPreviews
                            }
                        }
                    }

                    StyledText {
                        visible: root.actionPanelOpen
                        Layout.fillWidth: true
                        text: root.itemName
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.main
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                    }

                    Item {
                        id: actionIndicator
                        readonly property bool shouldShow: root.isSelected && !root.actionPanelOpen && root.allActionItems.length > 1
                        visible: (shouldShow || indicatorAnim.running) && !root.actionPanelOpen
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 44
                        implicitHeight: 16
                        opacity: shouldShow ? 1.0 : 0.0
                        scale: shouldShow ? 1.0 : 0.7
                        Behavior on opacity {
                            NumberAnimation {
                                id: indicatorAnim
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutBack
                            }
                        }
                        Row {
                            anchors.centerIn: parent
                            spacing: 2
                            Rectangle {
                                width: 26
                                height: 16
                                radius: 3
                                color: Appearance.colors.colSurfaceContainerHighest
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Ctrl"
                                    font.pixelSize: 9
                                    font.family: Appearance.font.family.main
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                            Rectangle {
                                width: 14
                                height: 16
                                radius: 3
                                color: Appearance.colors.colSurfaceContainerHighest
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "K"
                                    font.pixelSize: 9
                                    font.family: Appearance.font.family.main
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }

                Loader {
                    id: nowPlayingLoader
                    active: root.isNowPlaying
                    visible: root.isNowPlaying
                    anchors.fill: parent
                    anchors.leftMargin: root.buttonHorizontalPadding
                    anchors.rightMargin: root.buttonHorizontalPadding
                    anchors.topMargin: root.buttonVerticalPadding
                    anchors.bottomMargin: root.buttonVerticalPadding

                    sourceComponent: RowLayout {
                        spacing: 14

                        Item {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.large
                                color: Appearance.colors.colSurfaceContainerHighest
                            }

                            Image {
                                anchors.fill: parent
                                source: root.artSource
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                visible: source !== ""
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: 56
                                        height: 56
                                        radius: Appearance.rounding.large
                                    }
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "music_note"
                                iconSize: 28
                                color: Appearance.colors.colOnSurfaceVariant
                                visible: root.artSource === ""
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: MprisController.activePlayer?.trackTitle || Translation.tr("Nothing playing")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                font.family: Appearance.font.family.main
                                color: root.colForeground
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            StyledText {
                                text: MprisController.activePlayer?.trackArtist || ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.main
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                visible: text !== ""
                            }
                        }

                        RippleButton {
                            implicitWidth: 44
                            implicitHeight: 44
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            visible: !root.actionPanelOpen
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: MprisController.isPlaying ? "pause" : "play_arrow"
                                iconSize: 26
                                color: Appearance.m3colors.m3onPrimary
                            }
                            onClicked: MprisController.togglePlaying()
                        }
                    }
                }
            }

            Repeater {
                id: actionRepeater
                model: root.allActionItems

                delegate: Rectangle {
                    id: actionBtn
                    required property var modelData
                    required property int index
                    readonly property bool isActionSelected: root.actionSelectedIndex === index
                    readonly property int hIdx: index + 1
                    readonly property bool isBtnActive: root.isSelected && isActionSelected

                    width: actionBtnContent.implicitWidth + 24
                    height: slideRow.height
                    y: 0
                    topLeftRadius: hIdx === root.activeHIndex || (hIdx - 1) === root.activeHIndex ? root.pillRadius : Appearance.rounding.small
                    bottomLeftRadius: topLeftRadius
                    topRightRadius: hIdx === root.allActionItems.length ? root.pillRadius : (hIdx === root.activeHIndex || (hIdx + 1) === root.activeHIndex ? root.pillRadius : Appearance.rounding.small)
                    bottomRightRadius: topRightRadius

                    color: isBtnActive ? Appearance.colors.colPrimaryContainer : (root.isSelected && actionBtnMa.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighest)
                    visible: root.actionPanelOpen || opacity > 0.0
                    opacity: root.actionPanelOpen ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 80
                        }
                    }
                    Behavior on topLeftRadius {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on topRightRadius {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on bottomLeftRadius {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on bottomRightRadius {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                    }

                    MouseArea {
                        id: actionBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: actionBtn.modelData.execute()
                        onEntered: root.actionSelectedIndex = actionBtn.index
                    }

                    RowLayout {
                        id: actionBtnContent
                        anchors.centerIn: parent
                        spacing: 8
                        Layout.leftMargin: 6
                        Layout.rightMargin: 10

                        Item {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36

                            MaterialShape {
                                anchors.fill: parent
                                shape: actionBtn.isBtnActive ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Cookie7Sided
                                color: actionBtn.isBtnActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 80
                                    }
                                }
                            }

                            IconImage {
                                anchors.centerIn: parent
                                visible: actionBtn.modelData.nativeIcon ?? false
                                source: visible ? Quickshell.iconPath(actionBtn.modelData.icon, "image-missing") : ""
                                implicitSize: 22
                                smooth: true
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !(actionBtn.modelData.nativeIcon ?? false)
                                text: actionBtn.modelData.icon || "play_arrow"
                                iconSize: 22
                                fill: actionBtn.isBtnActive ? 1 : 0
                                color: actionBtn.isBtnActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnSurfaceVariant
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 80
                                    }
                                }
                            }
                        }

                        StyledText {
                            text: actionBtn.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.main
                            font.weight: Font.Medium
                            color: actionBtn.isBtnActive ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                            Behavior on color {
                                ColorAnimation {
                                    duration: 80
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    onClicked: {
        if (root.actionPanelOpen) {
            root.actionPanelOpen = false;
            return;
        }
        if (root.isNowPlaying) {
            MprisController.togglePlaying();
            return;
        }

        const isSystemControl = root.entry?.key?.startsWith("sys:");
        const cmdKey = isSystemControl ? root.entry.key.slice(4) : "";
        const isConfirming = isSystemControl && LauncherSearch.confirmKey !== cmdKey;
        const isModeSwitch = (root.entry?.key?.startsWith("mock:") && root.entry?.key !== "mock:settings") || (root.entry?.key?.startsWith("shortcut:") && root.entry?.key !== "shortcut:openSettings") || root.itemType === Translation.tr("Folder Alias");

        if (!isConfirming && !isModeSwitch) {
            GlobalStates.overviewOpen = false;
        }
        root.itemExecute();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
            const deleteAction = root.entry.actions.find(action => action.name == Translation.tr("Delete"));
            if (deleteAction)
                deleteAction.execute();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.actionPanelOpen) {
                root.executeSelectedAction();
            } else {
                root.keyboardDown = true;
                root.clicked();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.actionPanelOpen) {
            root.actionPanelOpen = false;
            event.accepted = true;
        } else if (root.actionPanelOpen && event.key === Qt.Key_Left) {
            root.actionSelectedIndex = Math.max(0, root.actionSelectedIndex - 1);
            event.accepted = true;
        } else if (root.actionPanelOpen && event.key === Qt.Key_Right) {
            root.actionSelectedIndex = Math.min(root.allActionItems.length - 1, root.actionSelectedIndex + 1);
            event.accepted = true;
        } else if (root.actionPanelOpen && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            root.actionPanelOpen = false;
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = false;
            event.accepted = true;
        }
    }
}
