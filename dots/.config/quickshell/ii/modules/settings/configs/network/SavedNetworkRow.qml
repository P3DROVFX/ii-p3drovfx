import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One saved NetworkManager profile. The row carries the things that are worth
 * one click — connect, autoconnect, forget — and hands anything that needs a
 * form over to the editor sub-page.
 */
Rectangle {
    id: root

    required property var profile
    property bool isFirst: false
    property bool isLast: false
    property bool expanded: false
    // Sticky: the actions panel below is built once, on first expand.
    property bool wasExpanded: false
    onExpandedChanged: if (root.expanded) root.wasExpanded = true

    signal editRequested()
    signal toggleRequested()

    readonly property string uuid: root.profile?.uuid ?? ""
    readonly property string name: root.profile?.name ?? ""
    readonly property bool isActive: root.profile?.active ?? false
    readonly property bool autoconnect: root.profile?.autoconnect ?? false
    readonly property bool everUsed: (root.profile?.timestamp ?? 0) > 0
    readonly property bool wired: (root.profile?.type ?? "") === "802-3-ethernet"

    readonly property real outerRadius: Appearance.rounding.normal
    readonly property real innerRadius: Appearance.rounding.verysmall
    readonly property bool performanceMode: Config.options?.appearance?.settingsPerformanceMode ?? false

    Layout.fillWidth: true
    implicitHeight: rowContent.implicitHeight
    topLeftRadius: root.isFirst ? root.outerRadius : root.innerRadius
    topRightRadius: root.isFirst ? root.outerRadius : root.innerRadius
    bottomLeftRadius: root.isLast ? root.outerRadius : root.innerRadius
    bottomRightRadius: root.isLast ? root.outerRadius : root.innerRadius
    color: root.isActive ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    clip: true

    Behavior on color {
        // createObject runs once per row at construction regardless of
        // `enabled`, so performance mode skips it outright — with several
        // dozen saved profiles that's several dozen fewer objects built the
        // moment the list mounts.
        animation: root.performanceMode ? null
            : Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    ColumnLayout {
        id: rowContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Item {
            Layout.fillWidth: true
            implicitHeight: 54

            MouseArea {
                id: headerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleRequested()
            }

            Rectangle {
                anchors.fill: parent
                // A Rectangle clips its children to its bounding box, not to its
                // rounded shape, so a plain fill squares off the corners the row
                // just rounded. The highlight has to carry them itself.
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: root.expanded ? 0 : root.bottomLeftRadius
                bottomRightRadius: root.expanded ? 0 : root.bottomRightRadius
                color: headerArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                opacity: root.isActive ? 0.4 : 1
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                MaterialSymbol {
                    Layout.preferredWidth: 24
                    text: NetworkProfiles.typeIcon(root.profile?.type ?? "")
                    fill: root.isActive ? 1 : 0
                    iconSize: 24
                    color: root.isActive ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.isActive ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: {
                            const parts = [];
                            if (root.isActive)
                                parts.push(Translation.tr("In use"));
                            else if (!root.everUsed)
                                parts.push(Translation.tr("Never used"));
                            else if ((root.profile?.lastUsed ?? "").length > 0)
                                parts.push(Translation.tr("Last used %1").arg(root.profile.lastUsed));
                            if (!root.autoconnect)
                                parts.push(Translation.tr("Manual only"));
                            return parts.join("  •  ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    visible: (root.profile?.priority ?? 0) !== 0
                    text: "low_priority"
                    iconSize: Appearance.font.pixelSize.normal
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.35)
                }

                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    opacity: headerArea.containsMouse ? 1 : 0.6
                    rotation: root.expanded ? 0 : -90

                    Behavior on rotation {
                        enabled: !root.performanceMode
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: root.expanded && actionsLoader.item ? actionsLoader.item.implicitHeight + 16 : 0
            clip: true

            Behavior on implicitHeight {
                enabled: !root.performanceMode
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            // Deferred: most saved profiles are never opened, and this panel
            // builds several buttons and a switch — doing that eagerly for
            // every saved profile the moment the list mounts is what made
            // this section heavy to open with more than a few saved. Built
            // once on first expand (see wasExpanded).
            Loader {
                id: actionsLoader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                active: root.wasExpanded
                opacity: root.expanded ? 1 : 0

                Behavior on opacity {
                    enabled: !root.performanceMode
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                sourceComponent: ColumnLayout {
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButtonWithIcon {
                            materialIcon: root.isActive ? "link_off" : "link"
                            mainText: root.isActive ? Translation.tr("Disconnect") : Translation.tr("Connect")
                            colBackground: root.isActive ? Appearance.colors.colLayer2Hover
                                : Appearance.colors.colPrimary
                            colText: root.isActive ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colOnPrimary
                            onClicked: {
                                if (root.isActive)
                                    NetworkProfiles.deactivate(root.uuid);
                                else
                                    NetworkProfiles.activate(root.uuid);
                            }
                        }

                        RippleButtonWithIcon {
                            materialIcon: "tune"
                            mainText: Translation.tr("Edit")
                            onClicked: root.editRequested()
                        }

                        RippleButtonWithIcon {
                            materialIcon: "delete"
                            mainText: Translation.tr("Forget")
                            onClicked: NetworkProfiles.forget(root.uuid)
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: Translation.tr("Connect automatically")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: root.wired
                                    ? Translation.tr("Comes up on its own as soon as a cable is plugged in.")
                                    : Translation.tr("Joins this network on its own whenever it is in range.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        StyledSwitch {
                            checked: root.autoconnect
                            onToggled: {
                                NetworkProfiles.setAutoconnect(root.uuid, checked);
                                checked = Qt.binding(() => root.autoconnect);
                            }
                        }
                    }
                }
            }
        }
    }
}
