pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Fingerprint settings: turn fingerprint unlock on or off, and manage the
 * prints fprintd stores for this user.
 *
 * Everything here only affects this shell's lock screen. The prints themselves
 * are system-wide, so a fingerprint enrolled here can be used by anything else
 * that speaks to fprintd — that just has to be set up separately.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack

    readonly property var fpOptions: Config.options.lock.security.fingerprint
    readonly property string fingerBeingRenamed: renameState.finger

    QtObject {
        id: renameState
        property string finger: ""
    }

    // fprintd state can change from outside the shell (fprintd-enroll in a
    // terminal, a reader unplugged), so re-probe whenever this page appears
    // rather than trusting whatever was true at startup.
    Component.onCompleted: Fingerprint.refresh()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Fingerprint")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Reader status ──────────────────────────────────────────────────
        ContentSection {
            icon: "fingerprint"
            title: Translation.tr("Reader")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: readerLayout.implicitHeight + 28
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: readerLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 14

                    MaterialSymbol {
                        text: Fingerprint.deviceAvailable ? "fingerprint" : "sensors_off"
                        iconSize: 34
                        fill: 1
                        color: Fingerprint.deviceAvailable ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Fingerprint.deviceAvailable ? (Fingerprint.deviceName !== "" ? Fingerprint.deviceName : Translation.tr("Fingerprint reader")) : !Fingerprint.probed ? Translation.tr("Looking for a reader…") : Translation.tr("No fingerprint reader detected")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: {
                                if (!Fingerprint.deviceAvailable)
                                    return Translation.tr("Make sure fprintd is installed and the reader is supported by libfprint.");
                                const kind = Fingerprint.pressType ? Translation.tr("Press reader") : Translation.tr("Swipe reader");
                                return `${kind} · ${Translation.tr("%1 scans per fingerprint").arg(Fingerprint.numEnrollStages)}`;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        enabled: !Fingerprint.busy
                        onClicked: Fingerprint.refresh()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("Re-check the reader and enrolled fingerprints")
                        }
                    }
                }
            }
        }

        // ── Unlock behaviour ───────────────────────────────────────────────
        ContentSection {
            icon: "lock_open"
            title: Translation.tr("Unlock")

            ConfigSwitch {
                buttonIcon: "fingerprint"
                text: Translation.tr("Unlock with fingerprint")
                checked: subPageRoot.fpOptions.enable
                onCheckedChanged: {
                    subPageRoot.fpOptions.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Arm the reader on the lock screen. Turning this off keeps your fingerprints; it only stops them from unlocking the session.")
                }
            }

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Show fingerprint status on lock screen")
                checked: subPageRoot.fpOptions.showIndicator
                enabled: subPageRoot.fpOptions.enable
                onCheckedChanged: {
                    subPageRoot.fpOptions.showIndicator = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Show the fingerprint icon and remaining attempts next to the password box, including when the reader is unavailable.")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: subPageRoot.fpOptions.enable && Fingerprint.enrolledLoaded && !Fingerprint.hasEnrolled
                materialIcon: "info"
                text: Translation.tr("Fingerprint unlock is on, but no fingerprints are enrolled yet. Add one below.")
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Fingerprint.hasEnrolled
                materialIcon: "shield"
                text: Translation.tr("Fingerprints unlock this shell's lock screen only. Using them for sudo, polkit or the display manager means editing the matching files in /etc/pam.d yourself.")
            }
        }

        // ── Enrolled prints ────────────────────────────────────────────────
        ContentSection {
            icon: "list"
            title: Translation.tr("Your fingerprints")

            StyledText {
                Layout.fillWidth: true
                visible: Fingerprint.enrolledLoaded && !Fingerprint.hasEnrolled
                wrapMode: Text.WordWrap
                text: Translation.tr("No fingerprints enrolled yet.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: Fingerprint.enrolled

                delegate: Rectangle {
                    id: printRow

                    required property string modelData

                    readonly property string finger: printRow.modelData
                    readonly property bool renaming: renameState.finger === printRow.finger
                    readonly property bool verifyingThis: Fingerprint.verifyActive && Fingerprint.verifyFinger === printRow.finger
                    readonly property bool showingResult: Fingerprint.verifyResult !== "" && Fingerprint.verifyFinger === printRow.finger

                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + 20
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        id: rowLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        anchors.rightMargin: 10
                        spacing: 12

                        MaterialSymbol {
                            text: "fingerprint"
                            iconSize: 26
                            fill: 1
                            color: printRow.showingResult ? (Fingerprint.verifyResult === "match" ? Appearance.colors.colPrimary : Appearance.colors.colError) : Appearance.colors.colOnLayer2
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: !printRow.renaming

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Fingerprint.labelFor(printRow.finger)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: {
                                    if (printRow.verifyingThis)
                                        return Fingerprint.verifyMessage;
                                    if (printRow.showingResult)
                                        return Fingerprint.verifyMessage;
                                    return Fingerprint.defaultLabelFor(printRow.finger);
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: printRow.showingResult ? (Fingerprint.verifyResult === "match" ? Appearance.colors.colPrimary : Appearance.colors.colError) : Appearance.colors.colSubtext
                            }
                        }

                        MaterialTextField {
                            id: renameField
                            Layout.fillWidth: true
                            visible: printRow.renaming
                            placeholderText: Fingerprint.defaultLabelFor(printRow.finger)

                            onVisibleChanged: {
                                if (!visible)
                                    return;
                                text = Fingerprint.customLabelFor(printRow.finger);
                                forceActiveFocus();
                                selectAll();
                            }

                            onAccepted: {
                                Fingerprint.setLabel(printRow.finger, text);
                                renameState.finger = "";
                            }

                            Keys.onEscapePressed: renameState.finger = ""
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            visible: printRow.renaming
                            onClicked: {
                                Fingerprint.setLabel(printRow.finger, renameField.text);
                                renameState.finger = "";
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 20
                                color: Appearance.colors.colPrimary
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            visible: !printRow.renaming
                            onClicked: renameState.finger = printRow.finger

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "edit"
                                iconSize: 19
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledToolTip {
                                text: Translation.tr("Rename")
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            visible: !printRow.renaming
                            enabled: !Fingerprint.busy || printRow.verifyingThis
                            onClicked: {
                                if (printRow.verifyingThis)
                                    Fingerprint.cancelVerify();
                                else
                                    Fingerprint.startVerify(printRow.finger);
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: printRow.verifyingThis ? "stop" : "touch_app"
                                iconSize: 20
                                color: printRow.verifyingThis ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                            }

                            StyledToolTip {
                                text: printRow.verifyingThis ? Translation.tr("Stop the test") : Translation.tr("Test this fingerprint")
                            }
                        }

                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            visible: !printRow.renaming
                            enabled: !Fingerprint.busy
                            colBackgroundHover: Appearance.colors.colErrorContainer
                            onClicked: Fingerprint.deletePrint(printRow.finger)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: 20
                                color: Appearance.colors.colError
                            }

                            StyledToolTip {
                                text: Translation.tr("Delete this fingerprint")
                            }
                        }
                    }
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Fingerprint.lastError !== ""
                materialIcon: "error"
                text: Fingerprint.lastError
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                RippleButtonWithIcon {
                    materialIcon: "add"
                    mainText: Translation.tr("Add fingerprint")
                    enabled: Fingerprint.deviceAvailable && !Fingerprint.busy
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    colText: Appearance.colors.colOnPrimaryContainer
                    onClicked: enrollOverlay.open("")
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButtonWithIcon {
                    materialIcon: "delete_sweep"
                    mainText: Translation.tr("Remove all")
                    visible: Fingerprint.enrolled.length > 1
                    enabled: !Fingerprint.busy
                    colText: Appearance.colors.colError
                    onClicked: Fingerprint.deleteAll()
                }
            }
        }
    }

    FingerprintEnrollOverlay {
        id: enrollOverlay
        anchors.fill: parent
        z: 20
    }
}
