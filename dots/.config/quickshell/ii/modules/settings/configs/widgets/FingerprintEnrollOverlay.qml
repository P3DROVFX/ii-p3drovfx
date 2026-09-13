pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Guided fingerprint enrollment: pick a finger, then scan it.
 *
 * The ring carries one tick per enrollment stage rather than a smooth arc,
 * because the useful question during enrollment is "how many more times do I
 * touch this thing", not "what fraction am I at". On a match-on-chip reader
 * that is 16 touches, and a bar creeping along by 6% a time reads as broken.
 * The tick count follows the device, so a 5-stage swipe reader gets 5 ticks.
 */
Item {
    id: root

    property bool shown: false
    signal closed

    // pick | scan
    property string step: "pick"
    property string finger: ""

    readonly property bool scanning: Fingerprint.enrollActive && Fingerprint.enrollPhase !== "done"
    readonly property bool succeeded: Fingerprint.enrollPhase === "done"
    readonly property bool failed: Fingerprint.enrollPhase === "failed"

    function open(preselected: string): void {
        Fingerprint.resetEnrollState();
        root.finger = preselected ?? "";
        root.step = "pick";
        root.shown = true;
    }

    function close(): void {
        successCloseTimer.stop();
        if (Fingerprint.enrollActive)
            Fingerprint.cancelEnroll();
        Fingerprint.resetEnrollState();
        root.shown = false;
        root.closed();
    }

    function beginScan(): void {
        if (root.finger === "")
            return;
        root.step = "scan";
        Fingerprint.startEnroll(root.finger);
    }

    visible: opacity > 0
    opacity: root.shown ? 1 : 0
    enabled: root.shown

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
        }
    }

    // Close by itself once the success state has been on screen long enough
    // to register as a success rather than a flicker.
    Timer {
        id: successCloseTimer
        interval: 1600
        onTriggered: root.close()
    }

    onSucceededChanged: {
        if (root.succeeded && root.shown)
            successCloseTimer.restart();
    }

    // Scrim: also swallows clicks aimed at the page underneath.
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (!root.scanning)
                    root.close();
            }
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        implicitHeight: cardLayout.implicitHeight + 40
        height: implicitHeight
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        scale: root.shown ? 1 : 0.94

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        // Keep clicks on the card from reaching the scrim behind it.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 14

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.step === "pick" ? Translation.tr("Choose a finger") : Fingerprint.labelFor(root.finger)
                font.pixelSize: Appearance.font.pixelSize.larger
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                visible: root.step === "pick"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Translation.tr("Pick the finger you want to use. Choosing one that is already enrolled replaces it.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // ── Step 1: finger picker ──────────────────────────────────────
            FingerprintHandPicker {
                Layout.alignment: Qt.AlignHCenter
                visible: root.step === "pick"
                selectedFinger: root.finger
                onFingerPicked: finger => root.finger = finger
            }

            // ── Step 2: scanning ───────────────────────────────────────────
            Item {
                Layout.alignment: Qt.AlignHCenter
                visible: root.step === "scan"
                implicitWidth: 168
                implicitHeight: 168

                readonly property real ringRadius: 70
                readonly property int tickCount: Math.max(1, Fingerprint.numEnrollStages)

                Repeater {
                    id: tickRepeater
                    model: parent.tickCount

                    Rectangle {
                        id: tick

                        required property int index

                        readonly property real angle: -90 + tick.index * (360 / tickRepeater.count)
                        readonly property real rad: tick.angle * Math.PI / 180
                        readonly property bool filled: tick.index < Fingerprint.enrollStage

                        width: 5
                        height: 15
                        radius: Appearance.rounding.full
                        x: parent.width / 2 + parent.ringRadius * Math.cos(tick.rad) - width / 2
                        y: parent.height / 2 + parent.ringRadius * Math.sin(tick.rad) - height / 2
                        rotation: tick.angle + 90
                        transformOrigin: Item.Center

                        color: root.failed ? Appearance.colors.colError : tick.filled ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                        scale: tick.filled ? 1.15 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.succeeded ? "check_circle" : root.failed ? "error" : "fingerprint"
                    iconSize: 76
                    fill: 1
                    color: root.succeeded ? Appearance.colors.colPrimary : root.failed ? Appearance.colors.colError : Appearance.colors.colOnLayer1

                    // A slow breath while waiting for a touch, so the dialog
                    // never looks frozen between stages.
                    SequentialAnimation on opacity {
                        running: root.scanning && Fingerprint.enrollPhase !== "authorizing"
                        loops: Animation.Infinite
                        alwaysRunToEnd: true

                        NumberAnimation {
                            to: 0.45
                            duration: 750
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            to: 1
                            duration: 750
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.step === "scan" && !root.succeeded && !root.failed
                text: `${Fingerprint.enrollStage} / ${Fingerprint.numEnrollStages}`
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                visible: root.step === "scan" && text !== ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Fingerprint.enrollMessage
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.failed ? Appearance.colors.colError : Appearance.colors.colOnLayer1
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: 8

                DialogButton {
                    visible: !root.succeeded
                    buttonText: root.step === "pick" ? Translation.tr("Cancel") : Translation.tr("Stop")
                    onClicked: root.close()
                }

                DialogButton {
                    visible: root.step === "pick"
                    enabled: root.finger !== "" && Fingerprint.deviceAvailable
                    buttonText: Fingerprint.enrolled.indexOf(root.finger) !== -1 ? Translation.tr("Replace") : Translation.tr("Start")
                    onClicked: root.beginScan()
                }

                DialogButton {
                    visible: root.failed
                    buttonText: Translation.tr("Try again")
                    onClicked: {
                        Fingerprint.resetEnrollState();
                        root.step = "pick";
                    }
                }

                DialogButton {
                    visible: root.succeeded
                    buttonText: Translation.tr("Done")
                    onClicked: root.close()
                }
            }
        }
    }
}
