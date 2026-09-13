pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import qs.services

/**
 * What is using your sensors, and who is using it.
 *
 * Reporting only — the Android sheet this follows offers no controls either,
 * because nothing here can be revoked from a status bar without lying about
 * what the revoke did.
 */
StyledPopup {
    id: root

    stickyHover: true
    popupRadius: Appearance.rounding.large

    readonly property int cardWidth: 324

    // One row per sensor, carrying every app that reached for it.
    readonly property var groups: {
        const byKind = {};
        for (const item of Privacy.activeItems) {
            const kind = String(item.kind);
            if (byKind[kind] === undefined)
                byKind[kind] = [];
            const app = String(item.app ?? "").trim();
            if (app.length > 0 && byKind[kind].indexOf(app) < 0)
                byKind[kind].push(app);
        }
        return Privacy.activeKinds.map(kind => ({
            kind: kind,
            apps: byKind[kind] ?? []
        }));
    }

    contentItem: ColumnLayout {
        id: contentLayout

        spacing: 10
        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        onStartAnimChanged: {
            if (!contentLayout.startAnim)
                return;
            card.opacity = 0.0;
            card.scale = 0.94;
            cardTranslate.y = 20;
            Qt.callLater(() => cardAnim.start());
        }

        Connections {
            target: root
            function onPopupOpenProgressChanged() {
                if (root.popupOpenProgress !== 0.0)
                    return;
                cardAnim.stop();
                card.opacity = 0.0;
                card.scale = 0.94;
                cardTranslate.y = 20;
            }
        }

        Rectangle {
            id: card

            Layout.fillWidth: true
            Layout.minimumWidth: root.cardWidth
            implicitWidth: root.cardWidth
            implicitHeight: cardColumn.implicitHeight + 32
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
                id: cardTranslate
                y: 20
            }

            SequentialAnimation {
                id: cardAnim
                PauseAnimation {
                    duration: 40
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: card
                        property: "opacity"
                        to: 1.0
                        duration: 280
                    }
                    NumberAnimation {
                        target: card
                        property: "scale"
                        to: 1.0
                        duration: 380
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: cardTranslate
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
                anchors.margins: 16
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Privacy.summaryTitle()
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: -8
                    horizontalAlignment: Text.AlignHCenter
                    text: Privacy.active
                        ? Translation.tr("In use now")
                        : Translation.tr("Nothing is being accessed")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: root.groups

                    delegate: Rectangle {
                        id: sensorRow

                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 60
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colSurfaceContainerHighest

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 16
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colTertiaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: Privacy.iconFor(String(sensorRow.modelData.kind))
                                    iconSize: 20
                                    fill: 1
                                    color: Appearance.colors.colOnTertiaryContainer
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Privacy.labelFor(String(sensorRow.modelData.kind))
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const apps = sensorRow.modelData.apps ?? [];
                                        if (apps.length === 0
                                                || !(Config.options.bar.privacyPill.showAppNames ?? true))
                                            return Translation.tr("In use");
                                        return Translation.tr("In use by %1").arg(apps.join(", "));
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // Empty state
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 6
                    visible: root.groups.length === 0
                    spacing: 10

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        shapeString: "Cookie6Sided"
                        implicitSize: 52
                        color: Appearance.colors.colSurfaceContainerHighest

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: Privacy.available ? "shield_lock" : "error"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: Privacy.available
                            ? Translation.tr("No app is using your camera, microphone or screen")
                            : (Privacy.errorMessage.length > 0
                                ? Privacy.errorMessage
                                : Translation.tr("The privacy probe is not running"))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOutline
                    }
                }
            }
        }
    }
}
