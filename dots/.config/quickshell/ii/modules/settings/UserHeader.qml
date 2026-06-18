pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: userHeaderBtn
    implicitHeight: 56
    radius: Appearance.rounding.full
    signal clicked()

    property bool isActive: false

    scale: userHeaderMouse.pressed ? 0.95 : (userHeaderMouse.containsMouse ? 1.03 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuad
        }
    }

    color: isActive
        ? (userHeaderMouse.pressed
            ? Appearance.colors.colPrimaryActive
            : userHeaderMouse.containsMouse
                ? Appearance.colors.colPrimaryHover
                : Appearance.colors.colPrimary)
        : (userHeaderMouse.pressed
            ? Appearance.colors.colLayer2Active
            : userHeaderMouse.containsMouse
                ? Appearance.colors.colLayer2Hover
                : Appearance.colors.colLayer2)

    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    readonly property string _imageStyle: Config.options.userProfile.imageStyle
    readonly property string _customName: Config.options.userProfile.customName
    readonly property string _customGreeting: Config.options.userProfile.customGreeting
    readonly property string _avatarPath: Config.options.userProfile.imagePath

    // Avatar circle
    Item {
        id: avatarContainer
        anchors {
            left: parent.left
            leftMargin: 6
            verticalCenter: parent.verticalCenter
        }
        width:  userHeaderBtn.implicitHeight - 10
        height: userHeaderBtn.implicitHeight - 10

        // Custom Image
        Rectangle {
            id: avatarCircle
            anchors.fill: parent
            radius: width / 2
            visible: userHeaderBtn._imageStyle === "custom"

            // Fallback icon
            MaterialSymbol {
                anchors.centerIn: parent
                text: "person"
                iconSize: 22
                color: Appearance.colors.colOnPrimary
                visible: !avatarImage.visible
            }

            // Avatar image
            Image {
                id: avatarSource
                anchors.fill: parent
                source: userHeaderBtn._avatarPath !== "" ? userHeaderBtn._avatarPath : ""
                sourceSize.width:  parent.width
                sourceSize.height: parent.height
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                visible: false
            }
            OpacityMask {
                id: avatarImage
                anchors.fill: parent
                source: avatarSource
                maskSource: avatarMask
                visible: avatarSource.status === Image.Ready
            }
        }

        // Initial (Default)
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: userHeaderBtn._imageStyle === "initial" || userHeaderBtn._imageStyle === "default"

            Image {
                id: initialAvatarSource
                anchors.fill: parent
                source: parent.visible ? Directories.userAvatarPathAccountsService : ""
                sourceSize.width:  parent.width
                sourceSize.height: parent.height
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            Rectangle {
                id: initialAvatarMask
                anchors.fill: parent
                radius: width / 2
                visible: false
            }
            OpacityMask {
                id: initialAvatarImage
                anchors.fill: parent
                source: initialAvatarSource
                maskSource: initialAvatarMask
                visible: initialAvatarSource.status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Appearance.colors.colPrimary
                visible: initialAvatarSource.status !== Image.Ready

                StyledText {
                    anchors.centerIn: parent
                    text: SystemInfo.username.charAt(0).toUpperCase()
                    color: Appearance.colors.colOnPrimary
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                }
            }
        }

        // Expressive
        MaterialShape {
            anchors.fill: parent
            
            function resolveShapeInner(s) {
                switch(s) {
                    case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided;
                    case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided;
                    case "Squircle":      return MaterialShape.Shape.Squircle;
                    case "Circle":        return MaterialShape.Shape.Circle;
                    case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf;
                    case "Burst":         return MaterialShape.Shape.Burst;
                    case "Heart":         return MaterialShape.Shape.Heart;
                    case "Bun":           return MaterialShape.Shape.Bun;
                    default:              return MaterialShape.Shape.Cookie9Sided;
                }
            }
            shape: resolveShapeInner(Config.options.userProfile.avatarShape)
            
            property color resolvedColor: {
                switch(Config.options.userProfile.avatarColor) {
                    case "primary": return Appearance.colors.colPrimary;
                    case "secondary": return Appearance.colors.colSecondary;
                    case "tertiary": return Appearance.colors.colTertiary;
                    case "error": return Appearance.colors.colError;
                    default: return Appearance.colors.colPrimary;
                }
            }
            property color resolvedOnColor: {
                switch(Config.options.userProfile.avatarColor) {
                    case "primary": return Appearance.colors.colOnPrimary;
                    case "secondary": return Appearance.colors.colOnSecondary;
                    case "tertiary": return Appearance.colors.colOnTertiary;
                    case "error": return Appearance.colors.colOnError;
                    default: return Appearance.colors.colOnPrimary;
                }
            }
            
            color: resolvedColor
            visible: userHeaderBtn._imageStyle === "expressive"

            StyledText {
                anchors.centerIn: parent
                text: SystemInfo.username.charAt(0).toUpperCase()
                color: parent.resolvedOnColor
                font.pixelSize: Appearance.font.pixelSize.huge
                font.family: Appearance.font.family.expressive
                font.weight: Font.DemiBold
            }
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
