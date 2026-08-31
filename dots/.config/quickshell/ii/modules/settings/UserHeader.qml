pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: userHeaderBtn
    implicitHeight: 56
    radius: Appearance.rounding.full
    signal clicked

    property bool isActive: false

    scale: userHeaderMouse.pressed ? 0.95 : (userHeaderMouse.containsMouse ? 1.03 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuad
        }
    }

    color: isActive ? (userHeaderMouse.pressed ? Appearance.colors.colPrimaryActive : userHeaderMouse.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary) : (userHeaderMouse.pressed ? Appearance.colors.colLayer2Active : userHeaderMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    readonly property string _imageStyle: Config.options.userProfile.imageStyle
    readonly property string _customName: Config.options.userProfile.customName
    readonly property string _customGreeting: Config.options.userProfile.customGreeting
    readonly property string _avatarPath: Config.options.userProfile.imagePath

    // Avatar
    Item {
        id: avatarContainer
        anchors {
            left: parent.left
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        width: userHeaderBtn.implicitHeight - 10
        height: userHeaderBtn.implicitHeight - 10

        UserProfileAvatar {
            anchors.fill: parent
            active: GlobalStates.settingsOpen
        }
    }

    // Greeting text
    ColumnLayout {
        id: greetingText
        anchors {
            left: avatarContainer.right
            leftMargin: 10
            right: parent.right
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        spacing: 0

        StyledText {
            text: userHeaderBtn._customGreeting !== "" ? userHeaderBtn._customGreeting : Translation.tr("Hello,")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: userHeaderBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            opacity: userHeaderBtn.isActive ? 0.8 : 0.65
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        StyledText {
            text: userHeaderBtn._customName !== "" ? userHeaderBtn._customName : SystemInfo.username.toUpperCase()
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: userHeaderBtn.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: userHeaderMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: userHeaderBtn.clicked()
    }
}
