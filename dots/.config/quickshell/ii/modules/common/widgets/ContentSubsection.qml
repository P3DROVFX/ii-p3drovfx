import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    property string title: ""
    property string tooltip: ""
    property string icon: ""
    default property alias contentData: sectionContent.data
    property Component headerExtra: null

    // Accordion support: when collapsible is true, clicking the header toggles expanded.
    // When collapsed, sectionContent is not loaded (saves GPU/memory for heavy previews).
    property bool collapsible: false
    property bool expanded: true

    Layout.fillWidth: true
    implicitHeight: mainLayout.implicitHeight + 16

    // Hover color when collapsible — entire header is the button
    color: headerMouseArea.containsMouse && collapsible
        ? Appearance.colors.colLayer2Hover
        : Appearance.colors.colLayer2

    Behavior on color {
        ColorAnimation { duration: 150 }
    }

    readonly property GroupPosition groupPosition: GroupPosition {
        item: root
    }
    readonly property int itemIndex: groupPosition.index

    readonly property int totalItems: groupPosition.count

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1

    readonly property bool isPressed: headerMouseArea.pressed

    readonly property bool prevIsPressed: groupPosition.previousPressed

    readonly property bool nextIsPressed: groupPosition.nextPressed

    readonly property bool isHorizontalLayout: {
        var p = parent;
        if (!p) return false;
        var pStr = p.toString();
        return (pStr.indexOf("RowLayout") !== -1 || pStr.indexOf("Row") !== -1) && pStr.indexOf("Column") === -1;
    }

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on topRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    ColumnLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 8
        spacing: 8

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            spacing: 12

            Loader {
                active: root.icon && root.icon.length > 0
                visible: active
                Layout.alignment: Qt.AlignVCenter
                opacity: root.enabled ? 1 : 0.4

                sourceComponent: MaterialSymbol {
                    text: root.icon
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            ContentSubsectionLabel {
                opacity: 1 - highlightOverlay.opacity
                visible: root.title && root.title.length > 0
                text: root.title
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnLayer2
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.headerExtra !== null
                visible: active
                sourceComponent: root.headerExtra
            }

            // Accordion chevron: fixed at right edge, visible when collapsible
            // Points down when expanded (default), rotates to right when collapsed
            MaterialSymbol {
                visible: root.collapsible
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer2
                opacity: headerMouseArea.containsMouse ? 1.0 : 0.6
                Layout.alignment: Qt.AlignVCenter

                Behavior on opacity {
                    NumberAnimation { duration: 100 }
                }

                // Down (0°) when expanded → right (90°) when collapsed
                rotation: root.expanded ? 0 : -90
                Behavior on rotation {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }

            MaterialSymbol {
                opacity: 1 - highlightOverlay.opacity
                visible: root.tooltip && root.tooltip.length > 0
                text: "info"
                iconSize: Appearance.font.pixelSize.large
                Layout.alignment: Qt.AlignVCenter

                color: Appearance.colors.colSubtext
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

        // Content area: animated expand/collapse with clip and height transition
        Item {
            id: subSectionContentContainer
            Layout.fillWidth: true
            implicitHeight: root.expanded ? sectionContent.implicitHeight : 0
            clip: subSectionAnim.running || subSectionContentContainer.implicitHeight < sectionContent.implicitHeight

            Behavior on implicitHeight {
                id: subSectionAnim
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: sectionContent
                anchors.left: parent.left
                anchors.right: parent.right
                opacity: root.expanded ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: root.expanded ? 200 : 100 }
                }
            }
        }
    }

    // Clickable overlay for the entire header area (when collapsible)
    MouseArea {
        id: headerMouseArea
        anchors.left: root.left
        anchors.right: root.right
        anchors.top: root.top
        height: mainLayout.anchors.topMargin + headerRow.implicitHeight + 8
        hoverEnabled: root.collapsible
        cursorShape: root.collapsible ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.collapsible
        onClicked: root.expanded = !root.expanded
    }

    HighlightOverlay {
        id: highlightOverlay
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        visible: opacity > 0
    }
}
