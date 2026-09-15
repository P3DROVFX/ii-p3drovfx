pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    required property var appEntry
    property bool highlighted: false
    property int iconSize: 40
    property int inset: 6

    signal activated()
    signal rightClicked(entry: var, sceneX: real, sceneY: real)

    RippleButton {
        id: tile
        anchors.centerIn: parent
        implicitWidth: root.width - root.inset
        implicitHeight: root.height - root.inset
        buttonRadius: Appearance.rounding.small
        colBackground: root.highlighted ? Appearance.colors.colLayer2Hover : "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover

        onClicked: root.activated()
        altAction: event => {
            const scene = tile.mapToItem(null, event.x, event.y);
            root.rightClicked(resultComp.createObject(null, {
                type: Translation.tr("App"),
                id: root.appEntry.id ?? "",
                name: root.appEntry.name,
                iconName: root.appEntry.icon,
                iconType: LauncherSearchResult.IconType.System
            }), scene.x, scene.y);
        }

        contentItem: Item {
            Column {
                anchors.centerIn: parent
                spacing: 6

                IconImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: Quickshell.iconPath(root.appEntry.icon, "image-missing")
                    implicitSize: root.iconSize
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.width - 14
                    text: root.appEntry.name
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer0
                }
            }
        }
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
