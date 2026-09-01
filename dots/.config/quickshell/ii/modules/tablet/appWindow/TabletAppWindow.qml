pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.tablet.navigation

/**
 * A shell tool presented as a normal application window.
 *
 * Unlike a layer-shell overlay this is an xdg toplevel: Hyprland places it on the workspace
 * selected by GlobalStates.openTabletApp and can focus it like any other program. A compact
 * app bar restores touch-reachable Back and Close controls without turning the window back
 * into a layer-shell overlay.
 *
 * The content Components come from the ii family, so they are injected by the composition
 * root; this window knows only their ids.
 */
FloatingWindow {
    id: root

    readonly property string appId: GlobalStates.tabletAppId
    readonly property var app: root.appId.length > 0 ? TabletSystemApps.byId(root.appId) : null
    readonly property Component contentComponent: root.appId.length > 0
        ? (TabletSystemApps.hostedContent[root.appId] ?? null)
        : null

    title: root.app ? "ii Tablet: " + Translation.tr(root.app.name) : "ii Tablet"
    implicitWidth: Math.round((root.screen?.width ?? 1280) * 0.86)
    implicitHeight: Math.round((root.screen?.height ?? 800) * 0.82)
    minimumSize: Qt.size(Appearance.sizes.minimumTouchTarget * 10,
                         Appearance.sizes.minimumTouchTarget * 8)
    color: Appearance.colors.colLayer0

    visible: root.contentComponent !== null && !GlobalStates.screenLocked

    // A compositor close must release the current app id; otherwise the next app request
    // would only change a hidden Loader instead of reopening a normal toplevel.
    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && root.appId.length > 0)
            GlobalStates.closeTabletApp();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Appearance.sizes.minimumTouchTarget
                + Appearance.sizes.elevationMargin * 2
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Appearance.sizes.elevationMargin
                anchors.rightMargin: Appearance.sizes.elevationMargin
                spacing: Appearance.sizes.elevationMargin

                RippleButton {
                    Layout.preferredWidth: Appearance.sizes.minimumTouchTarget
                    Layout.preferredHeight: Appearance.sizes.minimumTouchTarget
                    buttonRadius: Appearance.rounding.full
                    buttonRadiusPressed: Appearance.rounding.large
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colBackgroundActive: Appearance.colors.colLayer1Active
                    colRipple: Appearance.colors.colLayer1Active
                    releaseAction: () => TabletNavigation.back()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                }

                MaterialSymbol {
                    text: root.app?.icon ?? "widgets"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.app ? Translation.tr(root.app.name) : ""
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                RippleButton {
                    Layout.preferredWidth: Appearance.sizes.minimumTouchTarget
                    Layout.preferredHeight: Appearance.sizes.minimumTouchTarget
                    buttonRadius: Appearance.rounding.full
                    buttonRadiusPressed: Appearance.rounding.large
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colBackgroundActive: Appearance.colors.colLayer1Active
                    colRipple: Appearance.colors.colLayer1Active
                    releaseAction: () => GlobalStates.closeTabletApp()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        Loader {
            id: contentLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Only while mapped: these are heavy trees, and keeping the last opened app
            // built after it closes would make the shell slow to start.
            active: root.visible && root.contentComponent !== null
            sourceComponent: root.contentComponent
        }
    }
}
