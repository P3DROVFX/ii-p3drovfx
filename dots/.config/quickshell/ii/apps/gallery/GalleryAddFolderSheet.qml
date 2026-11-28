pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Right-hand M3 Expressive side sheet for adding folders to the Gallery library.
 * Slides smoothly from the right, pushing the main page pane.
 */
Rectangle {
    id: root

    required property var store
    signal closeRequested()

    radius: Math.max(8, Appearance.rounding.windowRounding - 12)
    color: Appearance.m3colors.m3surfaceContainerHigh
    clip: true

    property string selectedSuggestion: ""
    property string customPath: ""
    property string validationError: ""

    readonly property var suggestions: [
        { name: "Videos",    path: "~/Videos",          icon: "movie",            shape: MaterialShape.Shape.Flower },
        { name: "Desktop",   path: "~/Desktop",         icon: "desktop_windows",  shape: MaterialShape.Shape.SoftBurst },
        { name: "Documents", path: "~/Documents",       icon: "description",      shape: MaterialShape.Shape.Cookie6Sided },
        { name: "Screenshots", path: "~/Pictures/Screenshots", icon: "screenshot", shape: MaterialShape.Shape.Clover4Leaf }
    ]

    readonly property var availableSuggestions: {
        return suggestions.filter(s => !store.folders.some(f => f.path === s.path || f.name === s.name));
    }

    function reset(): void {
        root.selectedSuggestion = "";
        root.customPath = "";
        root.validationError = "";
        customField.text = "";
    }

    function submit(): void {
        const trimmed = root.customPath.trim();
        if (trimmed.length > 0) {
            if (!/^(~\/|\/)/.test(trimmed)) {
                root.validationError = Translation.tr("Use a full path starting with ~/ or /.");
                return;
            }
            if (store.folders.some(f => f.path === trimmed)) {
                root.validationError = Translation.tr("This folder is already in your library.");
                return;
            }
            store.addFolder("", trimmed);
            root.reset();
            root.closeRequested();
            return;
        }
        if (root.selectedSuggestion.length > 0) {
            const pick = suggestions.find(s => s.name === root.selectedSuggestion);
            if (pick) {
                store.addFolder(pick.name, pick.path);
                root.reset();
                root.closeRequested();
            }
        }
    }

    Process {
        id: folderPickerProc
        command: ["python3", store.scanScriptPath, "pick-folder", "--title", Translation.tr("Choose a folder")]
        stdout: StdioCollector {
            onStreamFinished: {
                const picked = String(this.text ?? "").trim();
                if (picked.length > 0) {
                    const home = String(Directories.home).replace("file://", "").replace(/\/$/, "");
                    const nice = picked.startsWith(home + "/") ? ("~" + picked.slice(home.length)) : picked;
                    root.selectedSuggestion = "";
                    root.customPath = nice;
                    customField.text = nice;
                    root.validationError = "";
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    text: Translation.tr("Add folder")
                    font.pixelSize: 24
                    font.variableAxes: ({ "wght": 600, "wdth": 110, "ROND": 100 })
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Appears in Albums and, if enabled, in the Home timeline.")
                    font.pixelSize: 13
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: hovered ? 13 : 20
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.88)
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                onClicked: root.closeRequested()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 20
                    color: parent.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                }
                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Close")
                }
            }
        }

        // Body
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: sheetCol.implicitHeight
            clip: true

            ColumnLayout {
                id: sheetCol
                width: parent.width
                spacing: 10

                StyledText {
                    text: Translation.tr("SUGGESTIONS")
                    font.pixelSize: 11
                    font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 60 })
                    font.letterSpacing: 0.8
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Repeater {
                    model: root.availableSuggestions

                    delegate: Rectangle {
                        id: sugCard
                        required property var modelData
                        readonly property bool chosen: root.selectedSuggestion === modelData.name

                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: chosen ? Appearance.rounding.large : Appearance.rounding.small
                        color: chosen
                            ? Appearance.colors.colSecondaryContainer
                            : (sugMouse.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.colors.colLayer2)

                        Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12

                            MaterialShape {
                                implicitWidth: 36
                                implicitHeight: 36
                                shape: sugCard.chosen ? MaterialShape.Shape.Sunny : sugCard.modelData.shape
                                color: sugCard.chosen
                                    ? Appearance.m3colors.m3tertiaryContainer
                                    : Appearance.colors.colPrimaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: sugCard.modelData.icon
                                    iconSize: 18
                                    fill: sugCard.chosen ? 1 : 0
                                    color: sugCard.chosen
                                        ? Appearance.m3colors.m3onTertiaryContainer
                                        : Appearance.colors.colOnPrimaryContainer
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText {
                                    text: sugCard.modelData.name
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    color: sugCard.chosen
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    text: sugCard.modelData.path
                                    font.pixelSize: 12
                                    color: sugCard.chosen
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colSubtext
                                    opacity: sugCard.chosen ? 0.8 : 1
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        MouseArea {
                            id: sugMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedSuggestion = sugCard.chosen ? "" : sugCard.modelData.name;
                                if (root.selectedSuggestion.length > 0) {
                                    root.customPath = "";
                                    customField.text = "";
                                    root.validationError = "";
                                }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.availableSuggestions.length === 0
                    Layout.fillWidth: true
                    text: Translation.tr("All suggested folders are already in your library.")
                    font.pixelSize: 13
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                // Custom path input
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Or enter a folder path")
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: Appearance.rounding.small
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            border.width: customField.activeFocus ? 2 : 0
                            border.color: Appearance.colors.colPrimary

                            HoverHandler {
                                cursorShape: Qt.IBeamCursor
                            }

                            TextInput {
                                id: customField
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Appearance.font.family.main
                                font.pixelSize: 14
                                color: Appearance.colors.colOnSurface
                                clip: true
                                onTextChanged: {
                                    root.customPath = text;
                                    if (text.trim().length > 0)
                                        root.selectedSuggestion = "";
                                    root.validationError = "";
                                }
                                Keys.onReturnPressed: root.submit()
                                Keys.onEnterPressed: root.submit()

                                StyledText {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: customField.text.length === 0
                                    text: "~/Pictures/Travel"
                                    font.pixelSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        RippleButton {
                            implicitWidth: 46
                            implicitHeight: 46
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: {
                                if (!folderPickerProc.running)
                                    folderPickerProc.running = true;
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "folder_open"
                                iconSize: 20
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledToolTip {
                                text: Translation.tr("Browse folder")
                            }
                        }
                    }

                    Rectangle {
                        visible: root.validationError.length > 0
                        Layout.fillWidth: true
                        implicitHeight: errTxt.implicitHeight + 12
                        radius: 8
                        color: Appearance.m3colors.m3errorContainer

                        StyledText {
                            id: errTxt
                            anchors.fill: parent
                            anchors.margins: 6
                            text: root.validationError
                            font.pixelSize: 12
                            color: Appearance.m3colors.m3onErrorContainer
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        // Footer buttons (perfectly centered text + clean M3 hover colors)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 46
                leftPadding: 0
                rightPadding: 0
                buttonRadius: hovered && enabled ? 16 : 23
                enabled: root.selectedSuggestion.length > 0 || root.customPath.trim().length > 0
                opacity: enabled ? 1.0 : 0.42
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                onClicked: root.submit()
                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Add")
                    font.family: Appearance.font.family.main
                    font.pixelSize: 15
                    font.variableAxes: ({ "wght": 660, "wdth": 102, "ROND": 100 })
                    color: Appearance.colors.colOnPrimary
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                leftPadding: 0
                rightPadding: 0
                buttonRadius: hovered ? 16 : 22
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.86)
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                onClicked: root.closeRequested()
                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Cancel")
                    font.family: Appearance.font.family.main
                    font.pixelSize: 15
                    font.variableAxes: ({ "wght": 580, "wdth": 100, "ROND": 100 })
                    color: Appearance.colors.colOnSurface
                }
            }
        }
    }
}
