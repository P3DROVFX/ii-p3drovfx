pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A shell surface presented as an app: title bar, back button, the content below.
 *
 * The desktop shell shows these things as overlays you dismiss — press Escape, click away,
 * hit the keybind again. None of that reads as an application on a tablet, and none of it
 * is reachable without a keyboard. So the content is re-chromed here into something with a
 * visible way back, which is what a finger needs and what D6 asked for.
 *
 * The content Components come from the ii family, so they are injected by the composition
 * root; this window knows only their ids.
 */
PanelWindow {
    id: root

    readonly property string appId: GlobalStates.tabletAppId
    readonly property var app: root.appId.length > 0 ? TabletSystemApps.byId(root.appId) : null
    readonly property Component contentComponent: root.appId.length > 0
        ? (TabletSystemApps.hostedContent[root.appId] ?? null)
        : null

    readonly property bool wantOpen: root.contentComponent !== null
    property real openProgress: root.wantOpen ? 1 : 0

    /// Which edge the window comes in from. Most apps rise from the bottom, the way an
    /// Android app does when you tap its icon; a surface that lives on an edge of the
    /// screen — policies on the left — keeps coming from there, so opening it still reads
    /// as the same panel rather than as an unrelated app.
    readonly property string enterFrom: root.app?.enterFrom ?? "bottom"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:tabletAppWindow"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.openProgress > 0.99 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: (root.wantOpen || root.openProgress > 0.001) && !GlobalStates.screenLocked

    Behavior on openProgress {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    onWantOpenChanged: {
        if (root.wantOpen)
            GlobalFocusGrab.addDismissable(root);
        else
            GlobalFocusGrab.removeDismissable(root);
    }

    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    function dismiss() {
        GlobalStates.closeTabletApp();
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: root.openProgress
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        opacity: root.openProgress
        transform: Translate {
            x: root.enterFrom === "left" ? -(1 - root.openProgress) * 64 : 0
            y: root.enterFrom === "left" ? 0 : (1 - root.openProgress) * 48
        }

        // ── Title bar ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(Appearance.sizes.minimumTouchTarget + 12, 64)
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 20
                spacing: 14

                // The only way out that does not need a keyboard.
                Rectangle {
                    Layout.preferredWidth: Appearance.sizes.minimumTouchTarget
                    Layout.preferredHeight: Appearance.sizes.minimumTouchTarget
                    radius: width / 2
                    color: backArea.pressed ? Appearance.colors.colLayer2 : "transparent"

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        iconSize: 24
                        color: Appearance.colors.colOnLayer1
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        onClicked: root.dismiss()
                    }
                }

                MaterialSymbol {
                    text: root.app?.icon ?? "widgets"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.app ? Translation.tr(root.app.name) : ""
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }
        }

        // ── The app itself ──────────────────────────────────────────────────
        Loader {
            id: contentLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Only while mapped: these are heavy trees, and keeping the last opened app
            // built after it closes is what makes a shell slow to start.
            active: root.visible && root.contentComponent !== null
            sourceComponent: root.contentComponent
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.wantOpen
        onActivated: root.dismiss()
    }
}
