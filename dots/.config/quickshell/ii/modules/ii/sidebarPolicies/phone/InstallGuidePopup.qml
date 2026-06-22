pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * InstallGuidePopup — a floating overlay that shows which dependencies are
 * missing for a Phone feature (scrcpy mirror, DroidCam webcam, or mic) and
 * provides copyable install commands per distro.
 *
 * The popup is declared as a child of the Phone panel and toggled via
 * `visible`. It catches clicks outside its card to close itself.
 *
 * Each entry in `missingDeps` is:
 *   { key, name, description, present, installCommands: {arch, fedora, debian} }
 *
 * `detectedDistro` selects which command line to show by default. The user
 * can switch between distros via a small pill row.
 */
Item {
    id: root

    /** Array of dependency descriptors (see services missingDeps). */
    property var missingDeps: []
    /** Auto-detected distro: "arch" | "fedora" | "debian" | "unknown". */
    property string detectedDistro: "unknown"
    /** Title for the popup header. */
    property string headerTitle: Translation.tr("Missing Dependencies")

    /** Emitted when the user clicks "Re-check" — the parent should call
     *  refresh() on the relevant services. */
    signal refreshRequested()

    /** Currently selected distro tab (user can override auto-detection). */
    property string _selectedDistro: root.detectedDistro.length > 0 && root.detectedDistro !== "unknown"
        ? root.detectedDistro : "arch"

    onVisibleChanged: {
        if (visible) root._selectedDistro = root.detectedDistro.length > 0 && root.detectedDistro !== "unknown"
            ? root.detectedDistro : "arch"
    }

    /** Copies text to the Wayland clipboard via wl-copy. */
    function _copyToClipboard(text) {
        if (text.length === 0) return
        Quickshell.execDetached(["bash", "-c",
            "wl-copy " + root._shellQuote(text)])
    }

    function _shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    /** Extracts the first command from a (possibly multi-line) install string,
     *  stripping comments. Used for the "Copy first command" quick action. */
    function _firstCommand(text) {
        const lines = text.split("\n")
        for (const line of lines) {
            const trimmed = line.trim()
            if (trimmed.length === 0 || trimmed.startsWith("#")) continue
            return trimmed
        }
        return text.trim()
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "transparent"
        visible: root.visible

        // Click-outside catcher
        MouseArea {
            anchors.fill: parent
            z: 0
            onClicked: root.visible = false
        }

        Rectangle {
            id: popupCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 16, 420)
            height: Math.min(parent.height - 16, popupColumn.implicitHeight + 24)
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.large
            z: 1

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                id: popupColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ─── Header ───────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialSymbol {
                        text: "build"
                        iconSize: 22
                        color: Appearance.colors.colPrimary
                        fill: 1.0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.headerTitle
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }

                    RippleButton {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer3
                        }
                        onClicked: root.visible = false
                    }
                }

                // ─── Distro selector pills ────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { key: "arch", label: "Arch" },
                            { key: "fedora", label: "Fedora" },
                            { key: "debian", label: "Debian" }
                        ]
                        delegate: RippleButton {
                            required property var modelData
                            Layout.preferredHeight: 30
                            buttonRadius: Appearance.rounding.full
                            colBackground: root._selectedDistro === modelData.key
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer3
                            colBackgroundHover: root._selectedDistro === modelData.key
                                ? Appearance.colors.colPrimaryContainerHover
                                : Appearance.colors.colLayer3Hover
                            scale: down ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: root._selectedDistro === modelData.key ? Font.DemiBold : Font.Normal
                                color: root._selectedDistro === modelData.key
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer3
                            }
                            leftPadding: 14
                            rightPadding: 14
                            onClicked: root._selectedDistro = modelData.key
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.detectedDistro !== "unknown"
                            ? Translation.tr("Detected: %1").arg(root.detectedDistro)
                            : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.7
                        visible: text.length > 0
                    }
                }

                // ─── Dependency list ──────────────────────────
                Repeater {
                    model: root.missingDeps

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: depColumn.implicitHeight + 16
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1

                        ColumnLayout {
                            id: depColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 6

                            // Dep name + description
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    text: "error"
                                    iconSize: 16
                                    color: Appearance.colors.colError
                                    fill: 1.0
                                    Layout.alignment: Qt.AlignTop
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        wrapMode: Text.WordWrap
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.description
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer1
                                        opacity: 0.7
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            // Install command box + copy button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(34, cmdRow.implicitHeight + 10)
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer3
                                visible: {
                                    const cmds = modelData.installCommands
                                    return cmds && cmds[root._selectedDistro]
                                }

                                RowLayout {
                                    id: cmdRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    anchors.topMargin: 5
                                    anchors.bottomMargin: 5
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const cmds = modelData.installCommands
                                            if (!cmds) return ""
                                            const cmd = cmds[root._selectedDistro]
                                            return cmd || ""
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.monospace || font.family
                                        color: Appearance.colors.colOnLayer3
                                        wrapMode: Text.WrapAnywhere
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                    }

                                    RippleButton {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colLayer4
                                        colBackgroundHover: Appearance.colors.colLayer4Hover
                                        scale: down ? 0.92 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: copyLabel.showCheck ? "check" : "content_copy"
                                            iconSize: 15
                                            color: copyLabel.showCheck
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOnLayer4
                                            fill: 1.0
                                        }
                                        property bool _copied: false

                                        onClicked: {
                                            const cmds = modelData.installCommands
                                            if (!cmds) return
                                            const cmd = cmds[root._selectedDistro]
                                            if (cmd) {
                                                root._copyToClipboard(cmd)
                                                copyLabel.showCheck = true
                                                copyLabelTimer.restart()
                                            }
                                        }

                                        Timer {
                                            id: copyLabelTimer
                                            interval: 1500
                                            repeat: false
                                            onTriggered: copyLabel.showCheck = false
                                        }

                                        StyledText {
                                            id: copyLabel
                                            property bool showCheck: false
                                            visible: false
                                        }

                                        StyledToolTip {
                                            text: Translation.tr("Copy install command")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ─── Footer hint + refresh button ─────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("After installing, click re-check to verify.")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                    }

                    RippleButton {
                        Layout.preferredHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        scale: down ? 0.96 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                        contentItem: RowLayout {
                            spacing: 4
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "refresh"
                                iconSize: 14
                                color: Appearance.colors.colOnPrimaryContainer
                                fill: 1.0
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: Translation.tr("Re-check")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                        leftPadding: 12
                        rightPadding: 12
                        onClicked: root.refreshRequested()
                    }
                }
            }
        }
    }
}
