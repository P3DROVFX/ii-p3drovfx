pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.akebono
import qs.modules.ii.lock as IiLock
import Quickshell

MouseArea {
    id: root
    required property LockContext context

    property bool ctrlHeld: false
    property real introScale: 0.96
    property real introOpacity: 0

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    function forceFieldFocus(): void {
        passwordBox.forceActiveFocus();
    }

    function requestPower(action): void {
        if (!Config.options.lock.security.requirePasswordToPower) {
            root.context.unlocked(action);
            return;
        }
        if (root.context.targetAction === action)
            root.context.resetTargetAction();
        else {
            root.context.targetAction = action;
            root.context.shouldReFocus();
        }
    }

    Connections {
        target: root.context
        function onShouldReFocus() { root.forceFieldFocus(); }
    }

    onPressed: root.forceFieldFocus()
    onPositionChanged: root.forceFieldFocus()

    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = true;
        if (event.key === Qt.Key_Escape)
            root.context.currentText = "";
        root.forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = false;
    }

    Component.onCompleted: {
        root.forceFieldFocus();
        root.introScale = 1;
        root.introOpacity = 1;
    }
    Behavior on introScale {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on introOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: Math.round(parent.height * 0.13)
        }
        spacing: 0
        opacity: root.introOpacity

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: DateTime.time
            color: Appearance.colors.colOnLayer1
            font {
                family: Appearance.font.family.title
                pixelSize: 92
                variableAxes: Appearance.font.variableAxes.title
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: DateTime.collapsedCalendarFormat
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.25)
            font.pixelSize: Appearance.font.pixelSize.huge
        }
    }

    ColumnLayout {
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
        spacing: 16
        scale: root.introScale
        opacity: root.introOpacity

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 96
            implicitHeight: 96

            MaterialSymbol {
                anchors.centerIn: parent
                text: "account_circle"
                iconSize: 96
                fill: 1
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.3)
                visible: avatar.status !== Image.Ready
            }
            StyledImage {
                id: avatar
                anchors.fill: parent
                sourceSize: Qt.size(96, 96)
                source: Directories.userAvatarPathAccountsService
                fallbacks: [Directories.userAvatarPathRicersAndWeirdSystems, Directories.userAvatarPathRicersAndWeirdSystems2]
                visible: status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Squircle {
                        width: avatar.width
                        height: avatar.height
                        radius: 32
                        smoothing: AkebonoAppearance.squircleSmoothing
                        color: "white"
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 4
            text: SystemInfo.username
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.huge
        }

        Item {
            id: fieldWrap
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 320
            implicitHeight: 50

            EdgeWaveSquircle {
                id: fieldBg
                anchors.fill: parent
                radius: height / 2
                smoothing: AkebonoAppearance.squircleSmoothing
                color: Appearance.colors.colLayer1
            }

            TextField {
                id: passwordBox
                anchors.fill: parent
                padding: 0
                leftPadding: 20
                rightPadding: 20
                verticalAlignment: TextInput.AlignVCenter
                background: null
                clip: true
                placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")
                placeholderTextColor: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.5)
                font.pixelSize: Appearance.font.pixelSize.normal
                echoMode: TextInput.Password
                passwordCharacter: "●"
                inputMethodHints: Qt.ImhSensitiveData
                enabled: !root.context.unlockInProgress

                property bool materialShapeChars: Config.options.lock.materialShapeChars
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
                selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
                selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

                onTextChanged: root.context.currentText = text
                onAccepted: root.context.tryUnlock(root.ctrlHeld)
                Keys.onPressed: event => root.context.resetClearTimer()
                Connections {
                    target: root.context
                    function onCurrentTextChanged() {
                        passwordBox.text = root.context.currentText;
                    }
                }

                TextEditContextMenuArea {
                    editor: passwordBox
                }

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: passwordBox.width
                        height: passwordBox.height
                        radius: height / 2
                    }
                }

                Loader {
                    active: passwordBox.materialShapeChars
                    anchors {
                        fill: parent
                        leftMargin: passwordBox.leftPadding
                        rightMargin: passwordBox.rightPadding
                    }
                    sourceComponent: IiLock.PasswordChars {
                        length: root.context.currentText.length
                        selectionStart: passwordBox.selectionStart
                        selectionEnd: passwordBox.selectionEnd
                        cursorPosition: passwordBox.cursorPosition
                    }
                }
            }

            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed)
                        fieldBg.buzz();
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2
            spacing: 10

            PowerButton {
                icon: "dark_mode"
                onActivated: Session.suspend()
            }
            PowerButton {
                icon: "power_settings_new"
                targetAction: LockContext.ActionEnum.Poweroff
                onActivated: root.requestPower(LockContext.ActionEnum.Poweroff)
            }
            PowerButton {
                icon: "restart_alt"
                targetAction: LockContext.ActionEnum.Reboot
                onActivated: root.requestPower(LockContext.ActionEnum.Reboot)
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2
            spacing: 6
            visible: root.context.fingerprintsConfigured

            MaterialSymbol {
                text: "fingerprint"
                iconSize: Appearance.font.pixelSize.huge
                fill: 1
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.35)
            }
            StyledText {
                text: Translation.tr("Touch the sensor to unlock")
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.35)
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    component PowerButton: Item {
        id: powerButton
        property string icon
        property var targetAction
        signal activated()

        readonly property bool armed: powerButton.targetAction !== undefined && root.context.targetAction === powerButton.targetAction
        implicitWidth: 44
        implicitHeight: 44

        Squircle {
            anchors.fill: parent
            radius: 15
            smoothing: AkebonoAppearance.squircleSmoothing
            color: powerButton.armed ? Appearance.colors.colPrimary
                : powerButtonArea.containsMouse ? Appearance.colors.colLayer1Hover
                : Appearance.colors.colLayer1
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: powerButton.icon
            iconSize: 22
            color: powerButton.armed ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: powerButtonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                powerButton.activated();
                root.forceFieldFocus();
            }
        }
    }
}
