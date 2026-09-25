pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Android's timer entry: digits fill "00h 00m 00s" from the right, a keypad of keys that
 * square off under the finger, presets as chips, and the start button once there is a
 * duration. The physical keyboard types into it too.
 */
FocusScope {
    id: root

    property bool compact: false
    property bool canCancel: false

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property int maxDigits: 6
    readonly property real keySize: Math.max(ClockStyle.keypadKeyMin, Math.min(ClockStyle.keypadKeyMax,
        (root.width - ClockStyle.gap * 2 - ClockStyle.gapHuge * 2) / 3.36,
        (root.height - ClockStyle.chipHeight - ClockStyle.fabSize * 1.15 - ClockStyle.gapHuge * 4) / 4.61))
    readonly property real displaySize: Math.max(ClockStyle.displayDigitMin * 0.8, Math.min(root.keySize * 0.9, ClockStyle.displayDigitMax * 0.8))
    readonly property color colTyped: ClockStyle.colPrimary
    readonly property color colEmpty: ClockStyle.colOutline
    readonly property color colKey: ClockStyle.colSurfaceHigh
    readonly property color colKeyHover: ClockStyle.colSurfaceHover
    readonly property color colOnKey: ClockStyle.colOnSurface

    property string digits: ""
    readonly property string padded: root.digits.padStart(root.maxDigits, "0")
    readonly property int hours: parseInt(root.padded.slice(0, 2))
    readonly property int minutes: parseInt(root.padded.slice(2, 4))
    readonly property int seconds: parseInt(root.padded.slice(4, 6))
    readonly property int totalSeconds: root.hours * 3600 + root.minutes * 60 + root.seconds
    readonly property var presets: Array.from(Config.options.time.timer?.presets ?? [])

    signal startRequested(int seconds)
    signal cancelRequested()

    function press(key: string): void {
        if (key === "back") {
            root.digits = root.digits.slice(0, -1);
            return;
        }
        const next = (root.digits + key).replace(/^0+/, "");
        if (next.length <= root.maxDigits)
            root.digits = next;
    }

    function setSeconds(value: int): void {
        const h = Math.floor(value / 3600);
        const m = Math.floor((value % 3600) / 60);
        const s = value % 60;
        root.digits = (ClockFormat.pad(h) + ClockFormat.pad(m) + ClockFormat.pad(s)).replace(/^0+/, "");
    }

    function start(): void {
        if (root.totalSeconds <= 0)
            return;
        root.startRequested(root.totalSeconds);
        root.digits = "";
    }

    function savePreset(): void {
        if (root.totalSeconds <= 0 || root.presets.includes(root.totalSeconds))
            return;
        Config.options.time.timer.presets = root.presets.concat([root.totalSeconds]).sort((a, b) => a - b);
    }

    implicitHeight: keypadColumn.implicitHeight + ClockStyle.gapHuge * 2
    focus: true
    Component.onCompleted: root.forceActiveFocus()

    Keys.onPressed: event => {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            root.press(String(event.key - Qt.Key_0));
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            root.press("back");
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.start();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.canCancel) {
            root.cancelRequested();
            event.accepted = true;
        }
    }

    component Unit: RowLayout {
        id: unit
        property string value: "00"
        property string suffix: ""
        property bool typed: false
        spacing: 2

        StyledText {
            text: unit.value
            font.family: ClockStyle.fontMain
            font.variableAxes: ClockStyle.axesDigitsBold
            font.pixelSize: root.displaySize
            color: unit.typed ? root.colTyped : root.colEmpty

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: root.displaySize * 0.14
            text: unit.suffix
            font.pixelSize: root.displaySize * 0.3
            color: unit.typed ? root.colTyped : root.colEmpty
        }
    }

    ColumnLayout {
        id: keypadColumn
        anchors.centerIn: parent
        width: Math.min(parent.width, root.keySize * 3 + ClockStyle.gap * 2 + ClockStyle.gapHuge * 2)
        spacing: ClockStyle.gapLarge

        RowLayout {
            id: displayRow
            Layout.alignment: Qt.AlignHCenter
            spacing: ClockStyle.gap

            Unit {
                value: root.padded.slice(0, 2)
                suffix: Translation.tr("h")
                typed: root.digits.length > 4
            }
            Unit {
                value: root.padded.slice(2, 4)
                suffix: Translation.tr("m")
                typed: root.digits.length > 2
            }
            Unit {
                value: root.padded.slice(4, 6)
                suffix: Translation.tr("s")
                typed: root.digits.length > 0
            }
        }

        Flow {
            id: presetFlow
            Layout.fillWidth: true
            Layout.maximumWidth: parent.width
            spacing: ClockStyle.gapSmall
            visible: root.presets.length > 0

            Repeater {
                model: root.presets

                ClockChip {
                    required property var modelData
                    symbol: "bolt"
                    label: ClockFormat.shortDuration(modelData)
                    selected: root.totalSeconds === Number(modelData)
                    onClicked: root.setSeconds(Number(modelData))
                }
            }
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 3
            rowSpacing: ClockStyle.gap * 0.75
            columnSpacing: ClockStyle.gap

            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "back"]

                RippleButton {
                    id: key
                    required property string modelData
                    readonly property bool isBack: key.modelData === "back"

                    implicitWidth: root.keySize * 1.12
                    implicitHeight: root.keySize * 0.86
                    buttonRadius: ClockStyle.pill(implicitHeight)
                    buttonRadiusPressed: ClockStyle.radiusNormal
                    colBackground: key.isBack ? ClockStyle.colSecondaryContainer : root.colKey
                    colBackgroundHover: key.isBack ? ClockStyle.colSecondaryContainerHover : root.colKeyHover
                    colRipple: ClockStyle.colSurfaceActive
                    enabled: !key.isBack || root.digits.length > 0
                    onClicked: root.press(key.modelData)

                    contentItem: Item {
                        StyledText {
                            anchors.centerIn: parent
                            visible: !key.isBack
                            text: key.modelData
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDisplay
                            font.pixelSize: root.keySize * 0.36
                            color: root.colOnKey
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: key.isBack
                            text: "backspace"
                            iconSize: root.keySize * 0.32
                            color: ClockStyle.colOnSecondaryContainer
                        }
                    }
                }
            }
        }

        RowLayout {
            id: startRow
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ClockStyle.gapSmall
            spacing: ClockStyle.gapLarge

            ClockIconButton {
                visible: root.canCancel
                symbol: "close"
                tooltip: Translation.tr("Cancel")
                colBackground: ClockStyle.colSurfaceHigh
                size: ClockStyle.fabSize * 0.75
                onClicked: root.cancelRequested()
            }

            ClockPlayButton {
                running: false
                size: ClockStyle.fabSize * 1.15
                opacity: root.totalSeconds > 0 ? 1 : 0.35
                enabled: root.totalSeconds > 0
                onClicked: root.start()

                Behavior on opacity {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            ClockIconButton {
                symbol: "bookmark_add"
                tooltip: Translation.tr("Save as preset")
                colBackground: ClockStyle.colSurfaceHigh
                size: ClockStyle.fabSize * 0.75
                enabled: root.totalSeconds > 0 && !root.presets.includes(root.totalSeconds)
                onClicked: root.savePreset()
            }
        }
    }
}
