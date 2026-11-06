pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * One login in the Passwords popup — a row of the shell's grouped list.
 *
 * Same dynamic radius as the Settings rail (`SidebarNavButton`) and the
 * Clock rail: every row has its own surface, the group's outer corners are
 * large and the joins tiny; the selected row becomes a pill and the rows
 * facing it round their facing corners, so the selection presses a notch
 * into the group. Rows never change height — selecting one morphs corners,
 * colour and the avatar's shape, and slides the actions in from the right.
 */
Item {
    id: root

    required property var item
    property bool selected: false
    property bool suggested: false
    property bool canType: false

    // Position in the group, set by the list.
    property bool isFirst: false
    property bool isLast: false
    property bool prevSelected: false
    property bool nextSelected: false

    signal activated()
    signal hoveredRow()
    signal action(string kind)

    readonly property int rowHeight: 54
    readonly property string name: String(root.item?.name ?? "")
    readonly property string user: String(root.item?.user ?? "")
    readonly property string letter: root.name.length > 0 ? root.name.charAt(0).toUpperCase() : "?"

    // A stable shape per item, so a login is recognised by its silhouette.
    readonly property var shapes: ["Cookie7Sided", "Clover4Leaf", "Sunny", "Cookie9Sided", "SoftBurst", "Flower", "Cookie6Sided", "Puffy"]
    readonly property string itemShape: {
        let h = 0;
        const id = String(root.item?.id ?? root.name);
        for (let i = 0; i < id.length; i++)
            h = (h * 31 + id.charCodeAt(i)) | 0;
        return root.shapes[Math.abs(h) % root.shapes.length];
    }

    readonly property bool pressed: mouseArea.pressed
    readonly property color contentColor: root.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2

    // ── Dynamic radius (SidebarNavButton rules) ──────────────────────────────
    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(root.rowHeight / 2, Appearance.rounding.large)
    readonly property real rLarge: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.large
    readonly property real rSmall: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.verysmall
    readonly property bool topPill: root.selected || root.pressed || root.prevSelected
    readonly property bool bottomPill: root.selected || root.pressed || root.nextSelected
    readonly property real topRadius: root.topPill ? root.rFull : (root.isFirst ? root.rLarge : root.rSmall)
    readonly property real bottomRadius: root.bottomPill ? root.rFull : (root.isLast ? root.rLarge : root.rSmall)

    // One 0→1 value for everything the selection reveals.
    property real reveal: root.selected ? 1 : 0
    Behavior on reveal {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    implicitHeight: root.rowHeight

    HoverHandler {
        id: hover
        onHoveredChanged: if (hover.hovered) root.hoveredRow()
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        // Press feedback: the only sanctioned scale.
        scale: root.pressed ? 0.98 : 1
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
        color: root.selected
            ? (root.pressed ? Appearance.colors.colPrimaryActive : hover.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
            : (root.pressed ? Appearance.colors.colLayer2Active : hover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on topLeftRadius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on topRightRadius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on bottomLeftRadius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on bottomRightRadius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // Under the content, so the action buttons take their own presses.
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    // ── Avatar: circle at rest, the item's own shape when selected ───────────
    MaterialShape {
        id: avatar
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: 36
        shapeString: root.selected ? root.itemShape : "Circle"
        color: root.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondaryContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StyledText {
            anchors.centerIn: parent
            text: root.letter
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.normal
            color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    // ── Name, and the username sliding up under it when selected ─────────────
    Item {
        id: label
        anchors.left: avatar.right
        anchors.leftMargin: 12
        anchors.right: actionSlot.left
        anchors.rightMargin: 8
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        clip: true

        readonly property real subHeight: userText.implicitHeight

        StyledText {
            id: nameText
            width: parent.width
            // Centred at rest; nudged up by half the second line as it arrives.
            y: Math.round((label.height - nameText.implicitHeight) / 2 - label.subHeight / 2 * root.reveal)
            text: root.name
            elide: Text.ElideRight
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            color: root.contentColor

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            id: userText
            width: parent.width
            y: Math.round(nameText.y + nameText.implicitHeight + 6 * (1 - root.reveal))
            opacity: root.reveal
            visible: root.reveal > 0.01
            text: root.user.length > 0 ? root.user : String(root.item?.host ?? "")
            elide: Text.ElideMiddle
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.contentColor
        }
    }

    // A quiet mark on the row that matches the window behind the popup.
    MaterialSymbol {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        opacity: root.suggested ? 1 - root.reveal : 0
        visible: opacity > 0.01
        text: "web_asset"
        iconSize: Appearance.font.pixelSize.normal
        color: Appearance.colors.colOnSurfaceVariant
    }

    // ── Actions: a clipped slot that opens with `reveal` (ToDo hover-reveal) ─
    component RowAction: RippleButton {
        id: act
        required property string symbol
        required property string kind
        required property string hint
        property bool primary: false

        implicitWidth: act.primary ? 40 : 32
        implicitHeight: act.primary ? 40 : 32
        buttonRadius: act.primary ? Appearance.rounding.normal : Appearance.rounding.full
        colBackground: act.primary ? Appearance.colors.colOnPrimary : ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.10)
        colBackgroundHover: act.primary ? ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colPrimary, 0.88) : ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.18)
        colRipple: act.primary ? ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colPrimary, 0.76) : ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.26)
        onClicked: root.action(act.kind)

        MaterialSymbol {
            anchors.centerIn: parent
            text: act.symbol
            iconSize: act.primary ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.normal
            fill: act.primary ? 1 : 0
            color: act.primary ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary
        }

        StyledToolTip {
            text: act.hint
            requireOverlay: false
        }
    }

    Item {
        id: actionSlot
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.round(actions.implicitWidth * root.reveal)
        clip: true

        Row {
            id: actions
            // Anchored to the slot's left: the buttons slide in from the right.
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            opacity: root.reveal

            RowAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "person"
                kind: "username"
                hint: Translation.tr("Copy username")
                visible: root.user.length > 0
            }
            RowAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "pin"
                kind: "totp"
                hint: Translation.tr("Copy 2FA code")
                // rbw/pass cannot tell without decrypting: null means "maybe".
                visible: root.item?.totp !== false
            }
            RowAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "keyboard"
                kind: "type"
                hint: Translation.tr("Type into the window")
                visible: root.canType
            }
            RowAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "content_copy"
                kind: "password"
                hint: Translation.tr("Copy password")
                primary: true
            }
        }
    }
}
