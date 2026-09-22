pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The Tuner OSD face: a round icon, then a ruler (the sliders), an OFF·ON selector (on/off
 * pills) or just the message (a plain notice).
 *
 * It has no background of its own and hugs its content: the Dynamic Island
 * (NotchContent.osdTargetWidth) and the standalone window (TunerOsdWindow) read
 * `osdWidth`/`osdHeight` and size themselves to it.
 */
Item {
    id: root

    property string indicator: GlobalStates.osdCurrentIndicator

    readonly property int padLeft: 16
    readonly property int padRight: 20
    readonly property int iconSize: 40
    readonly property int iconGap: 10

    readonly property int osdWidth: bodyLoader.item
        ? Math.ceil(root.padLeft + root.iconSize + root.iconGap + bodyLoader.item.implicitWidth + root.padRight) : 0
    readonly property int osdHeight: 72
    // Stays centred while its holder morphs to (or away from) the width it asked for.
    readonly property real originX: Math.round((root.width - root.osdWidth) / 2)

    readonly property var pill: GlobalStates.osdPill ?? ({})
    readonly property string pillState: (root.pill.state === "on" || root.pill.state === "off") ? root.pill.state : ""
    readonly property bool lit: root.indicator === "toggle" && root.pillState !== "off"

    readonly property real volumeMax: (Config.options.audio && Config.options.audio.protection
        && Config.options.audio.protection.enable) ? Config.options.audio.protection.maxAllowed / 100 : 1.5
    readonly property var brightnessMonitor: Brightness.getTargetMonitor()

    readonly property string iconName: {
        switch (root.indicator) {
        case "volume": {
            if (Audio.muted)
                return "volume_off";
            if (Audio.value <= 0.33)
                return "volume_mute";
            return Audio.value <= 0.66 ? "volume_down" : "volume_up";
        }
        case "brightness": {
            if (Hyprsunset.temperatureActive)
                return "routine";
            const val = root.brightnessMonitor?.brightness ?? 0.5;
            if (val <= 0.33)
                return "brightness_low";
            return val <= 0.66 ? "brightness_medium" : "brightness_high";
        }
        case "playerVolume":
            return "music_note";
        case "gamma":
            return "wb_twilight";
        case "keyboardBrightness":
            return "keyboard";
        case "toggle":
            return root.pill.icon || "info";
        }
        return "info";
    }

    // The selector already shows the state, so "Fn Lock on" reads "Fn Lock" here. Senders keep
    // their full label for the other OSD styles.
    function stripState(label: string): string {
        return label.replace(/\s+(on|off|enabled|disabled|started|stopped|muted|unmuted|active|inactive)$/i, "");
    }

    implicitWidth: root.osdWidth
    implicitHeight: root.osdHeight

    Rectangle {
        x: root.originX + root.padLeft
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSize
        height: root.iconSize
        radius: root.iconSize / 2
        color: root.lit ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerHigh

        Behavior on color {
            ColorAnimation {
                duration: 300
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.iconName
            iconSize: 24
            fill: 1
            color: root.lit ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0

            Behavior on color {
                ColorAnimation {
                    duration: 300
                }
            }
        }
    }

    Loader {
        id: bodyLoader
        x: root.originX + root.padLeft + root.iconSize + root.iconGap
        anchors.verticalCenter: parent.verticalCenter
        height: root.osdHeight
        // One component per indicator, so moving from one slider to another builds a fresh
        // ruler instead of sliding the old one to the new value.
        sourceComponent: {
            switch (root.indicator) {
            case "volume":
                return volumeBody;
            case "brightness":
                return brightnessBody;
            case "playerVolume":
                return playerVolumeBody;
            case "gamma":
                return gammaBody;
            case "keyboardBrightness":
                return keyboardBody;
            case "toggle":
                return root.pillState !== "" ? switchBody : noticeBody;
            }
            return null;
        }
    }

    Component {
        id: volumeBody

        TunerSlider {
            label: Translation.tr("Volume")
            value: Audio.muted ? 0 : Audio.value * 100
            to: Math.round(root.volumeMax * 100)
            safeLimit: root.volumeMax > 1 ? 100 : 0
            onValueUpdateRequested: newValue => {
                if (!Audio.sink?.audio)
                    return;
                Audio.sink.audio.volume = newValue / 100;
                if (Audio.sink.audio.muted && newValue > 0)
                    Audio.sink.audio.muted = false;
            }
        }
    }

    Component {
        id: brightnessBody

        TunerSlider {
            label: Translation.tr("Brightness")
            value: (root.brightnessMonitor?.brightness ?? 0.5) * 100
            onValueUpdateRequested: newValue => root.brightnessMonitor?.setBrightness(newValue / 100)
        }
    }

    Component {
        id: playerVolumeBody

        TunerSlider {
            label: Translation.tr("Music")
            value: (MprisController.activePlayer?.volume ?? 0) * 100
            onValueUpdateRequested: newValue => {
                if (MprisController.activePlayer)
                    MprisController.activePlayer.volume = newValue / 100;
            }
        }
    }

    Component {
        id: gammaBody

        TunerSlider {
            label: Translation.tr("Gamma")
            value: Hyprsunset.gamma
            from: Hyprsunset.gammaLowerLimit
            onValueUpdateRequested: newValue => Hyprsunset.setGamma(Math.round(newValue))
        }
    }

    Component {
        id: keyboardBody

        TunerSlider {
            label: Translation.tr("Keyboard backlight")
            value: KeyboardBacklight.currentValue
            to: Math.max(1, KeyboardBacklight.maxValue)
            stepped: true
            onValueUpdateRequested: newValue => {
                if (KeyboardBacklight.available && KeyboardBacklight.ready)
                    KeyboardBacklight.setValue(newValue);
            }
        }
    }

    Component {
        id: switchBody

        TunerSwitch {
            label: root.stripState(root.pill.label ?? "")
            on: root.pillState === "on"
            ruler: Config.options.osd.tuner?.toggleRuler ?? false
        }
    }

    Component {
        id: noticeBody

        Item {
            implicitWidth: Math.min(360, noticeText.implicitWidth) + 8
            implicitHeight: root.osdHeight

            StyledText {
                id: noticeText
                width: Math.min(360, implicitWidth)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.pill.label ?? ""
                color: Appearance.colors.colOnLayer0
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }
        }
    }
}
