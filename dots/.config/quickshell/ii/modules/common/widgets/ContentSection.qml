import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
    onCurrentSearchChanged: {
        if (matchesCurrent(SearchRegistry.currentSearch)) {
            doScrollAndHighlight();
            SearchRegistry.currentSearch = "";
        }
    }

    function matchesCurrent(query) {
        if (!query || query.length === 0)
            return false;
        return query.toLowerCase() === root.title.toLowerCase();
    }

    function tryPendingHighlight() {
        if (matchesCurrent(SearchRegistry.currentSearch)) {
            doScrollAndHighlight();
            SearchRegistry.currentSearch = "";
        }
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

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: 8

                Loader {
                    id: iconLoader
                    active: root.icon && root.icon.length > 0
                    visible: active
                    Layout.alignment: Qt.AlignVCenter
                    opacity: 1 - highlightOverlay.opacity

                    sourceComponent: MaterialSymbol {
                        text: root.icon
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    opacity: 1 - highlightOverlay.opacity
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    color: Appearance.colors.colOnLayer1
                    Layout.fillWidth: true
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

            ColumnLayout {
                id: sectionContent
                Layout.fillWidth: true
                spacing: 4
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
