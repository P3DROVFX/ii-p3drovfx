pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** "Phone mirroring failed" and why, for a few seconds. Clicking retries. */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.phoneMirrorError : null;
    }
    readonly property var event: root.source ? root.source.payload : null
    readonly property bool canRetry: !!root.event && root.event.sessionId === "mirror"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            shape: MaterialShape.Shape.Cookie9Sided
            text: "mobile_off"
            iconSize: 18
            padding: 7
            color: Appearance.colors.colErrorContainer
            colSymbol: Appearance.colors.colOnErrorContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.event ? root.event.title : ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: root.event ? root.event.reason : ""
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                maximumLineCount: 2
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        RippleButton {
            id: retryButton
            Layout.alignment: Qt.AlignVCenter
            visible: root.canRetry
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: {
                root.source?.dismiss();
                PhoneScrcpyService.openMirrorWindow();
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "refresh"
                iconSize: 18
                color: Appearance.colors.colOnLayer2
            }

            StyledToolTip {
                text: Translation.tr("Try again")
            }
        }
    }
}
