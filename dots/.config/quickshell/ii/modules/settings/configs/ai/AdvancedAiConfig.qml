import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets

/**
 * Advanced AI settings sub-page.
 *
 * Tool permissions, request limits and attachment limits are set once and
 * then left alone, so they moved off the main AI page — where their many
 * rows made the dashboard long and tiring to scroll — into this sub-page,
 * reached from the "Advanced settings" entry button.
 */
ContentPage {
    id: page

    property bool showBackButton: false
    signal goBack()
    // The old page remains a complete view for compatibility. Focused pages
    // below reuse its controls instead of maintaining six drifting copies.
    property string sectionMode: "all" // all | tools | files | requests
    readonly property bool showingTools: sectionMode === "all" || sectionMode === "tools"
    readonly property bool showingFiles: sectionMode === "all" || sectionMode === "files"
    readonly property bool showingRequests: sectionMode === "all" || sectionMode === "requests"

    forceWidth: false

    // Detection only otherwise runs on the first recording attempt or a
    // manual "Check again" — reached without either on a page whose whole
    // point is showing whether whisper.cpp is there yet, which would
    // stick on "Checking…" until the user tried the microphone once.
    Component.onCompleted: {
        if (page.showingFiles)
            Ai.voiceService.ensureDetected();
    }

    property string folderPickerError: ""

    function openFolderPicker(): void {
        page.folderPickerError = "";
        folderPickerProc.running = false;
        folderPickerProc.running = true;
    }

    Process {
        id: folderPickerProc
        command: ["bash", "-c", "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory; elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME\"; else exit 127; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const selectedPath = text.trim();
                if (selectedPath)
                    Ai.filesIntegration.addRoot(selectedPath);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 127)
                page.folderPickerError = Translation.tr("Install zenity or kdialog to choose a folder.");
        }
    }

    /**
     * A readable distro family name, shared by the voice and OCR install
     * guides below — the exact package name differs per guide, but the
     * grouping of distros into families does not.
     */
    function linuxFamilyFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "Fedora / RHEL";
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "Arch Linux";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "Debian / Ubuntu";
        if (distro === "nixos")
            return "NixOS";
        return SystemInfo.distroName && SystemInfo.distroName !== "Unknown"
            ? SystemInfo.distroName
            : "Linux";
    }

    /**
     * Only the package-manager line differs between distros; the rest of
     * the build is identical everywhere whisper.cpp compiles, so this
     * returns just that one line and `voiceDepsInstallCommandFor` below
     * appends the shared build steps to it.
     */
    function voiceDepsPackageLineFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "sudo dnf install -y cmake gcc-c++ git pipewire-utils";
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "sudo pacman -S --needed cmake gcc git pipewire-audio";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "sudo apt update && sudo apt install -y cmake g++ git pipewire-bin";
        if (distro === "nixos")
            return "nix profile install nixpkgs#cmake nixpkgs#gcc nixpkgs#git nixpkgs#pipewire";
        return "# Install with your package manager: cmake, a C++ compiler, git, and\n" +
            "# PipeWire's pw-record (often a separate \"utils\"/\"tools\"/\"bin\" package)";
    }

    function voiceDepsInstallCommandFor(value: string): string {
        return [
            page.voiceDepsPackageLineFor(value),
            "git clone --depth 1 https://github.com/ggerganov/whisper.cpp ~/.local/share/whisper.cpp",
            "cmake -B ~/.local/share/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release",
            "cmake --build ~/.local/share/whisper.cpp/build -j$(nproc)",
            "mkdir -p ~/.local/bin",
            "ln -sf ~/.local/share/whisper.cpp/build/bin/whisper-cli ~/.local/bin/whisper-cli",
            "bash ~/.local/share/whisper.cpp/models/download-ggml-model.sh base"
        ].join("\n");
    }

    // English and Portuguese language data named explicitly: tesseract's
    // OCR tool defaults to "eng" and the model may ask for "por", and on
    // Fedora/Arch/Debian neither ships with the engine package by default.
    function tesseractInstallCommandFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "sudo dnf install -y tesseract tesseract-langpack-eng tesseract-langpack-por";
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "sudo pacman -S --needed tesseract tesseract-data-eng tesseract-data-por";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "sudo apt update && sudo apt install -y tesseract-ocr tesseract-ocr-eng tesseract-ocr-por";
        if (distro === "nixos")
            return "nix profile install nixpkgs#tesseract";
        return "# Install with your package manager: tesseract (the OCR engine) plus\n" +
            "# its English and Portuguese language data";
    }

    readonly property string linuxFamily: page.linuxFamilyFor(SystemInfo.distroId)
    readonly property string voiceDepsInstallCommand: page.voiceDepsInstallCommandFor(SystemInfo.distroId)
    readonly property string tesseractInstallCommand: page.tesseractInstallCommandFor(SystemInfo.distroId)

    RowLayout {
        visible: page.showBackButton
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
            onClicked: page.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: page.sectionMode === "tools" ? Translation.tr("Tools & Permissions")
                : page.sectionMode === "files" ? Translation.tr("Files, Vision & Voice")
                : page.sectionMode === "requests" ? Translation.tr("Request Limits")
                : Translation.tr("Advanced AI Settings")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        visible: page.showingTools
        icon: "service_toolbox"
        title: Translation.tr("Tools")

        ConfigSelectionArray {
            Layout.fillWidth: true
            currentValue: Config.options.ai.tools.mode
            onSelected: newValue => {
                Config.options.ai.tools.mode = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Tools"),
                    icon: "build",
                    value: "functions"
                },
                {
                    displayName: Translation.tr("Web search"),
                    icon: "travel_explore",
                    value: "search"
                },
                {
                    displayName: Translation.tr("None"),
                    icon: "block",
                    value: "none"
                }
            ]
        }

        AiToolPermissionList {
            definitions: Array.from(Ai.toolbox.definitions)
        }

        ConfigSwitch {
            buttonIcon: "rate_review"
            text: Translation.tr("Show settings changes before applying them")
            checked: Config.options.ai.tools.reviewConfigChanges
            onCheckedChanged: {
                Config.options.ai.tools.reviewConfigChanges = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "forum"
            text: Translation.tr("Keep tool permissions within each conversation")
            checked: Config.options.ai.tools.scopePerConversation
            onCheckedChanged: {
                Config.options.ai.tools.scopePerConversation = checked;
            }
            StyledToolTip {
                text: Translation.tr("When enabled, Allow and Never choices apply only to the chat that is open now. New chats ask again.")
            }
        }

        TipBox {
            Layout.fillWidth: true
            visible: Config.options.ai.tools.scopePerConversation
            text: Translation.tr("This conversation has its own tool decisions. They are saved with it and do not change the global defaults.")
        }

        ConfigSwitch {
            buttonIcon: "home_storage"
            text: Translation.tr("Let local models use tools")
            checked: Config.options.ai.tools.localModels
            onCheckedChanged: {
                Config.options.ai.tools.localModels = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Allow shell commands under the Local-only policy")
            checked: Config.options.ai.tools.allowShellInLocalPolicy
            onCheckedChanged: {
                Config.options.ai.tools.allowShellInLocalPolicy = checked;
            }
            StyledToolTip {
                text: Translation.tr("Off by default: Local-only exists to shrink what the assistant can reach, not only to cut off the network. A shell command runs locally either way.")
            }
        }

        ConfigSpinBox {
            icon: "history"
            text: Translation.tr("Tool calls to remember")
            value: Config.options.ai.tools.logSize
            from: 0
            to: 200
            stepSize: 10
            onValueChanged: {
                Config.options.ai.tools.logSize = value;
            }
        }
    }

    ContentSection {
        visible: page.showingRequests
        icon: "speed"
        title: Translation.tr("Chat toolbar")

        ConfigSwitch {
            buttonIcon: "speed"
            text: Translation.tr("Show tokens per second in the chat toolbar")
            checked: Config.options.ai.showTokensPerSecond
            onCheckedChanged: {
                if (Config.options.ai.showTokensPerSecond !== checked)
                    Config.options.ai.showTokensPerSecond = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shows the generated tokens per second from the latest completed answer instead of accumulated token usage.")
            }
        }

        ConfigSwitch {
            buttonIcon: "payments"
            text: Translation.tr("Show OpenRouter session cost in the chat toolbar")
            checked: Config.options.ai.showOpenRouterSessionCost
            onCheckedChanged: {
                if (Config.options.ai.showOpenRouterSessionCost !== checked)
                    Config.options.ai.showOpenRouterSessionCost = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shows the exact OpenRouter charges reported for this chat instead of a token metric. Free responses show $0.00.")
            }
        }
    }

    ContentSection {
        visible: page.showingRequests
        icon: "tune"
        title: Translation.tr("Requests")

        ConfigSpinBox {
            icon: "notes"
            text: Translation.tr("Longest answer, in tokens (0 = the model's own limit)")
            value: Config.options.ai.maxOutputTokens
            from: 0
            to: 200000
            stepSize: 1024
            onValueChanged: {
                Config.options.ai.maxOutputTokens = value;
            }
        }

        ConfigSpinBox {
            icon: "cloud_sync"
            text: Translation.tr("Seconds to reach the provider")
            value: Config.options.ai.connectTimeout
            from: 5
            to: 120
            stepSize: 5
            onValueChanged: {
                Config.options.ai.connectTimeout = value;
            }
        }

        ConfigSpinBox {
            icon: "hourglass_top"
            text: Translation.tr("Seconds to finish an answer")
            value: Config.options.ai.requestTimeout
            from: 30
            to: 1800
            stepSize: 30
            onValueChanged: {
                Config.options.ai.requestTimeout = value;
            }
        }

        ConfigSpinBox {
            icon: "refresh"
            text: Translation.tr("Retries after a rate limit or a server error")
            value: Config.options.ai.maxRetries
            from: 0
            to: 5
            stepSize: 1
            onValueChanged: {
                Config.options.ai.maxRetries = value;
            }
        }
    }

    ContentSection {
        visible: page.showingFiles
        icon: "attach_file"
        title: Translation.tr("Attachments")

        TipBox {
            Layout.fillWidth: true
            text: Translation.tr("Every attached file is sent again with every following turn of the same chat, so a large one is paid for more than once.")
        }

        ConfigSpinBox {
            icon: "database"
            text: Translation.tr("Biggest file, in MiB")
            value: Config.options.ai.maxAttachmentMib
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.ai.maxAttachmentMib = value;
            }
        }

        ConfigSpinBox {
            icon: "counter_1"
            text: Translation.tr("Files per message")
            value: Config.options.ai.maxAttachments
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.ai.maxAttachments = value;
            }
        }
    }

    ContentSection {
        visible: page.showingFiles
        icon: "folder_shared"
        title: Translation.tr("Files the assistant may search")

        TipBox {
            Layout.fillWidth: true
            text: Translation.tr("Empty by default: the assistant can only search inside folders listed here, never the rest of the filesystem. A file it finds still asks before being read in full.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                mainText: Translation.tr("Add folder")
                materialIcon: "create_new_folder"
                colText: Appearance.colors.colOnPrimaryContainer
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: page.openFolderPicker()
            }

            StyledText {
                Layout.fillWidth: true
                visible: page.folderPickerError.length > 0
                text: page.folderPickerError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
            }
        }

        Item {
            Layout.fillWidth: true
            visible: Ai.filesIntegration.roots.length === 0
            implicitHeight: visible ? 120 : 0

            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "folder_off"
                title: Translation.tr("No folders configured")
                description: Translation.tr("The assistant cannot search any files until you add one.")
                shape: MaterialShape.Shape.Cookie9Sided
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: Ai.filesIntegration.roots

                delegate: Rectangle {
                    id: rootRow
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "folder"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: rootRow.modelData
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideMiddle
                        }

                        RippleButtonWithIcon {
                            mainText: ""
                            materialIcon: "close"
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colText: Appearance.colors.colOnLayer2
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: Ai.filesIntegration.removeRoot(rootRow.index)

                            Accessible.name: Translation.tr("Remove this folder")
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        visible: page.showingFiles
        icon: "text_snippet"
        title: Translation.tr("Vision")

        ConfigSwitch {
            buttonIcon: "document_scanner"
            text: Translation.tr("Read text out of images with local OCR")
            checked: Config.options.ai.vision.ocrEnabled
            onCheckedChanged: {
                Config.options.ai.vision.ocrEnabled = checked;
            }
            StyledToolTip {
                text: Ai.tesseractPresent
                    ? Translation.tr("Uses tesseract, already installed on this machine. Nothing leaves it.")
                    : Translation.tr("tesseract is not installed, so this has no effect either way.")
            }
        }

        HelperCodeBox {
            Layout.fillWidth: true
            Layout.topMargin: 4
            topLeftRadius: Appearance.rounding.large
            topRightRadius: Appearance.rounding.large
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            icon: "terminal"
            title: Translation.tr("Install tesseract · %1").arg(page.linuxFamily)
            text: Translation.tr("Runs entirely on this machine — nothing in an image is ever sent anywhere for OCR. Copy the command for your system, run it in a terminal, then reopen this page; the switch above turns green on its own once tesseract is found.")
            codeSnippet: page.tesseractInstallCommand
            snippetWrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: page.showingFiles
        icon: "mic"
        title: Translation.tr("Voice")

        ConfigSwitch {
            buttonIcon: "keyboard_voice"
            text: Translation.tr("Turn speech into an editable draft")
            checked: Config.options.ai.voice.enabled
            onCheckedChanged: {
                Config.options.ai.voice.enabled = checked;
            }
            StyledToolTip {
                text: Translation.tr("Recording only ever starts when you press the microphone button. It is transcribed, then shown to you to edit — nothing is sent on its own.")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: Ai.voiceService.available ? "check_circle" : "info"
                iconSize: Appearance.font.pixelSize.large
                color: Ai.voiceService.available ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Ai.voiceService.available
                        ? Translation.tr("Ready — recording via pw-record, transcribing with %1.").arg(Ai.voiceService.backendName)
                        : Translation.tr("Not ready yet")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !Ai.voiceService.available
                    text: Ai.voiceService.unavailableReason()
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButtonWithIcon {
                mainText: Translation.tr("Check again")
                materialIcon: "refresh"
                onClicked: Ai.voiceService.redetect()
            }
        }

        HelperCodeBox {
            Layout.fillWidth: true
            Layout.topMargin: 4
            topLeftRadius: Appearance.rounding.large
            topRightRadius: Appearance.rounding.large
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            icon: "terminal"
            title: Translation.tr("Build whisper.cpp · %1").arg(page.linuxFamily)
            text: Translation.tr("Compiles a small local speech-to-text engine, links it as `whisper-cli`, and downloads its base model (about 150 MB, once). Runs entirely on this machine — nothing spoken is ever sent anywhere. Copy the command for your system, run it in a terminal, then press Check again above.")
            codeSnippet: page.voiceDepsInstallCommand
            snippetWrapMode: Text.Wrap
        }
    }
}
