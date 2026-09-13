pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import "../../shared/cards"
import qs.services

/**
 * Port Watcher popup.
 *
 * Three beats, in the order a person asks the questions: how many ports am I
 * serving and is any of them open to the network, which ones, and what can I
 * do about one. Filters, ranges and watch lists are settings, not popup
 * furniture — they live in the widget's settings page.
 */
StyledPopup {
    id: root

    stickyHover: true
    popupRadius: Appearance.rounding.large

    readonly property int cardWidth: 384

    // Only one row shows its actions at a time. Keyed by id rather than index
    // so a refresh that reorders the list cannot open the wrong row.
    property string expandedId: ""
    readonly property int expandedIndex: {
        if (root.expandedId.length === 0)
            return -1;
        const ports = PortWatcher.visiblePorts;
        for (let i = 0; i < ports.length; i++) {
            if (String(ports[i].id) === root.expandedId)
                return i;
        }
        return -1;
    }

    onOpenedChanged: {
        if (root.opened) {
            root.expandedId = "";
            PortWatcher.refresh();
        }
    }

    readonly property bool statusIsError: PortWatcher.actionMessage.length > 0 && !PortWatcher.actionSuccess

    function statusText(): string {
        if (PortWatcher.actionMessage.length > 0)
            return PortWatcher.actionMessage;
        if (!PortWatcher.available)
            return PortWatcher.errorMessage.length > 0
                ? PortWatcher.errorMessage
                : Translation.tr("Port scan unavailable");
        if (PortWatcher.lastUpdated === 0)
            return PortWatcher.refreshing
                ? Translation.tr("Scanning…")
                : Translation.tr("Waiting for the first scan");
        return Translation.tr("Updated %1").arg(
            new Date(PortWatcher.lastUpdated).toLocaleTimeString(Qt.locale(), "HH:mm:ss"));
    }

    contentItem: ColumnLayout {
        id: contentLayout

        spacing: 10
        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        onStartAnimChanged: {
            if (!contentLayout.startAnim)
                return;
            hero.opacity = 0.0;
            hero.scale = 0.9;
            heroTranslate.y = 20;
            portsCard.opacity = 0.0;
            portsCard.scale = 0.94;
            portsCardTranslate.y = 22;
            Qt.callLater(function () {
                heroAnim.start();
                portsCardAnim.start();
            });
        }

        Connections {
            target: root
            function onPopupOpenProgressChanged() {
                if (root.popupOpenProgress !== 0.0)
                    return;
                heroAnim.stop();
                portsCardAnim.stop();
                hero.opacity = 0.0;
                hero.scale = 0.9;
                heroTranslate.y = 20;
                portsCard.opacity = 0.0;
                portsCard.scale = 0.94;
                portsCardTranslate.y = 22;
            }
        }

        // ── Hero: the headline number ────────────────────────────────────────
        HeroCard {
            id: hero

            Layout.minimumWidth: root.cardWidth
            compactMode: true
            implicitHeight: 156
            margins: 16
            iconSize: 96
            iconFontSize: 44
            titleSize: Math.round(Appearance.font.pixelSize.hugeass * 1.8)
            subtitleSize: Appearance.font.pixelSize.normal

            shapeString: PortWatcher.exposedCount > 0 ? "Cookie7Sided" : "Cookie9Sided"
            icon: "lan"
            title: String(PortWatcher.count)
            subtitle: PortWatcher.count === 1
                ? Translation.tr("port served")
                : Translation.tr("ports served")

            // Every colour here is one half of a Material on/container pair,
            // and never crossed with the other half of a different pair. The
            // earlier version painted onPrimaryContainer text — pure black in
            // this theme — over an onPrimary surface, which is how you get
            // black on dark brown.
            color: Appearance.colors.colSecondaryContainer
            textColor: Appearance.colors.colOnSecondaryContainer
            shapeColor: Appearance.colors.colPrimary
            symbolColor: Appearance.colors.colOnPrimary

            pillIcon: PortWatcher.exposedCount > 0 ? "public" : "lock"
            pillText: PortWatcher.exposedCount > 0
                ? Translation.tr("%1 exposed").arg(PortWatcher.exposedCount)
                : Translation.tr("Local only")
            pillColor: Appearance.colors.colSurfaceContainerHighest
            pillTextColor: Appearance.colors.colOnSurface
            pillIconColor: Appearance.colors.colOnSurface

            startAnim: contentLayout.startAnim

            opacity: 0.0
            scale: 0.9
            transform: Translate {
                id: heroTranslate
                y: 20
            }

            SequentialAnimation {
                id: heroAnim
                PauseAnimation {
                    duration: 40
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: hero
                        property: "opacity"
                        to: 1.0
                        duration: 280
                    }
                    NumberAnimation {
                        target: hero
                        property: "scale"
                        to: 1.0
                        duration: 380
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: heroTranslate
                        property: "y"
                        to: 0
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // ── The list ─────────────────────────────────────────────────────────
        Rectangle {
            id: portsCard

            Layout.fillWidth: true
            Layout.minimumWidth: root.cardWidth
            implicitWidth: root.cardWidth
            implicitHeight: cardColumn.implicitHeight + 28
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHigh

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 280
                    easing.type: Easing.OutQuint
                }
            }

            opacity: 0.0
            scale: 0.94
            transform: Translate {
                id: portsCardTranslate
                y: 22
            }

            SequentialAnimation {
                id: portsCardAnim
                PauseAnimation {
                    duration: 110
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: portsCard
                        property: "opacity"
                        to: 1.0
                        duration: 300
                    }
                    NumberAnimation {
                        target: portsCard
                        property: "scale"
                        to: 1.0
                        duration: 380
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: portsCardTranslate
                        property: "y"
                        to: 0
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }
            }

            ColumnLayout {
                id: cardColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialShape {
                        shapeString: "Clover4Leaf"
                        implicitSize: 34
                        color: Appearance.colors.colSecondaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "hub"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Served ports")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    // Live connections across every listed port. Hidden when
                    // quiet — an always-present zero is just noise.
                    Rectangle {
                        visible: PortWatcher.connectionCount > 0
                        implicitWidth: liveRow.implicitWidth + 18
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer

                        RowLayout {
                            id: liveRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                text: "swap_vert"
                                iconSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimaryContainer
                            }

                            StyledText {
                                text: String(PortWatcher.connectionCount)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    RippleButton {
                        id: refreshButton

                        implicitWidth: 34
                        implicitHeight: 34
                        padding: 0
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: PortWatcher.refresh()

                        StyledToolTip {
                            text: PortWatcher.refreshing
                                ? Translation.tr("Scanning…")
                                : Translation.tr("Rescan ports")
                            alternativeVisibleCondition: refreshButton.hovered
                            extraVisibleCondition: false
                            requireOverlay: false
                        }

                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "refresh"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface

                            NumberAnimation on rotation {
                                running: PortWatcher.refreshing
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 2
                    radius: 1
                    color: Appearance.colors.colSurfaceContainerHighest
                }

                // Empty state
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 12
                    visible: PortWatcher.count === 0
                    spacing: 10

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        shapeString: "Cookie6Sided"
                        implicitSize: 52
                        color: Appearance.colors.colSurfaceContainerHighest

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: PortWatcher.available ? "wifi_tethering_off" : "error"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: PortWatcher.available
                            ? Translation.tr("No app is serving a port")
                            : Translation.tr("Cannot read sockets")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: PortWatcher.available
                            ? Translation.tr("Start a server, or widen the filters in settings")
                            : (PortWatcher.errorMessage.length > 0
                                ? PortWatcher.errorMessage
                                : Translation.tr("The ss utility from iproute2 is required"))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOutline
                    }
                }

                // Port rows
                Item {
                    id: listHost

                    Layout.fillWidth: true
                    Layout.bottomMargin: 2
                    visible: PortWatcher.count > 0
                    readonly property real maxHeight: 296
                    implicitHeight: Math.min(listColumn.implicitHeight, listHost.maxHeight)

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 280
                            easing.type: Easing.OutQuint
                        }
                    }

                    StyledFlickable {
                        id: listFlick

                        anchors.fill: parent
                        contentHeight: listColumn.implicitHeight
                        clip: true
                        interactive: listColumn.implicitHeight > listHost.height

                        ColumnLayout {
                            id: listColumn

                            width: listFlick.width
                            spacing: 4

                            Repeater {
                                id: portsRepeater
                                model: PortWatcher.visiblePorts

                                delegate: PortRow {
                                    id: portRow

                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    entry: portRow.modelData
                                    isFirst: portRow.index === 0
                                    isLast: portRow.index === portsRepeater.count - 1
                                    showActions: root.expandedIndex === portRow.index
                                    aboveOpen: root.expandedIndex === portRow.index - 1
                                    belowOpen: root.expandedIndex === portRow.index + 1
                                    animDelay: 150 + Math.min(portRow.index, 7) * 55
                                    startAnim: contentLayout.startAnim
                                    onOpenRequested: root.expandedId = String(portRow.modelData.id)
                                    onCloseRequested: root.expandedId = ""
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Footer status line ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Layout.topMargin: -2
            spacing: 6

            MaterialSymbol {
                text: {
                    if (PortWatcher.actionMessage.length > 0)
                        return PortWatcher.actionSuccess ? "check_circle" : "error";
                    return PortWatcher.refreshing ? "sync" : "schedule";
                }
                iconSize: Appearance.font.pixelSize.small
                color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colOutline
            }

            StyledText {
                Layout.fillWidth: true
                text: root.statusText()
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colOutline
                elide: Text.ElideRight
            }

            StyledText {
                text: Config.options.bar.portWatcher.showSystem
                    ? Translation.tr("All processes")
                    : Translation.tr("Your apps")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOutline
            }
        }
    }
}
