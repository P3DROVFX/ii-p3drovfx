import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_cookie"

    implicitWidth: 240
    implicitHeight: 240

    property bool wallpaperSafetyTriggered: false

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly" || (Config.options.lock.centerWidget === "clock_cookie")
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    needsColText: false

    Column {
        anchors.centerIn: parent
        spacing: 10

        CookieClock {}

        FadeLoader {
            anchors.horizontalCenter: parent.horizontalCenter
            shown: Config.options.background.widgets.clock_cookie.quoteEnable && Config.options.background.widgets.clock_cookie.quoteText !== ""
            sourceComponent: CookieQuote {}
        }

        // Status row
        Item {
            id: statusText
            implicitHeight: statusTextBg.implicitHeight
            implicitWidth: statusTextBg.implicitWidth
            anchors.horizontalCenter: parent.horizontalCenter
            StyledRectangularShadow {
                target: statusTextBg
                visible: statusTextBg.visible && (Config.options.background.widgets.enableShadows ?? true)
                opacity: statusTextBg.opacity
            }
            Rectangle {
                id: statusTextBg
                anchors.centerIn: parent
                clip: true
                opacity: (safetyStatusText.shown || lockStatusText.shown) ? 1 : 0
                visible: opacity > 0
                implicitHeight: statusTextRow.implicitHeight + 5 * 2
                implicitWidth: statusTextRow.implicitWidth + 5 * 2
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0)

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: statusTextRow
                    anchors.centerIn: parent
                    spacing: 14
                    ClockStatusText {
                        id: safetyStatusText
                        shown: root.wallpaperSafetyTriggered
                        statusIcon: "hide_image"
                        statusText: Translation.tr("Wallpaper safety enforced")
                    }
                    ClockStatusText {
                        id: lockStatusText
                        shown: GlobalStates.screenLocked && Config.options.lock.showLockedText
                        statusIcon: "lock"
                        statusText: Translation.tr("Locked")
                    }
                }
            }
        }
    }

    component ClockStatusText: Row {
        id: statusTextRow
        property alias statusIcon: statusIconWidget.text
        property alias statusText: statusTextWidget.text
        property bool shown: true
        property color textColor: Appearance.colors.colOnSecondaryContainer
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        spacing: 4
        MaterialSymbol {
            id: statusIconWidget
            anchors.verticalCenter: statusTextRow.verticalCenter
            iconSize: Appearance.font.pixelSize.huge
            color: statusTextRow.textColor
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
        ClockText {
            id: statusTextWidget
            color: statusTextRow.textColor
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: statusTextRow.verticalCenter
            font {
                pixelSize: Appearance.font.pixelSize.large
                weight: Font.Normal
            }
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
    }
}
