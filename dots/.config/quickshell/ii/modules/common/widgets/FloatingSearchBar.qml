pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Floating search pill with an optional leading action and local backdrop blur.
 *
 * Layout: [FAB slot] [blurred pill: icon + input + arrow] [clear FAB slot]
 *
 * - The pill floats above the page content (z-ordering is the caller's job)
 *   and blurs what is behind it through an invisible ShaderEffectSource
 *   sampling `blurSourceItem` at the pill's exact rectangle (BarGradientOverlay
 *   pattern), over an opaque base — card gaps capture as alpha 0 and would
 *   otherwise stay see-through — plus a 1% fill on top.
 * - The arrow action only appears once the user types (scale entrance).
 * - Outer control slots are always reserved so typing never shifts the pill.
 * - Live blur updates run only while `tabActive` is true.
 */
Item {
    id: root

    signal accepted()
    signal fabClicked()

    property alias placeholderText: filterField.placeholderText
    property alias text: filterField.text
    property string fabIcon: "edit"
    property bool fabVisible: true
    property string fabTooltip: ""
    property string fabText: ""
    property string placeholderTooltip: ""
    property real barHeight: 56
    property bool tabActive: true
    // Item whose rendered content sits behind the pill (usually the page's
    // Flickable). Null falls back to a solid pill without blur sampling.
    property Item blurSourceItem: null
    property Item keyNavTarget: null

    readonly property bool hasText: filterField.text.length > 0

    function forceActiveFocus(): void {
        filterField.forceActiveFocus();
    }

    function clear(): void {
        filterField.clear();
        filterField.forceActiveFocus();
    }

    width: Math.min(parent?.width ?? 560, 560)
    height: barHeight
    readonly property real controlGap: 12
    readonly property real inset: 8
    readonly property real innerSize: barHeight - inset * 2

    anchors {
        bottom: parent?.bottom
        horizontalCenter: parent?.horizontalCenter
        bottomMargin: inset
    }

    transform: Translate {
        y: root.tabActive ? 0 : root.height / 2
        Behavior on y {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }
    opacity: root.tabActive ? 1 : 0
    enabled: root.tabActive
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Blurred backdrop for the search pill: dialog-blur pattern (MultiEffect,
    // blurMax 64) sampling the page behind the bar, plus a 1% fill on top.
    Item {
        id: searchBackdrop
        anchors {
            left: fabSlot.right
            right: clearSlot.left
            leftMargin: root.controlGap
            rightMargin: root.controlGap
            top: parent.top
            bottom: parent.bottom
        }
        visible: root.tabActive
        layer.enabled: visible
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: searchBackdrop.width
                height: searchBackdrop.height
                radius: Appearance.rounding.full
            }
        }

        // The backing must stay opaque: the blur texture can contain alpha,
        // which would otherwise reveal the original, sharp content beneath it.
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer0Base
        }

        MultiEffect {
            anchors.fill: parent
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            source: searchBlurSource
        }

        ShaderEffectSource {
            id: searchBlurSource
            anchors.fill: parent
            visible: false
            live: searchBackdrop.visible && root.blurSourceItem !== null
            smooth: true
            sourceItem: root.blurSourceItem
            // Map the pill's offset, not the whole control's origin: the
            // leading FAB and gap are outside the sampled rectangle.
            readonly property point backdropPos: {
                const _rev = root.geometryRevision;
                if (!root.blurSourceItem)
                    return Qt.point(0, 0);
                return root.blurSourceItem.mapFromItem(root, searchBackdrop.x, searchBackdrop.y);
            }
            sourceRect: Qt.rect(
                backdropPos.x, backdropPos.y,
                searchBackdrop.width, searchBackdrop.height)
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.99)
        }
    }

    // Track source geometry, including contentItem.y during scrolling.
    // Flickable viewport coordinates stay fixed; live sampling updates its pixels.
    property int geometryRevision: 0
    onXChanged: geometryRevision++
    onYChanged: geometryRevision++
    onWidthChanged: geometryRevision++
    onHeightChanged: geometryRevision++
    Connections {
        target: root.blurSourceItem
        function onXChanged() { root.geometryRevision++ }
        function onYChanged() { root.geometryRevision++ }
        function onWidthChanged() { root.geometryRevision++ }
        function onHeightChanged() { root.geometryRevision++ }
    }

    Item {
        id: fabSlot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.barHeight
        height: root.barHeight
        visible: root.fabVisible

        FloatingActionButton {
            id: fabButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            baseSize: root.barHeight
            buttonRadius: Appearance.rounding.normal
            buttonRadiusPressed: Appearance.rounding.normal
            iconText: root.fabIcon
            buttonText: root.fabText
            expanded: hovered
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colBackgroundActive: Appearance.colors.colPrimaryContainerActive
            colRipple: Appearance.colors.colPrimaryContainerActive
            colOnBackground: Appearance.colors.colOnPrimaryContainer
            onClicked: root.fabClicked()
            StyledToolTip {
                text: root.fabTooltip
            }
        }
    }

    ToolbarTextField {
        id: filterField
        anchors {
            left: fabSlot.right
            right: clearSlot.left
            leftMargin: root.controlGap
            rightMargin: root.controlGap
            top: parent.top
            bottom: parent.bottom
        }
        visible: searchBackdrop.visible
        leftPadding: searchIcon.width + root.inset * 2 + root.controlGap
        rightPadding: root.inset * 2 + searchAction.width
        horizontalAlignment: TextInput.AlignLeft
        verticalAlignment: TextInput.AlignVCenter
        Accessible.name: placeholderText
        font.pixelSize: Appearance.font.pixelSize.normal
        hoverEnabled: true
        color: Appearance.colors.colOnSurface
        placeholderTextColor: Appearance.colors.colOnSurfaceVariant
        selectionColor: Appearance.colors.colPrimaryContainer
        selectedTextColor: Appearance.colors.colOnPrimaryContainer
        keyNavTarget: root.keyNavTarget

        Behavior on rightPadding {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        background: Rectangle {
            radius: Appearance.rounding.full
            color: "transparent"
            border.width: 1
            border.color: filterField.hovered || filterField.activeFocus
                ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Appearance.colors.colOnSurface
                opacity: filterField.hovered ? 0.05 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        MaterialSymbol {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: root.inset * 2
            anchors.verticalCenter: parent.verticalCenter
            text: "search"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }

        FloatingActionButton {
            id: searchAction
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            anchors.verticalCenter: parent.verticalCenter
            baseSize: root.innerSize
            enabled: root.hasText
            visible: root.hasText || visualScale > 0
            opacity: 1
            opacityBehaviorEnabled: false
            visualScale: root.hasText ? 1 : 0
            transformOrigin: Item.Center
            Behavior on visualScale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            buttonRadius: Appearance.rounding.full
            iconText: "arrow_forward"
            iconSize: Appearance.font.pixelSize.large
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colBackgroundActive: Appearance.colors.colPrimaryActive
            colRipple: colBackgroundActive
            colOnBackground: Appearance.colors.colOnPrimary
            Accessible.name: filterField.placeholderText
            onClicked: root.accepted()
            StyledToolTip {
                text: root.placeholderTooltip
            }
        }
    }

    Item {
        id: clearSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.barHeight
        height: width

        FloatingActionButton {
            anchors.centerIn: parent
            baseSize: root.barHeight
            buttonRadius: Appearance.rounding.full
            iconText: "close"
            iconSize: Appearance.font.pixelSize.large
            enabled: root.hasText
            visible: root.hasText || visualScale > 0
            opacity: 1
            opacityBehaviorEnabled: false
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colBackgroundActive: Appearance.colors.colLayer2Active
            colRipple: Appearance.colors.colLayer2Active
            colOnBackground: Appearance.colors.colOnLayer2
            Accessible.name: Translation.tr("Clear filter")
            visualScale: root.hasText ? 1 : 0
            transformOrigin: Item.Center
            Behavior on visualScale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            onClicked: root.clear()
            StyledToolTip {
                text: Translation.tr("Clear filter")
            }
        }
    }
}
