pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The way into Settings → ii tools, at the top of Devices & Phone.
 *
 * The ii tools page is not in the sidebar: it belongs to the phone, and the phone's
 * page is where people look for it. So the door is a banner there, loud enough to be
 * found — primary container, an expressive shape that changes on hover and a live
 * status — rather than one more row among the switches.
 */
RippleButton {
    id: root

    readonly property bool live: IiLinkService.phoneConnected
    readonly property bool paired: IiLinkService.hasPeers

    implicitHeight: content.implicitHeight + 36
    buttonRadius: Appearance.rounding.verylarge
    colBackground: root.live ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
    colBackgroundHover: root.live ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainerHover
    colRipple: root.live ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimaryContainerActive

    readonly property color fg: root.live ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer

    onClicked: {
        const win = root.QsWindow.window;
        if (!win || win.pageIndexById === undefined)
            return;
        const idx = win.pageIndexById("iiTools");
        if (idx >= 0)
            win.currentPage = idx;
    }

    contentItem: RowLayout {
        id: content
        spacing: 18

        Item { implicitWidth: 4 }

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.live ? "phonelink" : "install_mobile"
            iconSize: 32
            padding: 16
            shape: root.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
            color: root.live ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
            colSymbol: root.live ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary
            rotation: root.hovered ? 30 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            StyledText {
                text: Translation.tr("ii tools")
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.huge
                color: root.fg
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.fg
                opacity: 0.85
                text: {
                    if (root.live)
                        return Translation.tr("Connected to %1 · remote control, live updates and more").arg(IiLinkService.connectedList.map(c => c.name || c.model).join(", "));
                    if (root.paired)
                        return Translation.tr("Your phone is paired · open the app to connect");
                    return Translation.tr("The shell's Android companion: pair your phone for remote control, live updates and more");
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: root.paired
            implicitWidth: pillText.implicitWidth + 20
            implicitHeight: pillText.implicitHeight + 8
            radius: height / 2
            color: root.live ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
            StyledText {
                id: pillText
                anchors.centerIn: parent
                text: root.live ? Translation.tr("Connected") : Translation.tr("Paired")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.live ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 8
            text: "chevron_right"
            iconSize: Appearance.font.pixelSize.hugeass
            color: root.fg
        }
    }
}
