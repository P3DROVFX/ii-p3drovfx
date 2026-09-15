pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Hyprland
import Quickshell.Wayland

Item {
    id: card
    property var entry: null
    property int previewIndex: 0
    property real uiScale: 1
    readonly property real cornerRadius: 12 * uiScale
    signal dismissRequested()

    readonly property int windowCount: entry?.toplevels.length ?? 0
    readonly property int idx: Math.max(0, Math.min(previewIndex, windowCount - 1))
    readonly property var toplevel: windowCount > 0 ? entry.toplevels[idx] : null
    readonly property bool currentMinimized: {
        const c = HyprlandData.clientForToplevel(card.toplevel);
        return c ? AkebonoStash.isStashed(c) : false;
    }

    function cycle(d) {
        if (card.windowCount <= 1)
            return;
        card.previewIndex = (card.idx + d + card.windowCount) % card.windowCount;
    }
    function toggleMin() {
        const c = HyprlandData.clientForToplevel(card.toplevel);
        if (!c)
            return;
        if (card.currentMinimized) {
            AkebonoStash.restore(c.address);
            Hyprland.dispatch(`hl.dsp.focus({window = "address:${c.address}"})`);
        } else {
            AkebonoStash.minimize(c.address);
        }
        card.dismissRequested();
    }
    function closeCurrent() {
        if (card.windowCount <= 1)
            card.dismissRequested();
        card.toplevel?.close();
    }

    component PreviewBtn: Item {
        id: pbtn
        property string icon: ""
        property bool danger: false
        signal trigger()
        implicitWidth: 22 * card.uiScale
        implicitHeight: 22 * card.uiScale
        MaterialSymbol {
            anchors.centerIn: parent
            text: pbtn.icon
            iconSize: Math.round(16 * card.uiScale)
            color: pbtn.danger ? Appearance.colors.colError
                : (pbtnMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0)
        }
        MouseArea {
            id: pbtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pbtn.trigger()
        }
    }

    WheelHandler {
        onWheel: (event) => card.cycle(event.angleDelta.y < 0 ? 1 : -1)
    }

    Rectangle {
        anchors.fill: parent
        radius: card.cornerRadius
        color: Appearance.colors.colLayer0
        visible: card.toplevel !== null
    }

    Component {
        id: previewCaptureComp
        ScreencopyView {
            id: scv
            anchors.fill: parent
            captureSource: card.toplevel
            live: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: scv.width
                    height: scv.height
                    radius: card.cornerRadius
                }
            }
        }
    }

    Loader {
        id: previewLoader
        anchors.fill: parent
        active: card.toplevel !== null
        sourceComponent: previewCaptureComp

        Connections {
            target: card
            function onToplevelChanged() {
                if (previewLoader.active) {
                    previewLoader.sourceComponent = null;
                    previewLoader.sourceComponent = previewCaptureComp;
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: card.toplevel === null
        text: card.entry?.appId ?? ""
        color: Appearance.colors.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.normal
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            card.toplevel?.activate();
            card.dismissRequested();
        }
    }

    Rectangle {
        id: controlBar
        anchors.top: parent.top
        anchors.topMargin: 6 * card.uiScale
        anchors.horizontalCenter: parent.horizontalCenter
        width: ctrlRow.implicitWidth + 14 * card.uiScale
        height: 26 * card.uiScale
        radius: height / 2
        color: Appearance.colors.colLayer0

        RowLayout {
            id: ctrlRow
            anchors.centerIn: parent
            spacing: 3 * card.uiScale

            PreviewBtn {
                Layout.alignment: Qt.AlignVCenter
                visible: card.windowCount > 1
                icon: "chevron_left"
                onTrigger: card.cycle(-1)
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: card.windowCount > 1
                text: `${card.idx + 1}/${card.windowCount}`
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            PreviewBtn {
                Layout.alignment: Qt.AlignVCenter
                visible: card.windowCount > 1
                icon: "chevron_right"
                onTrigger: card.cycle(1)
            }
            PreviewBtn {
                Layout.alignment: Qt.AlignVCenter
                icon: card.currentMinimized ? "open_in_full" : "remove"
                onTrigger: card.toggleMin()
            }
            PreviewBtn {
                Layout.alignment: Qt.AlignVCenter
                icon: "close"
                danger: true
                onTrigger: card.closeCurrent()
            }
        }
    }
}
