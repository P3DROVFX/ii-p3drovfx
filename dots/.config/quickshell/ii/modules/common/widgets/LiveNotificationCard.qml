pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A phone live update (an order on its way, a ride arriving) as its own card, so it
 * never reads as one more notification: primary container, the process status in large
 * type without expanding, the key value (an ETA) as a chip, and the progress as a wave.
 *
 * Drawn by NotificationGroup in place of its row when the group is live. `liveData`
 * comes from KdeConnectService._liveView; the close button is the only way to dismiss
 * it besides a swipe - "clear all" keeps it.
 */
ColumnLayout {
    id: root

    required property var notificationObject
    property real zoom: 1.0
    property bool popup: false
    signal dismissRequested

    readonly property var live: root.notificationObject?.liveData ?? null
    readonly property color colFg: Appearance.colors.colOnPrimaryContainer
    readonly property color colAccent: Appearance.colors.colPrimary
    readonly property color colOnAccent: Appearance.colors.colOnPrimary

    spacing: 10 * root.zoom

    // ── Header: app, the live badge, time, close ─────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10 * root.zoom

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 40 * root.zoom
            implicitHeight: 40 * root.zoom
            radius: 13 * root.zoom
            color: ColorUtils.transparentize(root.colFg, 0.88)
            clip: true

            Image {
                id: appIconImage
                anchors.fill: parent
                source: root.live?.iconPath ? "file://" + root.live.iconPath : ""
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: appIconImage.status !== Image.Ready
                text: "smartphone"
                iconSize: 22 * root.zoom
                color: root.colFg
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2 * root.zoom

            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * root.zoom

                StyledText {
                    Layout.fillWidth: false
                    Layout.maximumWidth: 180 * root.zoom
                    text: root.live?.appName ?? root.notificationObject?.appName ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small * root.zoom
                    font.weight: Font.DemiBold
                    color: root.colFg
                }

                // "Live" badge: a breathing dot, so the card says it is still going.
                Rectangle {
                    implicitHeight: liveBadgeRow.implicitHeight + 4 * root.zoom
                    implicitWidth: liveBadgeRow.implicitWidth + 12 * root.zoom
                    radius: height / 2
                    color: root.colAccent

                    Row {
                        id: liveBadgeRow
                        anchors.centerIn: parent
                        spacing: 4 * root.zoom

                        Rectangle {
                            id: liveDot
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6 * root.zoom
                            height: width
                            radius: width / 2
                            color: root.colOnAccent

                            SequentialAnimation on opacity {
                                running: root.popup && root.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Live")
                            font.pixelSize: Appearance.font.pixelSize.smallest * root.zoom
                            font.weight: Font.Bold
                            color: root.colOnAccent
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            StyledText {
                Layout.fillWidth: true
                text: NotificationUtils.getFriendlyNotifTimeString(root.notificationObject?.time)
                font.pixelSize: Appearance.font.pixelSize.smaller * root.zoom
                color: ColorUtils.transparentize(root.colFg, 0.3)
            }
        }

        RippleButton {
            id: closeButton
            Layout.alignment: Qt.AlignTop
            implicitWidth: 32 * root.zoom
            implicitHeight: 32 * root.zoom
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(root.colFg, 0.9)
            colBackgroundHover: ColorUtils.transparentize(root.colFg, 0.8)
            colRipple: ColorUtils.transparentize(root.colFg, 0.7)
            onClicked: root.dismissRequested()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 18 * root.zoom
                color: root.colFg
            }

            StyledToolTip {
                text: Translation.tr("Dismiss until it changes")
            }
        }
    }

    // ── What is happening, readable collapsed ────────────────────────────────
    StyledText {
        Layout.fillWidth: true
        text: root.live?.status ?? root.notificationObject?.summary ?? ""
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.huge * root.zoom
        font.weight: Font.Bold
        color: root.colFg
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6 * root.zoom
        visible: (root.live?.chipValue ?? "") !== "" || (root.live?.detail ?? "") !== ""

        // The key value - an ETA, a countdown - as a filled chip.
        Rectangle {
            visible: (root.live?.chipValue ?? "") !== ""
            implicitHeight: chipRow.implicitHeight + 10 * root.zoom
            implicitWidth: chipRow.implicitWidth + 20 * root.zoom
            radius: height / 2
            color: root.colAccent

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6 * root.zoom

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "schedule"
                    fill: 1
                    iconSize: 16 * root.zoom
                    color: root.colOnAccent
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: root.live?.chipLabel ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller * root.zoom
                    color: ColorUtils.transparentize(root.colOnAccent, 0.15)
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.live?.chipValue ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small * root.zoom
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                    color: root.colOnAccent
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.live?.detail ?? ""
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smallie * root.zoom
        color: ColorUtils.transparentize(root.colFg, 0.2)
    }

    StyledProgressBar {
        Layout.fillWidth: true
        Layout.topMargin: 2 * root.zoom
        visible: (root.live?.progress ?? -1) >= 0 && !(root.live?.indeterminate ?? false)
        valueBarHeight: 7 * root.zoom
        wavy: true
        // A moving wave only where it is seen: hidden items still render.
        animateWave: root.popup && root.visible
        highlightColor: root.colAccent
        trackColor: ColorUtils.transparentize(root.colFg, 0.82)
        value: Math.max(0, root.live?.progress ?? 0)
    }

    StyledIndeterminateProgressBar {
        Layout.fillWidth: true
        Layout.topMargin: 2 * root.zoom
        visible: (root.live?.indeterminate ?? false) && root.visible
    }

    RippleButton {
        Layout.alignment: Qt.AlignRight
        implicitHeight: 34 * root.zoom
        implicitWidth: openRow.implicitWidth + 28 * root.zoom
        buttonRadius: Appearance.rounding.full
        colBackground: root.colAccent
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        onClicked: KdeConnectService.openNotificationIntent(root.live?.publicId ?? "")

        Row {
            id: openRow
            anchors.centerIn: parent
            spacing: 6 * root.zoom

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "open_in_new"
                iconSize: 16 * root.zoom
                color: root.colOnAccent
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Open on phone")
                font.pixelSize: Appearance.font.pixelSize.smaller * root.zoom
                font.weight: Font.DemiBold
                color: root.colOnAccent
            }
        }
    }
}
