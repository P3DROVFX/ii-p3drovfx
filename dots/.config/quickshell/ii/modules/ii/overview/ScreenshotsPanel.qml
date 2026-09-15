pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property string noticeText: ""

    readonly property real listSpacing: Appearance.sizes.elevationMargin / 2
    readonly property var entries: root.filteredEntries()
    readonly property var selectedEntry: root.selectedIndex >= 0 && root.selectedIndex < root.entries.length
        ? root.entries[root.selectedIndex]
        : ""
    readonly property bool shouldBlurPreview: Config.options.search.modules.screenshots.blurPreviews
        || Config.options.workSafety.enable.clipboard
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (root.selectedEntry.length > 0 ? root.imageMetadata(root.selectedEntry) : Translation.tr("No screenshot selected"))
    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function filteredEntries() {
        const query = root.searchQuery.trim().toLocaleLowerCase();
        const rows = Array.from(Cliphist.imageEntries ?? [])
            .slice(0, Config.options.search.modules.screenshots.maxItems);
        if (query.length === 0)
            return rows;
        return rows.filter(entry => root.imageSearchText(entry).toLocaleLowerCase().includes(query));
    }

    function imageId(entry) {
        return String(entry ?? "").match(/^(\d+)\t/)?.[1] ?? "";
    }

    function imageTitle(entry) {
        const id = root.imageId(entry);
        return id.length > 0
            ? Translation.tr("Screenshot #%1").arg(id)
            : Translation.tr("Screenshot");
    }

    function imageMetadata(entry) {
        const size = String(entry ?? "").match(/(\d+)x(\d+)/);
        return size
            ? `${size[1]} × ${size[2]}`
            : Translation.tr("Image from clipboard");
    }

    function imageSearchText(entry) {
        return `${root.imageTitle(entry)} ${root.imageMetadata(entry)}`;
    }

    function clampSelection() {
        if (root.entries.length === 0) {
            root.selectedIndex = -1;
            return;
        }
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.entries.length - 1));
    }

    function navigateUp(): bool {
        if (root.selectedIndex <= 0)
            return false;
        root.selectedIndex--;
        screenshotList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateDown(): bool {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.entries.length - 1)
            return false;
        root.selectedIndex++;
        screenshotList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function focusInput(): bool {
        return false;
    }

    function activateSelected(): bool {
        if (root.selectedEntry.length === 0)
            return false;
        Cliphist.copy(root.selectedEntry);
        GlobalStates.overviewOpen = false;
        return true;
    }

    function decodeCommand(targetPath) {
        const entry = StringUtils.shellSingleQuoteEscape(root.selectedEntry);
        const target = StringUtils.shellSingleQuoteEscape(targetPath);
        return `printf '%s' '${entry}' | ${Cliphist.cliphistBinary} decode > '${target}'`;
    }

    function savedPath() {
        return `${Directories.pictures}/Screenshots/screenshot-${Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss")}.png`;
    }

    function saveSelected(): bool {
        if (root.selectedEntry.length === 0)
            return false;
        const path = root.savedPath();
        const directory = StringUtils.shellSingleQuoteEscape(`${Directories.pictures}/Screenshots`);
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${directory}' && ${root.decodeCommand(path)}`]);
        root.showNotice(Translation.tr("Saving to %1").arg(path));
        return true;
    }

    function editSelected(): bool {
        if (root.selectedEntry.length === 0)
            return false;
        const path = root.savedPath();
        const directory = StringUtils.shellSingleQuoteEscape(`${Directories.pictures}/Screenshots`);
        const escapedPath = StringUtils.shellSingleQuoteEscape(path);
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${directory}' && ${root.decodeCommand(path)} && exec swappy -f '${escapedPath}'`]);
        root.showNotice(Translation.tr("Opening screenshot editor…"));
        return true;
    }

    function ocrSelected(): bool {
        if (root.selectedEntry.length === 0)
            return false;
        const path = `${Directories.screenshotTemp}/search-ocr-${Date.now()}.png`;
        const escapedPath = StringUtils.shellSingleQuoteEscape(path);
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(Directories.screenshotTemp)}' && ${root.decodeCommand(path)} && langs=$(tesseract --list-langs 2>/dev/null | sed 1d | paste -sd+ -) && tesseract '${escapedPath}' stdout -l "${'${langs:-eng}'}" 2>/dev/null | wl-copy; rm -f '${escapedPath}'`]);
        root.showNotice(Translation.tr("Reading text and copying it…"));
        return true;
    }

    function deleteSelected(): bool {
        if (root.selectedEntry.length === 0)
            return false;
        Cliphist.deleteEntry(root.selectedEntry);
        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
        root.showNotice(Translation.tr("Screenshot removed from history"));
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    onEntriesChanged: root.clampSelection()

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Screenshots")
        icon: "screenshot"
        accent: true
        showStatus: true
        statusText: root.statusText
        primaryHint: ({ label: Translation.tr("Copy"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Save"), actionId: "save", keys: ["Ctrl", "S"] },
            { label: Translation.tr("Edit"), actionId: "edit", keys: ["Ctrl", "E"] },
            { label: Translation.tr("OCR"), actionId: "ocr", keys: ["Ctrl", "O"] },
            { label: Translation.tr("Delete"), actionId: "delete", keys: ["⇧", "Del"] }
        ]

        RowLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            ListView {
                id: screenshotList
                Layout.preferredWidth: Math.max(parent.width * Config.options.search.clipboard.listColumnRatio
                    - Appearance.sizes.elevationMargin * 4, Appearance.sizes.elevationMargin * 16)
                Layout.fillHeight: true
                clip: true
                spacing: root.listSpacing
                topMargin: 0
                bottomMargin: 0
                model: root.entries

                delegate: RippleButton {
                    required property int index
                    required property var modelData
                    width: screenshotList.width
                    implicitHeight: rowContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                    buttonRadius: Appearance.rounding.normal
                    colBackground: root.selectedIndex === index
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: root.selectedIndex === index
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: root.selectedIndex === index
                        ? Appearance.colors.colPrimaryContainerActive
                        : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.selectedIndex = index

                    RowLayout {
                        id: rowContent
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin
                        spacing: Appearance.sizes.elevationMargin

                        MaterialSymbol {
                            text: "image"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.selectedIndex === index
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnSurface
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.sizes.elevationMargin / 4

                            StyledText {
                                Layout.fillWidth: true
                                text: root.imageTitle(modelData)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.selectedIndex === index
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.imageMetadata(modelData)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.selectedIndex === index
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                            }
                        }

                        ConfiguredKeyHint {
                            visible: root.selectedIndex === index && Config.options.search.appearance.showKeyHints
                            actionId: "activate"
                            fallbackKeys: ["↵"]
                            surface: Appearance.colors.colPrimaryContainer
                            onSurface: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.entries.length === 0
                    text: Translation.tr("No screenshots in clipboard history")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.fill: parent
                    visible: root.selectedEntry.length > 0
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerHigh
                    clip: true

                    CliphistImage {
                        id: previewImage
                        anchors.centerIn: parent
                        entry: root.selectedEntry
                        maxWidth: parent.width - Appearance.sizes.elevationMargin * 2
                        maxHeight: parent.height - Appearance.sizes.elevationMargin * 2
                        blur: root.shouldBlurPreview
                        blurText: Translation.tr("Screenshot hidden")
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: previewImage.loading
                        spacing: Appearance.sizes.elevationMargin / 2

                        MaterialLoadingIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: Appearance.sizes.elevationMargin * 3
                            implicitHeight: implicitWidth
                        }
                        StyledText {
                            text: Translation.tr("Preparing preview…")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: previewImage.failed && !previewImage.loading
                        spacing: Appearance.sizes.elevationMargin / 2

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "broken_image"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colError
                        }
                        StyledText {
                            text: Translation.tr("Preview could not be decoded")
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        RippleButton {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: retryLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                            implicitHeight: Appearance.sizes.elevationMargin * 3
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colErrorContainer
                            colBackgroundHover: Appearance.colors.colErrorContainerHover
                            colRipple: Appearance.colors.colErrorContainerActive
                            onClicked: previewImage.requestDecode()
                            StyledText {
                                id: retryLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Try again")
                                color: Appearance.colors.colOnErrorContainer
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.selectedEntry.length === 0
                    spacing: Appearance.sizes.elevationMargin / 2
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.entries.length === 0 ? "screenshot_monitor" : "touch_app"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: root.entries.length === 0
                            ? Translation.tr("No images in clipboard history")
                            : Translation.tr("Select a screenshot to preview")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
