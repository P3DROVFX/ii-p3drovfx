pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * At a Glance, after Smartspacer's widget: pages of Targets with their
 * Complications, paged horizontally (dots or arrows), stacked vertically, or
 * opened into an Expanded view with every target and complication. The data
 * lives in AtAGlanceService; this file only draws and routes taps.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "at_a_glance"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "at_a_glance")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options.background.widgets.at_a_glance
    readonly property real contentScale: (root.options.widgetSize ?? 100) / 100.0
    readonly property int widthCells: Math.max(2, Math.min(4, root.options.widthCells ?? 3))
    readonly property bool vertical: (root.options.layout ?? "horizontal") === "vertical"
    readonly property bool materialYou: root.options.materialYouStyle ?? false
    readonly property bool animate: root.options.animateChanges ?? true
    property bool expanded: false

    // "Automatic (Wallpaper Based)" tint reads the wallpaper under the widget.
    needsColText: !root.materialYou && (root.options.tintColour ?? "automatic") === "automatic"
    // Settings previews never sample the wallpaper; the theme's mode is the
    // closest guess of how light it is.
    Binding {
        when: root.isPreview
        root.dominantColor: Appearance.m3colors.darkmode ? Qt.rgba(0.1, 0.1, 0.1, 1) : Qt.rgba(0.9, 0.9, 0.9, 1)
    }

    // ── Design metrics (units) ─────────────────────────────────────────────────
    readonly property real cellWidth: 120
    readonly property real pagePadding: (root.options.extraPadding ?? false) ? 16 : 6
    readonly property real cardPadding: 16
    readonly property real pageHeight: 72
    readonly property real dotsHeight: 12
    readonly property real arrowSize: 26
    readonly property real expandedMinWidth: 380

    readonly property real designWidth: root.expanded ? Math.max(root.expandedMinWidth, root.widthCells * root.cellWidth)
        : root.widthCells * root.cellWidth + root.pagePadding * 2
    readonly property real designHeight: root.expanded ? expandedColumn.implicitHeight + root.cardPadding * 2
        : root.vertical ? Math.max(root.pageHeight, verticalColumn.implicitHeight) + root.pagePadding * 2
        : root.pageHeight + (root.reserveDots ? root.dotsHeight : 0) + root.pagePadding * 2

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    // ── Colours ────────────────────────────────────────────────────────────────
    readonly property bool cardShown: root.materialYou || root.expanded
    readonly property color colTitle: {
        if (root.cardShown)
            return WidgetColorScheme.textColorOnBg;
        switch (root.options.tintColour ?? "automatic") {
        case "white": return Qt.rgba(1, 1, 1, 1);
        case "black": return Qt.rgba(0, 0, 0, 1);
        }
        return root.colText;
    }
    readonly property color colSubtitle: root.cardShown ? WidgetColorScheme.subtextColorOnBg : Qt.alpha(root.colTitle, 0.9)
    readonly property color colAccent: root.cardShown ? WidgetColorScheme.accentColor : root.colTitle
    readonly property color colButton: root.cardShown ? WidgetColorScheme.accentColor : Qt.alpha(root.colTitle, 0.18)
    readonly property color colOnButton: root.cardShown ? WidgetColorScheme.onAccentColor : root.colTitle

    // ── Pages ──────────────────────────────────────────────────────────────────
    readonly property var pages: AtAGlanceService.shownPages
    readonly property int pageCount: root.pages.length
    property string currentKey: ""
    property int currentIndex: 0
    readonly property var currentPage: root.pages[root.currentIndex] ?? null
    readonly property bool controlsAllowed: !root.vertical && (root.options.showPageControls ?? true)
        && !(root.options.singlePage ?? false) && (root.options.pinMode ?? "none") === "none"
    readonly property bool reserveDots: root.controlsAllowed && (root.options.pageControlStyle ?? "dots") === "dots"

    // Keep the page the user is on when the list changes under it.
    onPagesChanged: {
        const i = root.pages.findIndex(p => p.key === root.currentKey);
        if (i >= 0)
            root.currentIndex = i;
        else
            root.currentIndex = Math.max(0, Math.min(root.currentIndex, root.pageCount - 1));
        root.currentKey = root.pages[root.currentIndex]?.key ?? "";
    }

    function goTo(index) {
        if (root.pageCount === 0)
            return;
        // Smartspacer's controls loop back to the first page.
        root.currentIndex = ((index % root.pageCount) + root.pageCount) % root.pageCount;
        root.currentKey = root.pages[root.currentIndex]?.key ?? "";
    }

    // ── Taps ───────────────────────────────────────────────────────────────────
    // A left click that did not become a move (same contract as
    // ExpressiveCardWidget): no MouseArea over the content, so it stays draggable.
    property bool _movedSincePress: false
    onIsDraggingChanged: {
        if (root.isDragging)
            root._movedSincePress = true;
        else
            Qt.callLater(() => root._movedSincePress = false);
    }

    onClicked: mouse => {
        if (mouse.button !== Qt.LeftButton || root._movedSincePress || root.isPreview || root.editModeActive)
            return;
        const target = root.pageDelegateAt(mouse.x, mouse.y);
        if (!target)
            return;
        const p = target.mapFromItem(root, mouse.x, mouse.y);
        const hit = target.actionAt(p.x, p.y);
        if (hit.complication) {
            AtAGlanceService.runAction(hit.action);
            return;
        }
        root.activatePage(target.page);
    }

    function activatePage(page) {
        if (!page)
            return;
        const mode = root.options.expandedOpenMode ?? "expanded";
        const canExpand = !root.expanded && (root.options.expandedEnabled ?? true);
        if (canExpand && (page.openExpanded || mode === "always" || (mode === "expanded" && page.expandedOptions))) {
            root.expanded = true;
            return;
        }
        AtAGlanceService.runAction(page.action);
    }

    function pageDelegateAt(x, y) {
        const candidates = [];
        if (root.expanded) {
            for (let i = 0; i < expandedRepeater.count; i++)
                candidates.push(expandedRepeater.itemAt(i)?.pageItem);
        } else if (root.vertical) {
            for (let i = 0; i < verticalRepeater.count; i++)
                candidates.push(verticalRepeater.itemAt(i));
        } else {
            candidates.push(pagedRepeater.itemAt(root.currentIndex));
        }
        for (const c of candidates) {
            if (!c)
                continue;
            const p = c.mapFromItem(root, x, y);
            if (p.x >= 0 && p.y >= 0 && p.x <= c.width && p.y <= c.height)
                return c;
        }
        return null;
    }

    Component.onCompleted: if (root.isPreview) AtAGlanceService.previewViewers++
    Component.onDestruction: if (root.isPreview) AtAGlanceService.previewViewers--

    // Leave the expanded view when the screen locks or the widget is edited.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { root.expanded = false; }
    }
    onEditModeActiveChanged: if (root.editModeActive) root.expanded = false

    // ── Drawing ────────────────────────────────────────────────────────────────
    Item {
        id: box
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        HoverHandler {
            id: hover
        }

        WheelHandler {
            enabled: !root.vertical && !root.expanded && root.controlsAllowed && root.pageCount > 1
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => root.goTo(root.currentIndex + (event.angleDelta.y < 0 || event.angleDelta.x < 0 ? 1 : -1))
        }

        StyledRectangularShadow {
            target: card
            visible: card.visible && (Config.options.background.widgets.enableShadows ?? true)
        }

        Rectangle {
            id: card
            anchors.fill: parent
            visible: root.cardShown
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
        }

        // Text over the wallpaper gets Smartspacer's "Text Shadow".
        Item {
            id: content
            anchors.fill: parent
            layer.enabled: !root.cardShown && (root.options.textShadow ?? true)
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Appearance.colors.colShadow
                shadowBlur: 0.45
                shadowVerticalOffset: 1
                shadowHorizontalOffset: 0
                autoPaddingEnabled: true
            }

            // ── Horizontal (paged) ─────────────────────────────────────────────
            Item {
                id: pager
                visible: !root.vertical && !root.expanded
                x: root.pagePadding
                y: root.pagePadding
                width: parent.width - root.pagePadding * 2 - (arrows.visible ? arrows.width + 6 : 0)
                height: root.pageHeight
                clip: true

                Item {
                    id: strip
                    height: parent.height
                    x: -root.currentIndex * pager.width
                    Behavior on x {
                        enabled: root.animate
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }

                    // Bound by count so a minute tick updates pages in place
                    // instead of rebuilding them.
                    Repeater {
                        id: pagedRepeater
                        model: pager.visible ? root.pageCount : 0
                        delegate: AtAGlancePage {
                            required property int index
                            x: index * pager.width
                            width: pager.width
                            height: pager.height
                            page: root.pages[index] ?? null
                            interactive: !root.isPreview
                            colTitle: root.colTitle
                            colSubtitle: root.colSubtitle
                            colAccent: root.colAccent
                            colButton: root.colButton
                            colOnButton: root.colOnButton
                            opacity: index === root.currentIndex ? 1 : 0
                            Behavior on opacity {
                                enabled: root.animate
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            onButtonActivated: action => AtAGlanceService.runAction(action)
                        }
                    }
                }
            }

            // Page dots: tap one to go there.
            Row {
                id: dots
                visible: pager.visible && root.reserveDots && root.pageCount > 1
                opacity: (root.options.invisibleControls ?? false) ? 0 : 1
                x: root.pagePadding
                y: root.pagePadding + root.pageHeight + (root.dotsHeight - height) / 2
                spacing: 6
                Repeater {
                    model: dots.visible ? root.pageCount : 0
                    delegate: Rectangle {
                        id: dot
                        required property int index
                        readonly property bool current: dot.index === root.currentIndex
                        anchors.verticalCenter: parent.verticalCenter
                        width: dot.current ? 16 : 6
                        height: 6
                        radius: 3
                        color: Qt.alpha(root.colTitle, dot.current ? 1 : 0.45)
                        Behavior on width {
                            enabled: root.animate
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.isPreview
                            onClicked: root.goTo(dot.index)
                        }
                    }
                }
            }

            // Page arrows on the right.
            Column {
                id: arrows
                visible: pager.visible && root.controlsAllowed && (root.options.pageControlStyle ?? "dots") === "arrows" && root.pageCount > 1
                opacity: (root.options.invisibleControls ?? false) ? 0 : 1
                anchors.right: parent.right
                anchors.rightMargin: root.pagePadding
                anchors.verticalCenter: pager.verticalCenter
                spacing: 2
                Repeater {
                    model: arrows.visible ? ["keyboard_arrow_up", "keyboard_arrow_down"] : []
                    delegate: RippleButton {
                        id: arrow
                        required property string modelData
                        required property int index
                        implicitWidth: root.arrowSize
                        implicitHeight: root.arrowSize
                        buttonRadius: root.arrowSize / 2
                        colBackground: "transparent"
                        colBackgroundHover: Qt.alpha(root.colTitle, 0.12)
                        colRipple: Qt.alpha(root.colTitle, 0.24)
                        onClicked: if (!root.isPreview) root.goTo(root.currentIndex + (arrow.index === 0 ? -1 : 1))
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: arrow.modelData
                            iconSize: 20
                            color: root.colTitle
                        }
                    }
                }
            }

            // Dismiss, revealed on hover, for pages that allow it.
            RippleButton {
                id: dismissButton
                visible: pager.visible && hover.hovered && !root.isPreview && (root.currentPage?.dismiss ?? null) !== null
                anchors.top: parent.top
                anchors.right: arrows.visible ? arrows.left : parent.right
                anchors.margins: 2
                implicitWidth: 24
                implicitHeight: 24
                buttonRadius: 12
                colBackground: Qt.alpha(root.colTitle, 0.14)
                colBackgroundHover: Qt.alpha(root.colTitle, 0.24)
                colRipple: Qt.alpha(root.colTitle, 0.32)
                onClicked: AtAGlanceService.dismiss(root.currentPage)
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "close"
                    iconSize: 16
                    color: root.colTitle
                }
                StyledToolTip {
                    text: Translation.tr("Dismiss")
                }
            }

            // ── Vertical (list) ────────────────────────────────────────────────
            Column {
                id: verticalColumn
                visible: root.vertical && !root.expanded
                x: root.pagePadding
                y: root.pagePadding
                width: parent.width - root.pagePadding * 2
                spacing: 2
                Repeater {
                    id: verticalRepeater
                    model: verticalColumn.visible ? root.pageCount : 0
                    delegate: AtAGlancePage {
                        required property int index
                        width: verticalColumn.width
                        height: root.pageHeight
                        page: root.pages[index] ?? null
                        interactive: !root.isPreview
                        colTitle: root.colTitle
                        colSubtitle: root.colSubtitle
                        colAccent: root.colAccent
                        colButton: root.colButton
                        colOnButton: root.colOnButton
                        onButtonActivated: action => AtAGlanceService.runAction(action)
                    }
                }
            }
        }

        // ── Expanded ───────────────────────────────────────────────────────────
        Column {
            id: expandedColumn
            visible: root.expanded
            x: root.cardPadding
            y: root.cardPadding
            width: parent.width - root.cardPadding * 2
            spacing: 10

            Item {
                width: parent.width
                height: 32
                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("At a Glance")
                    color: root.colTitle
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.family: Appearance.font.family.title
                }
                RippleButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: WidgetColorScheme.innerShapeColor
                    colBackgroundHover: Qt.alpha(root.colTitle, 0.16)
                    colRipple: Qt.alpha(root.colTitle, 0.24)
                    onClicked: root.expanded = false
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: 18
                        color: root.colTitle
                    }
                }
            }

            // Complications grid; "Complications First" puts it above the targets.
            Loader {
                width: parent.width
                active: root.expanded && (root.options.complicationsFirst ?? false)
                visible: active
                sourceComponent: complicationGridComponent
            }

            Repeater {
                id: expandedRepeater
                model: root.expanded ? AtAGlanceService.pages.length : 0
                delegate: Rectangle {
                    id: expandedPage
                    required property int index
                    property alias pageItem: pageItem
                    width: expandedColumn.width
                    height: root.pageHeight + 8
                    radius: Appearance.rounding.normal
                    color: WidgetColorScheme.innerShapeColor
                    AtAGlancePage {
                        id: pageItem
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        page: AtAGlanceService.pages[expandedPage.index] ?? null
                        interactive: !root.isPreview
                        colTitle: root.colTitle
                        colSubtitle: root.colSubtitle
                        colAccent: root.colAccent
                        colButton: root.colButton
                        colOnButton: root.colOnButton
                        onButtonActivated: action => AtAGlanceService.runAction(action)
                    }
                }
            }

            Loader {
                width: parent.width
                active: root.expanded && !(root.options.complicationsFirst ?? false)
                visible: active
                sourceComponent: complicationGridComponent
            }
        }
    }

    Component {
        id: complicationGridComponent
        Flow {
            visible: AtAGlanceService.complications.length > 0
            spacing: 8
            Repeater {
                model: root.expanded ? AtAGlanceService.complications.length : 0
                delegate: RippleButton {
                    id: chip
                    required property int index
                    readonly property var entry: AtAGlanceService.complications[chip.index] ?? null
                    visible: chip.entry !== null && String(chip.entry.text ?? "") !== ""
                    implicitHeight: 36
                    implicitWidth: chipRow.implicitWidth + 24
                    buttonRadius: 18
                    colBackground: WidgetColorScheme.innerShapeColor
                    colBackgroundHover: Qt.alpha(root.colTitle, 0.16)
                    colRipple: Qt.alpha(root.colTitle, 0.24)
                    onClicked: AtAGlanceService.runAction(chip.entry?.action ?? null)
                    contentItem: Item {
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: String(chip.entry?.iconImage ?? "") !== ""
                                source: chip.entry?.iconImage ?? ""
                                width: 20
                                height: 20
                                sourceSize: Qt.size(40, 40)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: String(chip.entry?.iconImage ?? "") === ""
                                text: chip.entry?.icon ?? ""
                                iconSize: 18
                                fill: 1
                                color: root.colAccent
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.entry?.text ?? ""
                                color: root.colTitle
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                        }
                    }
                }
            }
        }
    }
}
