import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property string tooltip: ""
    property var customBackgroundColor: undefined
    property list<string> stringMap: []
    default property alias contentData: sectionContent.data

    Layout.fillWidth: true
    spacing: 12

    property string pageId: ""
    property string subPage: ""
    // Search results clone a small, safe subset of the original controls.
    // Their original ConfigSubPageHost is not part of that clone, so child
    // navigation controls use this marker to route through SettingsWindow.
    property bool searchResult: false
    property bool collapsible: false
    property bool expanded: true
    readonly property bool performanceMode: Config.options?.appearance?.settingsPerformanceMode ?? false

    function navigateToPage(subPageOverride) {
        if (!root.pageId || root.pageId === "")
            return;
        const win = root.QsWindow.window;
        if (!win || win.pageIndexById === undefined)
            return;
        const idx = win.pageIndexById(root.pageId);
        if (idx < 0)
            return;

        const targetSubPage = arguments.length > 0
            ? String(subPageOverride ?? "")
            : root.subPage;
        // A section title belongs to the parent page, not necessarily to the
        // destination sub-page. Highlight only page-level deep links.
        win.pendingSectionHighlight = targetSubPage === "" ? root.title : "";
        win.pendingSubPage = targetSubPage;

        if (win.currentPage === idx) {
            if (win.pendingSubPage && win.restoreSubPagePath) {
                win.restoreSubPagePath(win.pendingSubPage);
                win.pendingSubPage = "";
            }
            SearchRegistry.currentSearch = targetSubPage === "" ? root.title : "";
            win.pendingSectionHighlight = "";
        } else {
            win.currentPage = idx;
        }
    }

    // NOTE: The `page` id (declared in the consuming ContentPage file, e.g.
    // `WidgetsConfig.qml`) is NOT accessible from this separate component file
    // because QML ids do not propagate across file boundaries. So we resolve
    // the containing Flickable at runtime by walking the parent chain.
    // (Previously this used `page` which threw `ReferenceError: page is not
    // defined` and silently broke the scroll + highlight feature.)
    property Flickable flickable: null

    function findFlickable() {
        var p = parent;
        while (p) {
            if (p.flickableDirection !== undefined && p.contentY !== undefined) {
                root.flickable = p;
                return;
            }
            p = p.parent;
        }
        root.flickable = null;
    }

    Component.onCompleted: {
        findFlickable();
        // Catch a pending search that was set BEFORE this ContentSection was
        // instantiated (e.g. during the Loader's async page load). This closes
        // the race where SearchRegistry.currentSearch was already matching our
        // title before bindings could re-fire onCurrentSearchChanged.
        tryPendingHighlight();
    }

    onParentChanged: findFlickable()

    readonly property string currentSearch: SearchRegistry.currentSearch
    onCurrentSearchChanged: root.tryPendingHighlight()

    function matchesCurrent(query) {
        if (!query || query.length === 0)
            return false;
        return query.toLowerCase() === root.title.toLowerCase();
    }

    function tryPendingHighlight() {
        if (!matchesCurrent(SearchRegistry.currentSearch))
            return;
        doScrollAndHighlight();
        // Cleared on the next tick rather than here: `currentSearch` above is
        // bound to the very property being written, so clearing it inside the
        // change handler re-enters the binding and Qt reports a loop. It
        // worked, loudly. Deferring the write takes it out of the binding's
        // own evaluation.
        Qt.callLater(() => {
            if (SearchRegistry.currentSearch === root.title)
                SearchRegistry.currentSearch = "";
        });
    }

    function doScrollAndHighlight() {
        var sectionRef = root;
        Qt.callLater(() => {
            // Layout settles between frames, so Qt.callLater guarantees
            // contentHeight/flickable.height have been computed.
            if (!root.flickable)
                findFlickable();
            if (root.flickable && root.flickable.contentItem) {
                let p = root.flickable.contentItem.mapFromItem(sectionRef, 0, 0);
                let targetY = p.y - 100;
                let maxContentY = Math.max(0, root.flickable.contentHeight - root.flickable.height);
                root.flickable.contentY = Math.max(0, Math.min(targetY, maxContentY));
            }
            highlightOverlay.startAnimation();
            bgPulseAnimation.restart();
        });
    }

    function addKeyword(word) {
        if (!word)
            return;
        stringMap.push(word);
    }

    ScrollAnimate {}

    Rectangle {
        id: cardContainer
        Layout.fillWidth: true
        implicitHeight: cardInnerLayout.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: root.customBackgroundColor !== undefined ? root.customBackgroundColor : Appearance.colors.colLayer0
        border.width: root.customBackgroundColor !== undefined ? 0 : 1
        border.color: Appearance.colors.colLayer0Border

        Behavior on color {
            ColorAnimation { duration: 280; easing.type: Easing.InOutQuad }
        }

        ColumnLayout {
            id: cardInnerLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            spacing: 12

            Item {
                id: headerSurface
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight

                MouseArea {
                    id: headerMouseArea
                    anchors.fill: parent
                    hoverEnabled: root.collapsible || (root.pageId !== "" && root.pageId.length > 0)
                    cursorShape: root.collapsible || (root.pageId !== "" && root.pageId.length > 0) ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: root.collapsible || (root.pageId !== "" && root.pageId.length > 0)
                    onClicked: {
                        if (root.collapsible)
                            root.expanded = !root.expanded;
                        else
                            root.navigateToPage();
                    }
                }

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    spacing: 8

                    MaterialSymbol {
                        visible: root.icon && root.icon.length > 0
                        text: root.icon
                        iconSize: Appearance.font.pixelSize.huge
                        color: headerMouseArea.containsMouse && root.pageId ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        opacity: 1 - highlightOverlay.opacity
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        opacity: 1 - highlightOverlay.opacity
                        text: root.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        color: headerMouseArea.containsMouse && root.pageId ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        Layout.fillWidth: true

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }

                    MaterialSymbol {
                        visible: root.collapsible
                        text: "keyboard_arrow_down"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                        opacity: headerMouseArea.containsMouse ? 1.0 : 0.6
                        Layout.alignment: Qt.AlignVCenter
                        rotation: root.expanded ? 0 : -90

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }

                        Behavior on rotation {
                            NumberAnimation {
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Appearance.animation.elementMove.type
                                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                            }
                        }
                    }

                    RowLayout {
                        spacing: 4
                        visible: root.pageId !== "" && root.pageId.length > 0
                        Layout.alignment: Qt.AlignVCenter
                        opacity: headerMouseArea.containsMouse ? 1.0 : 0.65

                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }

                        StyledText {
                            readonly property var pageObj: SettingsPageRegistry.pageById(root.pageId)
                            text: pageObj ? Translation.tr(pageObj.name) : ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: headerMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }

                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: Appearance.font.pixelSize.normal
                            color: headerMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }
                    }

                    MaterialSymbol {
                        opacity: 1 - highlightOverlay.opacity
                        visible: root.tooltip && root.tooltip.length > 0
                        text: "info"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1

                        MouseArea {
                            id: infoMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.WhatsThisCursor
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: infoMouseArea.containsMouse
                                text: root.tooltip
                            }
                        }
                    }
                }
            }

            Item {
                id: sectionContentContainer
                Layout.fillWidth: true
                implicitHeight: root.expanded ? sectionContent.implicitHeight : 0
                clip: sectionContentAnim.running || sectionContentContainer.implicitHeight < sectionContent.implicitHeight

                Behavior on implicitHeight {
                    id: sectionContentAnim
                    enabled: !root.performanceMode
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                ColumnLayout {
                    id: sectionContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    opacity: root.expanded ? 1.0 : 0.0
                    spacing: 4

                    Behavior on opacity {
                        enabled: !root.performanceMode
                        NumberAnimation {
                            duration: root.expanded
                                ? Appearance.animation.elementMove.duration
                                : Appearance.animation.elementMoveFast.duration
                        }
                    }
                }
            }
        }

        HighlightOverlay {
            id: highlightOverlay
            anchors.fill: parent
            radius: cardContainer.radius
            visible: opacity > 0
        }

        SequentialAnimation {
            id: bgPulseAnimation
            ColorAnimation {
                target: cardContainer
                property: "color"
                to: Appearance.colors.colPrimaryContainer
                duration: 350
                easing.type: Easing.InOutQuad
            }
            ColorAnimation {
                target: cardContainer
                property: "color"
                to: Appearance.colors.colLayer0
                duration: 500
                easing.type: Easing.InOutQuad
            }
        }
    }
}
