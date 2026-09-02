import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The bar widget's right-click menu in Edit Mode: its page in the catalogue,
 * the centre split (centre list only), and Remove.
 *
 * Drawn by the chrome surface - the bar's own window is too thin to hold a
 * card - and every layout write goes through the bar's controller. The rows
 * carry their own bodies, the same shape the widget menu and the catalogue
 * use.
 */
Rectangle {
    id: root

    property var controller: null
    property int bucket: -1
    property int index: -1
    property bool centered: false
    signal dismissRequested()

    readonly property real padding: 8
    readonly property string componentId: {
        if (!root.controller || root.bucket < 0 || root.index < 0)
            return "";
        const entry = root.controller.storedList(root.bucket)[root.index];
        return entry && entry.id ? entry.id : "";
    }
    readonly property var info: root.componentId === ""
        ? null : BarComponentRegistry.getComponent(root.componentId)

    implicitWidth: 244
    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.windowRounding
    color: Appearance.colors.colSurfaceContainer

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    StyledRectangularShadow {
        target: root
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: 4
            spacing: 8

            MaterialSymbol {
                text: root.info?.icon ?? "widgets"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: root.info?.title ?? Translation.tr("Widget")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        // The way to this widget's looks and its group, which is a page of the
        // catalogue rather than anything this card could hold.
        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            rowEnabled: root.componentId !== ""
            symbol: "palette"
            title: Translation.tr("Appearance & group")
            trailingKind: "chevron"
            onActivated: {
                const id = root.componentId;
                root.dismissRequested();
                GlobalStates.openEditCatalogue("bar", "", "component:" + id);
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            visible: root.bucket === 1 && !ShellModePolicy.barCenterActive
            first: false
            last: false
            symbol: "align_horizontal_center"
            title: Translation.tr("Centre this")
            trailingKind: "switch"
            switchChecked: root.centered
            onActivated: {
                root.dismissRequested();
                root.controller?.toggleCenter(root.bucket, root.index);
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            destructive: true
            symbol: "delete"
            title: Translation.tr("Remove from the bar")
            trailingKind: "none"
            onActivated: {
                root.dismissRequested();
                root.controller?.removeAt(root.bucket, root.index);
            }
        }
    }
}
