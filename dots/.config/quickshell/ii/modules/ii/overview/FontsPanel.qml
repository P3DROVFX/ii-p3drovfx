pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Installed font families, each row drawn in its own face.
 *
 * `fc-list` runs once per panel open (about 30 ms for a thousand faces) and is
 * collapsed into one entry per family; typing only filters that array.
 */
Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property string noticeText: ""
    property var families: []
    property bool loading: true

    readonly property var rows: root.filteredFamilies()
    readonly property var selectedFamily: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length
        ? root.rows[root.selectedIndex]
        : null
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (root.loading ? Translation.tr("Reading installed fonts…") : Translation.tr("%1 font families").arg(String(root.rows.length)))

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function parseFonts(text) {
        const byFamily = new Map();
        const lines = String(text ?? "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const fields = lines[i].split("\t");
            if (fields.length < 3)
                continue;
            // fontconfig escapes its own separators inside names.
            const family = fields[0].replace(/\\(.)/g, "$1").trim();
            if (family.length === 0)
                continue;
            const key = family.toLocaleLowerCase();
            let entry = byFamily.get(key);
            if (!entry) {
                entry = { family: family, styles: [], file: fields[2] };
                byFamily.set(key, entry);
            }
            const style = fields[1].replace(/\\(.)/g, "$1").trim();
            if (style.length > 0 && entry.styles.indexOf(style) === -1)
                entry.styles.push(style);
            // The regular face is the most representative file to point at.
            if (/^(regular|book|normal|roman)$/i.test(style))
                entry.file = fields[2];
        }
        return Array.from(byFamily.values()).sort((a, b) => a.family.localeCompare(b.family));
    }

    function filteredFamilies() {
        const tokens = root.searchQuery.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
        if (tokens.length === 0)
            return root.families;
        return root.families.filter(entry => {
            const haystack = (entry.family + " " + entry.styles.join(" ")).toLocaleLowerCase();
            return tokens.every(token => haystack.includes(token));
        });
    }

    function clampSelection() {
        root.selectedIndex = root.rows.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }

    function navigateUp(): bool {
        if (root.selectedIndex <= 0)
            return false;
        root.selectedIndex--;
        fontList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateDown(): bool {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length - 1)
            return false;
        root.selectedIndex++;
        fontList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function focusInput(): bool { return false; }

    function copySelected(): bool {
        if (!root.selectedFamily)
            return false;
        Quickshell.clipboardText = root.selectedFamily.family;
        root.showNotice(Translation.tr("Copied “%1”").arg(root.selectedFamily.family));
        return true;
    }

    function activateSelected(): bool { return root.copySelected(); }

    function secondaryActivateSelected(): bool {
        const file = String(root.selectedFamily?.file ?? "");
        if (file.length === 0)
            return false;
        Quickshell.execDetached(["xdg-open", file.slice(0, file.lastIndexOf("/")) || "/"]);
        root.showNotice(Translation.tr("Opening the font's folder"));
        return true;
    }

    function saveSelected(): bool {
        const file = String(root.selectedFamily?.file ?? "");
        if (file.length === 0)
            return false;
        Quickshell.clipboardText = file;
        root.showNotice(Translation.tr("Font file path copied"));
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    // Deferred: `rows` is first evaluated while `selectedFamily` is, and writing
    // `selectedIndex` from inside that evaluation is a binding loop.
    onRowsChanged: Qt.callLater(root.clampSelection)
    onSearchQueryChanged: root.selectedIndex = 0

    Process {
        id: fontListProc
        running: true
        command: ["fc-list", "--format", "%{family[0]}\t%{style[0]}\t%{file}\n"]
        stdout: StdioCollector {
            id: fontListOutput
            onStreamFinished: {
                root.families = root.parseFonts(fontListOutput.text);
                root.loading = false;
            }
        }
        onExited: root.loading = false
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Fonts")
        icon: "text_fields"
        accent: true
        showStatus: true
        statusText: root.statusText
        primaryHint: ({ label: Translation.tr("Copy name"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Open folder"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Copy file path"), actionId: "save", keys: ["Ctrl", "S"] }
        ]

        RowLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            ListView {
                id: fontList
                Layout.preferredWidth: parent.width * 0.42
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.sizes.elevationMargin / 2
                model: root.rows

                delegate: RippleButton {
                    id: fontRow
                    required property int index
                    required property var modelData
                    readonly property bool selected: root.selectedIndex === index
                    width: fontList.width
                    implicitHeight: fontRowContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                    buttonRadius: Appearance.rounding.normal
                    colBackground: fontRow.selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: fontRow.selected ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: fontRow.selected ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.selectedIndex = index

                    ColumnLayout {
                        id: fontRowContent
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: fontRow.modelData.family
                            elide: Text.ElideRight
                            font.family: fontRow.modelData.family
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: fontRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            // Symbol and icon fonts cannot draw their own name
                            // above; this line always stays in the UI face.
                            text: Translation.tr("%1 · %2 styles").arg(fontRow.modelData.family).arg(String(fontRow.modelData.styles.length))
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: fontRow.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !root.loading && root.rows.length === 0
                    text: Translation.tr("No fonts match")
                    color: Appearance.colors.colSubtext
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin * 1.5
                    visible: root.selectedFamily !== null
                    spacing: Appearance.sizes.elevationMargin

                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedFamily?.family ?? ""
                        font.family: root.selectedFamily?.family ?? Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.huge * 1.6
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnSurface
                    }

                    Repeater {
                        model: [Appearance.font.pixelSize.small, Appearance.font.pixelSize.large, Appearance.font.pixelSize.huge]

                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true
                            text: Config.options.search.modules.fonts.sampleText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: root.selectedFamily?.family ?? Appearance.font.family.main
                            font.pixelSize: modelData
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: (root.selectedFamily?.styles ?? []).join(" · ")
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedFamily?.file ?? ""
                        elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.loading
                    implicitWidth: Appearance.sizes.elevationMargin * 3
                    implicitHeight: implicitWidth
                }
            }
        }
    }
}
