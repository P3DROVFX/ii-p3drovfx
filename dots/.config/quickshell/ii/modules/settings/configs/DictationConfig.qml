import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Dictation — speech typed into whatever window has focus.
 *
 * The page is honest about the two things that can be missing: voxtype itself,
 * which nothing here installs, and the speech model, which is a download this
 * page can actually perform. Everything else only becomes reachable once those
 * two are in place, so the switch never promises something that cannot happen.
 */
ContentPage {
    id: page
    forceWidth: false

    readonly property bool installed: DictationService.installed
    readonly property bool ready: DictationService.available

    function linuxFamilyFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "Arch Linux";
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "Fedora / RHEL";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "Debian / Ubuntu";
        return SystemInfo.distroName && SystemInfo.distroName !== "Unknown" ? SystemInfo.distroName : "Linux";
    }

    /**
     * Voxtype publishes an AUR package and prebuilt .deb/.rpm archives, so the
     * honest instruction differs per distro rather than being one command with
     * a swapped package manager.
     */
    function installCommandFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "yay -S voxtype-bin";
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "# Grab the latest .rpm from https://voxtype.io/download/\n" +
                "sudo dnf install ./voxtype-*.rpm";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "# Grab the latest .deb from https://voxtype.io/download/\n" +
                "sudo apt install ./voxtype_*.deb";
        return "# Download a build for your distro from https://voxtype.io/download/";
    }

    readonly property string linuxFamily: page.linuxFamilyFor(SystemInfo.distroId)
    readonly property string installCommand: page.installCommandFor(SystemInfo.distroId)

    // The languages worth a one-click entry. Whisper handles 99; the rest are
    // reachable through the code field below rather than a scroll of flags.
    readonly property var languageOptions: [
        { displayName: Translation.tr("Auto-detect"), value: "auto" },
        { displayName: Translation.tr("English"), value: "en" },
        { displayName: Translation.tr("French"), value: "fr" },
        { displayName: Translation.tr("Spanish"), value: "es" },
        { displayName: Translation.tr("German"), value: "de" },
        { displayName: Translation.tr("Italian"), value: "it" },
        { displayName: Translation.tr("Portuguese"), value: "pt" },
        { displayName: Translation.tr("Dutch"), value: "nl" },
        { displayName: Translation.tr("Polish"), value: "pl" },
        { displayName: Translation.tr("Russian"), value: "ru" },
        { displayName: Translation.tr("Ukrainian"), value: "uk" },
        { displayName: Translation.tr("Turkish"), value: "tr" },
        { displayName: Translation.tr("Arabic"), value: "ar" },
        { displayName: Translation.tr("Hindi"), value: "hi" },
        { displayName: Translation.tr("Chinese"), value: "zh" },
        { displayName: Translation.tr("Japanese"), value: "ja" },
        { displayName: Translation.tr("Korean"), value: "ko" },
        { displayName: Translation.tr("Catalan"), value: "ca" },
        { displayName: Translation.tr("Swedish"), value: "sv" },
        { displayName: Translation.tr("Czech"), value: "cs" }
    ]

    KeyboardShortcutBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        text: Translation.tr("Start or stop dictation")
        keys: ["Super", "Shift", "D"]
    }

    // ── Setup ────────────────────────────────────────────────────────────────
    ContentSection {
        visible: !page.installed
        icon: "download"
        title: Translation.tr("Install Voxtype")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Dictation runs on Voxtype, a local speech-to-text daemon. Speech is transcribed on this machine and typed into the window you are already working in — nothing is sent anywhere. Install it, then press Check again.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        HelperCodeBox {
            Layout.fillWidth: true
            Layout.topMargin: 4
            topLeftRadius: Appearance.rounding.large
            topRightRadius: Appearance.rounding.large
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            icon: "terminal"
            title: Translation.tr("Install voxtype · %1").arg(page.linuxFamily)
            text: Translation.tr("Run this in a terminal, then press Check again below.")
            codeSnippet: page.installCommand
            snippetWrapMode: Text.Wrap
        }

        RippleButtonWithIcon {
            Layout.topMargin: 4
            materialIcon: "refresh"
            mainText: Translation.tr("Check again")
            onClicked: DictationService.redetect()
        }
    }

    // ── Main switch and status ───────────────────────────────────────────────
    ContentSection {
        icon: "mic"
        title: Translation.tr("Dictation")

        ConfigSwitch {
            buttonIcon: "keyboard_voice"
            text: Translation.tr("Type what I say into the focused window")
            checked: Config.options.dictation.enabled
            enabled: page.installed
            onCheckedChanged: {
                Config.options.dictation.enabled = checked;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: page.ready ? "check_circle" : "info"
                iconSize: Appearance.font.pixelSize.large
                color: page.ready ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: page.ready
                        ? Translation.tr("Ready — %1, %2.").arg(DictationService.qualityLabel).arg(DictationService.requiredModel)
                        : Translation.tr("Not ready yet")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !page.ready
                    text: DictationService.unavailableReason()
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.installed && !DictationService.bridgeInstalled
                    text: Translation.tr("The voxtype-audio-bridge helper is missing, so the notch shows a pulse instead of your voice's waveform. Dictation itself is unaffected.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: DictationService.lastError.length > 0
                    text: DictationService.lastError
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: Translation.tr("The daemon runs for as long as the shell does, and stops when this switch is off.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // ── Engine ───────────────────────────────────────────────────────────────
    ContentSection {
        visible: page.installed
        icon: "graphic_eq"
        title: Translation.tr("Speech model")

        ContentSubsection {
            title: Translation.tr("Quality")
            icon: "tune"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.dictation.quality
                onSelected: newValue => {
                    Config.options.dictation.quality = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Fast · 142 MB"),
                        icon: "bolt",
                        value: "fast"
                    },
                    {
                        displayName: Translation.tr("Accurate · 1.6 GB"),
                        icon: "target",
                        value: "accurate"
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                text: Config.options.dictation.quality === "accurate"
                    ? Translation.tr("large-v3-turbo. Understands every language Whisper knows and handles accents and background noise better, at a noticeably longer wait after you stop speaking.")
                    : Translation.tr("The base model. Quick to load and quick to transcribe — a good everyday default for clear speech.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        ContentSubsection {
            title: Translation.tr("Download")
            icon: "cloud_download"
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: DictationService.modelReady ? "check_circle" : "cloud_download"
                    iconSize: Appearance.font.pixelSize.large
                    color: DictationService.modelReady ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: DictationService.requiredModel
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (DictationService.downloadingModel.length > 0)
                                return Translation.tr("Downloading %1… %2%")
                                    .arg(DictationService.downloadingModel)
                                    .arg(Math.round(DictationService.downloadProgress * 100));
                            if (DictationService.requiredModelIncomplete)
                                return Translation.tr("A download of %1 is still running.").arg(DictationService.requiredModel);
                            if (DictationService.modelReady)
                                return Translation.tr("Downloaded and in use.");
                            return Translation.tr("Not downloaded yet · %1 · one-time download")
                                .arg(DictationService.requiredModelSize);
                        }
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButtonWithIcon {
                    visible: !DictationService.modelReady
                    enabled: DictationService.downloadingModel.length === 0
                    materialIcon: "download"
                    mainText: DictationService.downloadingModel.length > 0
                        ? Translation.tr("Downloading…")
                        : Translation.tr("Download")
                    onClicked: DictationService.downloadModel(DictationService.requiredModel)
                }
            }

            StyledProgressBar {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: DictationService.downloadingModel.length > 0
                value: DictationService.downloadProgress
                valueBarHeight: 6
                wavy: true
                animateWave: true
            }

            StyledText {
                Layout.fillWidth: true
                visible: !DictationService.modelReady && DictationService.installedModels.length > 0
                    && DictationService.downloadingModel.length === 0
                text: Config.options.dictation.quality === "accurate"
                    ? Translation.tr("The fast option's model is already downloaded, if you would rather not wait for this one.")
                    : Translation.tr("A model you already downloaded would also work — switching quality above avoids a second download.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // Whichever models are on disk but not the one in use — dictation
            // works without them, and the accurate one costs 1.6 GB to keep.
            Repeater {
                model: DictationService.installedModels.filter(entry => entry !== DictationService.requiredModel)

                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "database"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 · downloaded, not in use").arg(modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    RippleButtonWithIcon {
                        materialIcon: "delete"
                        mainText: Translation.tr("Remove")
                        onClicked: DictationService.removeModel(modelData)
                    }
                }
            }
        }
    }

    // ── Speed ────────────────────────────────────────────────────────────────
    ContentSection {
        visible: page.installed
        icon: "speed"
        title: Translation.tr("Speed")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: DictationService.onGpu ? "bolt" : "memory"
                iconSize: Appearance.font.pixelSize.large
                color: DictationService.onGpu ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: DictationService.backend.length > 0
                        ? Translation.tr("Transcribing on %1").arg(DictationService.backend)
                        : Translation.tr("Backend unknown")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (DictationService.gpuAvailable)
                            return Translation.tr("A GPU build of voxtype is installed but not in use. On integrated graphics this is typically the difference between waiting most of a minute for the accurate model and waiting a second or two.");
                        if (DictationService.onGpu)
                            return Translation.tr("The accurate model is usable at this speed; on the processor alone it is several times slower than real time.");
                        return Translation.tr("No GPU build of voxtype is installed, so transcription runs on the processor. The fast model is the practical choice here.");
                    }
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButtonWithIcon {
                visible: DictationService.gpuAvailable
                materialIcon: "bolt"
                mainText: Translation.tr("Use the GPU")
                onClicked: DictationService.enableGpu()
            }
        }

        ConfigSpinBox {
            icon: "memory"
            text: Translation.tr("Processor threads (0 keeps one core free)")
            value: Config.options.dictation.threads
            from: 0
            to: 64
            stepSize: 1
            onValueChanged: {
                Config.options.dictation.threads = value;
            }
            StyledToolTip {
                text: Translation.tr("Whisper uses four threads by default however many the machine has. Zero here means all but one, which is usually the faster choice while transcription is the thing being waited on.")
            }
        }
    }

    // ── Language ─────────────────────────────────────────────────────────────
    ContentSection {
        visible: page.installed
        icon: "translate"
        title: Translation.tr("Language")

        StyledComboBox {
            id: languageSelector
            buttonIcon: "language"
            textRole: "displayName"
            model: page.languageOptions
            currentIndex: {
                const index = page.languageOptions.findIndex(item => item.value === Config.options.dictation.language);
                return index !== -1 ? index : 0;
            }
            onActivated: index => {
                Config.options.dictation.language = page.languageOptions[index].value;
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: {
                if (Config.options.dictation.language === "auto")
                    return Translation.tr("Whisper works out which language is being spoken from the first seconds of audio. Costs a moment of accuracy on very short phrases.");
                if (Config.options.dictation.language === "en")
                    return Translation.tr("English uses Whisper's English-only model, which is more accurate than the multilingual one at the same size.");
                return Translation.tr("Anything other than English needs Whisper's multilingual model. It is the same size as the English one, so the fast option stays fast.");
            }
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        ContentSubsection {
            title: Translation.tr("Other languages")
            icon: "spellcheck"
            Layout.fillWidth: true

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Language codes, e.g. el — or en,fr to allow either")
                text: Config.options.dictation.language
                onAccepted: {
                    const value = text.trim().toLowerCase();
                    if (value.length > 0)
                        Config.options.dictation.language = value;
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Whisper knows 99 languages by their two-letter code. Listing several lets it detect between just those, which is steadier than full auto-detection when you switch between a known handful.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        ContentSubsection {
            title: Translation.tr("Punctuation")
            icon: "format_quote"
            Layout.fillWidth: true

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("A sentence in your language, punctuated the way you want")
                text: Config.options.dictation.punctuationHint
                onAccepted: {
                    Config.options.dictation.punctuationHint = text.trim();
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Config.options.dictation.punctuationHint.length > 0
                    ? Translation.tr("Whisper is primed with this before every transcription and punctuates in the same style.")
                    : (DictationService.effectiveHint.length > 0
                        ? Translation.tr("Using a built-in sample for this language: “%1”").arg(DictationService.effectiveHint)
                        : Translation.tr("Auto-detected language gets no sample, since priming for the wrong language costs accuracy. Pick a language above, or write your own sample here."))
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        ConfigSwitch {
            buttonIcon: "g_translate"
            text: Translation.tr("Translate what I say into English")
            checked: Config.options.dictation.translateToEnglish
            onCheckedChanged: {
                Config.options.dictation.translateToEnglish = checked;
            }
            StyledToolTip {
                text: Translation.tr("Speech in any language is transcribed as English text. Leave off to have your own words typed as spoken.")
            }
        }
    }

    // ── Behaviour ────────────────────────────────────────────────────────────
    ContentSection {
        visible: page.installed
        icon: "settings_voice"
        title: Translation.tr("While dictating")

        ContentSubsection {
            title: Translation.tr("Where the text goes")
            icon: "keyboard"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.dictation.outputMode
                onSelected: newValue => {
                    Config.options.dictation.outputMode = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Paste it"),
                        icon: "content_paste",
                        value: "paste"
                    },
                    {
                        displayName: Translation.tr("Type it"),
                        icon: "keyboard",
                        value: "type"
                    },
                    {
                        displayName: Translation.tr("Copy it"),
                        icon: "content_copy",
                        value: "clipboard"
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (Config.options.dictation.outputMode === "clipboard")
                        return Translation.tr("The text lands on the clipboard and nothing is typed — paste it yourself.");
                    if (Config.options.dictation.outputMode === "paste")
                        return Translation.tr("Pasted in one piece with Ctrl+V. Your clipboard is put back afterwards. Apps that paste with something other than Ctrl+V — most terminals use Ctrl+Shift+V — will not receive it; use Type it there.");
                    return Translation.tr("Typed one key at a time into the focused window. Works anywhere a keyboard does, including terminals.");
                }
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            // The failure this warns about is quiet and easy to blame on the
            // speech model: words come back a letter short and it reads like a
            // bad transcription rather than a lost keystroke.
            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: Config.options.dictation.outputMode === "type"
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "warning"
                title: Translation.tr("Typing drops characters in some apps")
                text: Translation.tr("Keystrokes are synthesised one per character, faster than many apps accept them, and the ones that get lost make words arrive incomplete — “monde” typed as “mond”. It reads like a bad transcription but it is not. Raise the delay below if you see it, or switch to Paste it.")
            }
        }

        ConfigSpinBox {
            icon: "keyboard_alt"
            text: Translation.tr("Delay between typed characters (ms)")
            value: Config.options.dictation.typeDelayMs
            from: 0
            to: 50
            stepSize: 1
            enabled: Config.options.dictation.outputMode !== "clipboard"
            onValueChanged: {
                Config.options.dictation.typeDelayMs = value;
            }
            StyledToolTip {
                text: Translation.tr("Voxtype types with no gap by default, and many apps drop characters at that rate — words come out one letter short. Raise this if that happens; \"Paste it\" above avoids the problem entirely.")
            }
        }

        ConfigSwitch {
            buttonIcon: "pause"
            text: Translation.tr("Pause music while I speak")
            checked: Config.options.dictation.pauseMedia
            onCheckedChanged: {
                Config.options.dictation.pauseMedia = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications_active"
            text: Translation.tr("Play a sound when recording starts and stops")
            checked: Config.options.dictation.soundFeedback
            onCheckedChanged: {
                Config.options.dictation.soundFeedback = checked;
            }
        }

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Stop listening after (seconds)")
            value: Config.options.dictation.maxDurationSecs
            from: 10
            to: 600
            stepSize: 10
            onValueChanged: {
                Config.options.dictation.maxDurationSecs = value;
            }
        }
    }

    // ── Where it shows ───────────────────────────────────────────────────────
    ContentSection {
        visible: page.installed
        icon: "visibility"
        title: Translation.tr("Showing it")

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show the transcribed text in a notification")
            checked: Config.options.dictation.notifyOnTranscription
            onCheckedChanged: {
                Config.options.dictation.notifyOnTranscription = checked;
            }
            StyledToolTip {
                text: Translation.tr("The text goes into another window, so this is the one place it can be read back — useful when it lands somewhere unexpected, or when the window scrolled away.")
            }
        }

        ConfigSwitch {
            buttonIcon: "space_bar"
            text: Translation.tr("Microphone in the bar while dictating")
            checked: Config.options.dictation.showIndicator
            onCheckedChanged: {
                Config.options.dictation.showIndicator = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Keep it there while idle, as a button")
            checked: Config.options.dictation.alwaysShowIndicator
            enabled: Config.options.dictation.showIndicator
            onCheckedChanged: {
                Config.options.dictation.alwaysShowIndicator = checked;
            }
            StyledToolTip {
                text: Translation.tr("Click the microphone to start dictating, and again to finish — the same thing the keybind does.")
            }
        }

        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr("Waveform in the dynamic island")
            checked: Config.options.dictation.showInIsland
            onCheckedChanged: {
                Config.options.dictation.showInIsland = checked;
            }
        }
    }
}
