import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A modal surface inside the app window: a bottom sheet on narrow windows, a centred
 * dialog on wide ones. Content goes in the default slot, buttons in `actions`.
 *
 * Callers keep it behind a Loader so its tree exists only while it is open.
 */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool opened: false
    property bool scrollable: true
    property real maxHeightRatio: 0.9
    property real preferredWidth: ClockStyle.sheetMaxWidth
    readonly property bool wide: root.width >= ClockStyle.compactMax
    readonly property real progress: sheetProgress.value
    default property alias content: body.data
    property alias actions: actionsRow.data

    signal dismissed()
    signal fullyClosed()

    function open(): void {
        root.opened = true;
        root.forceActiveFocus();
    }

    function close(): void {
        if (!root.opened)
            return;
        root.opened = false;
        root.dismissed();
    }

    anchors.fill: parent
    visible: sheetProgress.value > 0
    z: 100
    focus: root.opened

    Keys.onEscapePressed: event => {
        root.close();
        event.accepted = true;
    }

    QtObject {
        id: sheetProgress
        property real value: root.opened ? 1 : 0
        onValueChanged: if (value === 0 && !root.opened) root.fullyClosed()

        Behavior on value {
            NumberAnimation {
                duration: root.opened ? ClockStyle.motionEnter.duration : ClockStyle.motionExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.opened ? ClockStyle.motionEnter.bezierCurve : ClockStyle.motionExit.bezierCurve
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colScrim
        opacity: sheetProgress.value

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: surface

        readonly property real maxHeight: root.height * root.maxHeightRatio
        readonly property real chromeHeight: header.implicitHeight + actionsRow.implicitHeight
            + ClockStyle.gapHuge * 2 + ClockStyle.gapLarge * (actionsRow.children.length > 0 ? 2 : 1)

        width: root.wide ? Math.min(root.preferredWidth, root.width - ClockStyle.gapHuge * 2) : root.width
        height: Math.min(surface.maxHeight, surface.chromeHeight + body.implicitHeight)
        x: (root.width - width) / 2
        y: root.wide
            ? (root.height - height) / 2 + (1 - sheetProgress.value) * ClockStyle.enterOffset
            : root.height - height * sheetProgress.value
        opacity: root.wide ? sheetProgress.value : 1
        color: ClockStyle.colSurfaceHigh
        topLeftRadius: ClockStyle.radiusExtraLarge
        topRightRadius: ClockStyle.radiusExtraLarge
        bottomLeftRadius: root.wide ? ClockStyle.radiusExtraLarge : 0
        bottomRightRadius: root.wide ? ClockStyle.radiusExtraLarge : 0

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            anchors {
                fill: parent
                margins: ClockStyle.gapHuge
            }
            spacing: ClockStyle.gapLarge

            ColumnLayout {
                id: header
                Layout.fillWidth: true
                spacing: ClockStyle.gapTiny

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: ClockStyle.gapSmall
                    visible: !root.wide
                    implicitWidth: ClockStyle.sheetHandleWidth
                    implicitHeight: ClockStyle.sheetHandleHeight
                    radius: ClockStyle.sheetHandleHeight / 2
                    color: ClockStyle.colOutline
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.title.length > 0
                    text: root.title
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textTitle
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colSubtext
                    wrapMode: Text.WordWrap
                }
            }

            StyledFlickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                interactive: root.scrollable && contentHeight > height
                contentWidth: width
                contentHeight: body.implicitHeight

                ColumnLayout {
                    id: body
                    width: flick.width
                    spacing: ClockStyle.gap
                }
            }

            RowLayout {
                id: actionsRow
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: children.length > 0
                spacing: ClockStyle.gapSmall
            }
        }
    }
}
