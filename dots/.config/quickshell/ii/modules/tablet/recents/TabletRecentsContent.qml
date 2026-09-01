pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The recents carousel: every open window as a card, scrubbed sideways.
 *
 * Deliberately not the ii overview. That is a grid of workspaces with their windows laid
 * out inside, which answers "where is everything"; this answers "what was I just doing",
 * which is a flat, most-recent-first list. Android keeps the two apart and so does this
 * family — the home screens are the workspaces, recents is this.
 */
Item {
    id: root

    property real revealProgress: 1

    signal dismissRequested
    /// Asks the host to close first and run this afterwards; see TabletRecentsWindow on why
    /// anything that changes focus cannot happen while this surface is still mapped.
    signal deferredRequested(var action)

    readonly property real cardWidth: Math.max(240, Math.min(460, Math.round(root.width * 0.26)))
    readonly property real cardHeight: Math.round(root.cardWidth * 0.68)
    readonly property real cardSpacing: Math.max(16, Math.round(root.cardWidth * 0.06))

    /// Most recently focused last in ToplevelManager's order, so reverse it: Android puts
    /// what you were just in nearest to hand.
    readonly property var windows: {
        const list = [];
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            if (toplevel)
                list.push(toplevel);
        }
        return list.reverse();
    }

    function activate(toplevel) {
        root.deferredRequested(() => toplevel?.activate());
    }

    function closeWindow(toplevel) {
        toplevel?.close();
    }

    function newWorkspace() {
        // The Lua dispatcher API, as everything else in the shell uses; the classic
        // "workspace empty" string is a Lua syntax error here rather than a no-op. The host
        // runs it after this surface has gone — see TabletRecentsWindow.pendingDispatch.
        root.deferredRequested(() => Hyprland.dispatch("hl.dsp.focus({ workspace = 'empty' })"));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.round(root.height * 0.06)
        spacing: 20

        opacity: root.revealProgress
        transform: Translate {
            y: (1 - root.revealProgress) * 40
        }

        // Takes the leftover height so the cards sit in the middle of the screen, with the
        // new-workspace pill pinned below them. The row itself stays card-height and is
        // centred inside, rather than stretching the cards to fill.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: carousel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.min(parent.height, root.cardHeight + 48)

                contentWidth: cardRow.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.DragOverBounds
                clip: true

                RowLayout {
                    id: cardRow
                    height: carousel.height
                    spacing: root.cardSpacing

                    Repeater {
                        model: root.windows

                        delegate: TabletRecentCard {
                            required property var modelData
                            Layout.preferredWidth: root.cardWidth
                            Layout.preferredHeight: root.cardHeight
                            Layout.alignment: Qt.AlignVCenter
                            toplevel: modelData
                            onActivated: root.activate(modelData)
                            onClosed: root.closeWindow(modelData)
                        }
                    }
                }
            }

            PagePlaceholder {
                anchors.fill: parent
                shown: root.windows.length === 0
                icon: "layers_clear"
                title: Translation.tr("Nothing open")
                description: Translation.tr("Apps you open will show up here")
                sizeScale: 1.3
                descriptionHorizontalAlignment: Text.AlignHCenter
            }
        }

        // A workspace with nothing on it is Android's "new window" — the way out of recents
        // that is not going back to something you already had.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: newWorkspaceRow.implicitWidth + 44
            Layout.preferredHeight: Math.max(Appearance.sizes.minimumTouchTarget, 52)
            radius: height / 2
            color: newWorkspaceArea.pressed ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                id: newWorkspaceRow
                anchors.centerIn: parent
                spacing: 10

                MaterialSymbol {
                    text: "add"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    text: Translation.tr("New workspace")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
            }

            MouseArea {
                id: newWorkspaceArea
                anchors.fill: parent
                onClicked: root.newWorkspace()
            }
        }
    }

    Keys.onEscapePressed: root.dismissRequested()
}
