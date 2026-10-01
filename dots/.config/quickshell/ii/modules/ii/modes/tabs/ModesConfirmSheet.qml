import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * "Are you sure?" as a side sheet: what is about to go, why it matters, and the one
 * button that does it. Used for deleting a mode or routine and for clearing the
 * activity log — the old in-place confirms, moved where every other decision opens.
 *
 * Enter confirms, Escape backs out (the sheet's own handling).
 */
ClockSheet {
    id: root

    property string message: ""
    property string symbol: "delete"
    property string confirmLabel: Translation.tr("Delete")
    property bool danger: true

    signal confirmed()

    function confirm(): void {
        root.confirmed();
        root.close();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.confirm();
            event.accepted = true;
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: shape.implicitHeight + ClockStyle.gapLarge * 2

        MaterialShapeWrappedMaterialSymbol {
            id: shape
            anchors.centerIn: parent
            text: root.symbol
            iconSize: 34
            padding: 22
            shape: MaterialShape.Shape.Cookie9Sided
            fill: 1
            color: root.danger ? ClockStyle.colErrorContainer : ClockStyle.colSecondaryContainer
            colSymbol: root.danger ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.message.length > 0
        text: root.message
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pixelSize: ClockStyle.textNormal
        color: ClockStyle.colOnSurfaceVariant
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Cancel")
            symbol: "close"
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            danger: root.danger
            symbol: root.symbol
            label: root.confirmLabel
            onClicked: root.confirm()
        }
    ]
}
