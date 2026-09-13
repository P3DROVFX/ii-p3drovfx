import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    required property ListView target

    anchors {
        bottom: parent.bottom
        horizontalCenter: parent.horizontalCenter
        bottomMargin: 10
    }

    /** Overridable: a list that scrolls itself knows better than `atYEnd` does. */
    property bool shown: !root.target.atYEnd
    /** A chat can say exactly how much arrived below the reader. */
    property int newItemCount: 0

    opacity: root.shown ? 1 : 0
    transform: Translate {
        id: scrollButtonTransform
        y: root.shown ? 0 : Appearance.rounding.small

        Behavior on y {
            enabled: !Config.options.sidebar.ai.reducedMotion
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
    }
    visible: opacity > 0
    Behavior on opacity {
        enabled: !Config.options.sidebar.ai.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    implicitWidth: contentItem.implicitWidth + 8 * 2
    implicitHeight: contentItem.implicitHeight + 4 * 2

    colBackground: Appearance.colors.colSecondary
    colBackgroundHover: Appearance.colors.colSecondaryHover
    colRipple: Appearance.colors.colSecondaryActive
    buttonRadius: Appearance.rounding.verysmall

    downAction: () => {
        target.positionViewAtEnd()
    }

    contentItem: Row {
        id: contentItem
        spacing: 4
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "arrow_downward"
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.newItemCount > 0
                ? Translation.tr("%1 new").arg(String(root.newItemCount))
                : Translation.tr("Scroll to Bottom")
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
    }
}
