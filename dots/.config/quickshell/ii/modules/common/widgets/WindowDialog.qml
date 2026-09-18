import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool show: false
    default property alias contentData: contentColumn.data
    readonly property real contentHeight: contentColumn.implicitHeight + dialogBackground.radius * 2
    property real backgroundHeight: contentHeight
    // An owner can opt into a wider dialog without changing existing
    // backgroundWidth overrides used by other hosts.
    property real preferredDialogWidth: 0
    property real backgroundWidth: 350
    property real backgroundAnimationMovementDistance: 60

    // ── Page presentation ──────────────────────────────────────────────────────
    /**
     * The same dialog, hosted as a page that replaces its host's content (the Dynamic
     * Island dashboard) instead of floating over it.
     *
     * Nothing about the dialog's own content changes: header, body and buttons are laid
     * out exactly as in a dialog. The frame changes - no scrim, no floating card, no
     * pop-in - and a back button joins the header. When the dialog's first row is its
     * header (title and switch), the back button sits at the start of that row;
     * a dialog without one gets a bar with the back button and `pageTitle`.
     */
    property bool pageMode: false
    property string pageTitle: ""
    /** The first content row, when it is a header row the back button can join. */
    readonly property Item pageHeaderRow: {
        if (!root.pageMode || contentColumn.children.length === 0)
            return null;
        const first = contentColumn.children[0];
        const type = String(first);
        // A header row (title and switch) or a bare dialog title.
        return (type.startsWith("QQuickRowLayout") || type.startsWith("WindowDialogTitle")) ? first : null;
    }
    /** The height this dialog wants as a page: its layout, its margins and its bar. */
    readonly property real pageContentHeight: Math.max(root.backgroundHeight, contentColumn.implicitHeight)
        + 24 + root.pageBarHeight
    readonly property real pageBackSize: 40
    readonly property real pageBarHeight: root.pageMode && !root.pageHeaderRow ? root.pageBackSize + 12 : 0
    onPageHeaderRowChanged: {
        if (root.pageHeaderRow)
            root.pageHeaderRow.Layout.leftMargin = root.pageBackSize + 12;
    }

    signal dismiss()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        }
    }

    color: root.pageMode ? "transparent"
        : (root.show ? Appearance.colors.colScrim : ColorUtils.transparentize(Appearance.colors.colScrim))
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    visible: dialogBackground.opacity > 0.01

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    MouseArea { // Clicking outside the dialog should dismiss
        anchors.fill: parent
        enabled: !root.pageMode
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.dismiss()
        onWheel: (wheel) => wheel.accepted = true
    }

    Rectangle {
        id: dialogBackground
        anchors.horizontalCenter: parent.horizontalCenter
        radius: root.pageMode ? 0 : Appearance.rounding.large
        color: root.pageMode ? "transparent" : Appearance.m3colors.m3surfaceContainerHigh // Use opaque version of layer3

        // A page is placed and animated by its host; it only fills it.
        property real targetY: root.pageMode ? 0 : root.height / 2 - root.backgroundHeight / 2
        y: root.pageMode ? 0 : (root.show ? targetY : (targetY + 40))
        scale: root.pageMode ? 1.0 : (root.show ? 1.0 : 0.88)
        opacity: root.show ? 1.0 : 0.0

        implicitWidth: root.pageMode ? root.width
            : (root.preferredDialogWidth > 0 ? root.preferredDialogWidth : root.backgroundWidth)
        implicitHeight: root.pageMode ? root.height : root.backgroundHeight

        Behavior on y {
            enabled: !root.pageMode
            NumberAnimation {
                duration: 350
                easing.type: root.show ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.2
            }
        }

        Behavior on scale {
            enabled: !root.pageMode
            NumberAnimation {
                duration: 350
                easing.type: root.show ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.2
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.show ? 280 : 200
                easing.type: Easing.OutCubic
            }
        }

        MouseArea { // So clicking inside the dialog won't dismiss
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onWheel: (wheel) => wheel.accepted = true
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: root.pageMode ? 12 : dialogBackground.radius
                topMargin: (root.pageMode ? 12 : dialogBackground.radius) + root.pageBarHeight
            }
            spacing: 16
            opacity: root.show ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

        }

        // The page's way back: joins the header row, or heads its own bar.
        RippleButton {
            id: pageBackButton
            visible: root.pageMode
            x: contentColumn.x
            y: root.pageHeaderRow
                ? contentColumn.y + root.pageHeaderRow.y + (root.pageHeaderRow.height - height) / 2
                : contentColumn.y - root.pageBarHeight + (root.pageBarHeight - height) / 2
            implicitWidth: root.pageBackSize
            implicitHeight: root.pageBackSize
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: root.dismiss()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }
        }

        StyledText {
            visible: root.pageMode && !root.pageHeaderRow && root.pageTitle !== ""
            anchors.left: pageBackButton.right
            anchors.leftMargin: 12
            anchors.verticalCenter: pageBackButton.verticalCenter
            text: root.pageTitle
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }
    }
}
