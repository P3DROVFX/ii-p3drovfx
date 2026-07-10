import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell

/**
 * FloatingNotchLocalSend — rewritten v2
 *
 * States (mutually exclusive, priority order):
 *   DRAG        – isDragOverNotch: two-column drop target
 *   INCOMING    – currentTransfer != null: accept/decline prompt
 *   READY_LS    – serviceChoice=1 && isExpanded: file list + device picker
 *   READY_KDE   – serviceChoice=2 && isExpanded: queued files + send button
 *   CONTRACTED  – single-line pill (catch-all)
 */
Item {
    id: root
    anchors.fill: parent

    // ── Injected by panel ────────────────────────────────────────────────
    property bool isExpanded: false
    property bool isDragOverNotch: false
    property int  panelWidgetsCount: 1

    // serviceChoice: 0=none, 1=LocalSend, 2=KDE Connect
    // Set by DynamicIslandPanel's DropArea on drop
    property int serviceChoice: 0
    property var queueFiles: []     // clean paths for KDE ready state

    // Left/right column hover during drag (set by panel onPositionChanged)
    property bool leftHover:  false
    property bool rightHover: false

    // ── KDE helpers ──────────────────────────────────────────────────────
    readonly property bool kdeEnabled:
        !Config.options.bar.floatingNotch.disableKdeConnectInLocalSend

    readonly property bool kdeAvailable: kdeEnabled
        && typeof KdeConnectService !== "undefined"
        && KdeConnectService.available
        && KdeConnectService.activeReachable

    readonly property var kdeDevice: kdeAvailable
        ? KdeConnectService.activeDevice
        : null

    // ── KDE send state ───────────────────────────────────────────────────
    property bool kdeSending: false
    property bool kdeSent:    false
    property int  kdeFilesSent: 0

    Timer {
        id: kdeSentTimer
        interval: 4000
        onTriggered: {
            root.kdeSent     = false
            root.kdeSending  = false
            root.kdeFilesSent = 0
            root.queueFiles  = []
            root.serviceChoice = 0
        }
    }

    // ── LocalSend progress ───────────────────────────────────────────────
    property real lsProgress: 0.0

    NumberAnimation {
        id: lsProgressAnim
        target: root
        property: "lsProgress"
        from: 0.0; to: 0.92
        duration: 3200
        easing.type: Easing.OutCubic
        running: LocalSend.sending
    }

    Timer {
        id: lsSentTimer
        interval: 2000
        onTriggered: {
            root.lsProgress    = 0.0
            root.serviceChoice = 0
            root.queueFiles    = []
        }
    }

    Connections {
        target: LocalSend
        function onSendCompleted() {
            root.lsProgress = 1.0
            lsSentTimer.restart()
        }
        function onSendFailed(message) {
            root.lsProgress = 0.0
        }
    }

    // ── State flags ──────────────────────────────────────────────────────
    readonly property bool isIncoming:  LocalSend.currentTransfer !== null
    readonly property bool isSendingLS: LocalSend.sending && root.serviceChoice === 1
    readonly property bool isReadyLS:   root.serviceChoice === 1 && root.isExpanded
        && !root.isDragOverNotch && !root.isIncoming
    readonly property bool isReadyKDE:  root.serviceChoice === 2 && root.isExpanded
        && !root.isDragOverNotch && !root.isIncoming

    // ── File icon helper ─────────────────────────────────────────────────
    function fileIcon(name) {
        const ext = (name || "").split(".").pop().toLowerCase()
        if (["jpg","jpeg","png","gif","webp","svg","heic","avif"].includes(ext)) return "image"
        if (["mp4","mkv","avi","mov","webm"].includes(ext)) return "movie"
        if (["mp3","flac","ogg","wav","aac","opus"].includes(ext)) return "audio_file"
        if (["pdf"].includes(ext)) return "picture_as_pdf"
        if (["zip","tar","gz","xz","7z","rar"].includes(ext)) return "folder_zip"
        if (["txt","md","rst"].includes(ext)) return "article"
        if (["doc","docx","odt"].includes(ext)) return "description"
        return "draft"
    }

    // ════════════════════════════════════════════════════════════════════
    //  CONTRACTED  –  single pill line
    // ════════════════════════════════════════════════════════════════════
    RowLayout {
        id: contractedView
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8
        visible: !root.isDragOverNotch && !root.isExpanded

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: {
                if (root.isIncoming)              return "cloud_download"
                if (LocalSend.sending)            return "sync"
                if (root.serviceChoice === 1)     return "near_me"
                if (root.serviceChoice === 2)     return "smartphone"
                return "share"
            }
            iconSize: 16
            color: root.serviceChoice === 2
                ? Appearance.colors.colSecondary
                : Appearance.colors.colPrimary

            RotationAnimation on rotation {
                running: LocalSend.sending && contractedView.visible
                loops: Animation.Infinite
                from: 0; to: 360; duration: 2000
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            color: Appearance.colors.colOnSurface
            elide: Text.ElideRight
            maximumLineCount: 1
            text: {
                if (root.isIncoming)
                    return Translation.tr("Incoming from %1").arg(LocalSend.currentTransfer.sender)
                if (LocalSend.sending)
                    return Translation.tr("Sending… %1%").arg(Math.round(root.lsProgress * 100))
                if (root.serviceChoice === 2) {
                    const n = root.kdeDevice ? root.kdeDevice.name : "KDE Connect"
                    return root.queueFiles.length > 0
                        ? Translation.tr("%1 file(s) → %2").arg(root.queueFiles.length).arg(n)
                        : Translation.tr("KDE Connect ready")
                }
                if (root.serviceChoice === 1) {
                    return LocalSend.droppedFiles.length > 0
                        ? Translation.tr("%1 file(s) staged").arg(LocalSend.droppedFiles.length)
                        : Translation.tr("LocalSend ready")
                }
                return Translation.tr("Drop files to share")
            }
        }

        // Inline clear button on contracted view
        RippleButton {
            visible: root.serviceChoice !== 0 && !LocalSend.sending
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 18; implicitHeight: 18
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            onClicked: {
                LocalSend.clearDroppedFiles()
                root.queueFiles    = []
                root.serviceChoice = 0
            }
            contentItem: MaterialSymbol {
                text: "close"; iconSize: 12
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  DRAG VIEW  –  two columns, no extra outer rectangles
    // ════════════════════════════════════════════════════════════════════
    Item {
        id: dragView
        anchors.fill: parent
        anchors.margins: 6
        visible: root.isDragOverNotch

        opacity: root.isDragOverNotch ? 1.0 : 0.0
        scale:   root.isDragOverNotch ? 1.0 : 0.93
        Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveEnter.duration; easing.type: Appearance.animation.elementMoveEnter.type; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve } }
        Behavior on scale   { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }

        RowLayout {
            anchors.fill: parent
            spacing: 8

            // ── LocalSend column ────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                clip: true
                scale: root.leftHover ? 1.03 : 1.0
                color: root.leftHover
                    ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.22)
                    : Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.10)
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    Item { Layout.fillHeight: true }

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth:  root.leftHover ? 44 : 36
                        Layout.preferredHeight: root.leftHover ? 44 : 36
                        shapeString: "Cookie12Sided"
                        color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, root.leftHover ? 0.32 : 0.18)
                        Behavior on Layout.preferredWidth  { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                        Behavior on color                  { ColorAnimation   { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.leftHover ? "file_upload" : "near_me"
                            iconSize: root.leftHover ? 23 : 18
                            color: Appearance.colors.colPrimary
                            Behavior on iconSize { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "LocalSend"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: root.leftHover ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.leftHover ? Translation.tr("Release to send") : Translation.tr("Drop here")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.leftHover ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Divider
            Rectangle {
                visible: root.kdeEnabled
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: parent.height * 0.5
                Layout.preferredWidth: 1
                color: Qt.rgba(Appearance.colors.colOnSurface.r, Appearance.colors.colOnSurface.g, Appearance.colors.colOnSurface.b, 0.15)
            }

            // ── KDE Connect column ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.kdeEnabled
                radius: Appearance.rounding.normal
                clip: true
                opacity: root.kdeAvailable ? 1.0 : 0.45
                Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                scale: root.rightHover && root.kdeAvailable ? 1.03 : 1.0
                color: {
                    if (!root.kdeAvailable) return Qt.rgba(Appearance.colors.colSubtext.r, Appearance.colors.colSubtext.g, Appearance.colors.colSubtext.b, 0.07)
                    return root.rightHover
                        ? Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, 0.24)
                        : Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, 0.10)
                }
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    Item { Layout.fillHeight: true }

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth:  root.rightHover && root.kdeAvailable ? 44 : 36
                        Layout.preferredHeight: root.rightHover && root.kdeAvailable ? 44 : 36
                        shapeString: "Cookie12Sided"
                        color: {
                            if (!root.kdeAvailable) return Qt.rgba(Appearance.colors.colSubtext.r, Appearance.colors.colSubtext.g, Appearance.colors.colSubtext.b, 0.14)
                            return Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, root.rightHover ? 0.32 : 0.18)
                        }
                        Behavior on Layout.preferredWidth  { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                        Behavior on color                  { ColorAnimation   { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: {
                                if (!root.kdeAvailable) return "link_off"
                                return root.rightHover ? "file_upload" : "smartphone"
                            }
                            iconSize: root.rightHover && root.kdeAvailable ? 23 : 18
                            color: root.kdeAvailable ? Appearance.colors.colSecondary : Appearance.colors.colSubtext
                            Behavior on iconSize { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.kdeDevice ? root.kdeDevice.name : "KDE Connect"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        elide: Text.ElideRight
                        color: {
                            if (!root.kdeAvailable) return Appearance.colors.colSubtext
                            return root.rightHover ? Appearance.colors.colSecondary : Appearance.colors.colOnSurface
                        }
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            if (!root.kdeAvailable) return Translation.tr("Unavailable")
                            return root.rightHover ? Translation.tr("Release to send") : Translation.tr("Drop here")
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: {
                            if (!root.kdeAvailable) return Appearance.colors.colSubtext
                            return root.rightHover ? Appearance.colors.colSecondary : Appearance.colors.colSubtext
                        }
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  EXPANDED CONTENT  –  one child visible at a time
    // ════════════════════════════════════════════════════════════════════
    Item {
        id: expandedView
        anchors.fill: parent
        visible: root.isExpanded && !root.isDragOverNotch

        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveEnter.duration; easing.type: Appearance.animation.elementMoveEnter.type; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve } }

        // ── 1. INCOMING TRANSFER ────────────────────────────────────────
        ColumnLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            spacing: 8
            visible: root.isIncoming

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 30; height: 30; radius: 8
                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.15)
                    MaterialSymbol { anchors.centerIn: parent; text: "cloud_download"; iconSize: 17; color: Appearance.colors.colPrimary }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Incoming Transfer")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: LocalSend.currentTransfer ? LocalSend.currentTransfer.sender : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            // File preview card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: Appearance.rounding.small
                color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.08)
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: {
                            if (!LocalSend.currentTransfer) return "draft"
                            const f = LocalSend.currentTransfer.files
                            return f && f.length > 0 ? root.fileIcon(f[0].name) : "draft"
                        }
                        iconSize: 22
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (!LocalSend.currentTransfer) return ""
                                const f = LocalSend.currentTransfer.files
                                if (!f || f.length === 0) return Translation.tr("No files")
                                return f.length === 1 ? f[0].name : Translation.tr("%1 files").arg(f.length)
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideMiddle
                        }
                        StyledText {
                            text: {
                                if (!LocalSend.currentTransfer) return ""
                                const f = LocalSend.currentTransfer.files
                                return f && f.length === 1 ? LocalSend.formatFileSize(f[0].size) : ""
                            }
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colError
                    onClicked: LocalSend.denyTransfer()
                    contentItem: RowLayout {
                        anchors.centerIn: parent; spacing: 4
                        MaterialSymbol { text: "close"; iconSize: 13; color: "#fff" }
                        StyledText { text: Translation.tr("Decline"); font.pixelSize: Appearance.font.pixelSize.smallest; font.bold: true; color: "#fff" }
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    onClicked: LocalSend.acceptTransfer()
                    contentItem: RowLayout {
                        anchors.centerIn: parent; spacing: 4
                        MaterialSymbol { text: "download"; iconSize: 13; color: "#fff" }
                        StyledText { text: Translation.tr("Accept"); font.pixelSize: Appearance.font.pixelSize.smallest; font.bold: true; color: "#fff" }
                    }
                }
            }
        }

        // ── 2. LOCALSEND READY ──────────────────────────────────────────
        ColumnLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            spacing: 6
            visible: root.isReadyLS

            // Header bar
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("LocalSend")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.bold: true
                    color: Appearance.colors.colOnSurface
                }

                // File count badge
                Rectangle {
                    visible: LocalSend.droppedFiles.length > 0
                    height: 18
                    implicitWidth: lsBadge.implicitWidth + 12
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                    StyledText {
                        id: lsBadge
                        anchors.centerIn: parent
                        text: LocalSend.droppedFiles.length.toString()
                        font.pixelSize: 10; font.bold: true
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }

            // Send progress (only while sending)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                visible: LocalSend.sending

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: Translation.tr("Sending…")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: Math.round(root.lsProgress * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colPrimary
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    valueBarHeight: 4
                    value: root.lsProgress
                    highlightColor: Appearance.colors.colPrimary
                    trackColor: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18)
                }
            }

            // Staged files list (scrollable middle area)
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 80)
                model: LocalSend.droppedFiles
                spacing: 4
                clip: true
                visible: LocalSend.droppedFiles.length > 0 && !LocalSend.sending

                delegate: Rectangle {
                    id: lsFileDel
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 32
                    radius: Appearance.rounding.small
                    color: lsFMouse.containsMouse
                        ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.15)
                        : Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.08)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    MouseArea {
                        id: lsFMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.fileIcon(lsFileDel.modelData.name)
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: lsFileDel.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideMiddle
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 24
                            implicitHeight: 24
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: LocalSend.removeDroppedFile(lsFileDel.index)
                            contentItem: Item {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }

            // Hint when no files yet
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                visible: LocalSend.droppedFiles.length === 0 && !LocalSend.sending

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "add_to_drive"
                        iconSize: 24
                        color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.5)
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Drop files to send")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Bottom buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 6
                visible: !LocalSend.sending

                // Device picker compact
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: Appearance.rounding.small
                    color: lsDevMouse.containsMouse
                        ? Appearance.colors.colSurfaceContainerHighestHover
                        : Appearance.colors.colSurfaceContainer
                    visible: LocalSend.discoveredDevices.length > 0

                    MouseArea {
                        id: lsDevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (LocalSend.droppedFiles.length > 0 && !LocalSend.sending) {
                                root.lsProgress = 0.0
                                LocalSend.sendToDevice(LocalSend.discoveredDevices[0].ip)
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "devices"
                            iconSize: 14
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: LocalSend.discoveredDevices[0] ? LocalSend.discoveredDevices[0].name : Translation.tr("No device")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            visible: LocalSend.droppedFiles.length > 0
                            text: Translation.tr("Send")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                // Scan button
                RippleButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSurfaceContainer
                    onClicked: LocalSend.startScanning()
                    contentItem: Item {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        
                        CircularProgress {
                            anchors.centerIn: parent
                            implicitSize: 14
                            visible: LocalSend.scanning
                            value: 0.7
                            colPrimary: Appearance.colors.colPrimary
                            enableAnimation: true
                        }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 14
                            color: Appearance.colors.colPrimary
                            visible: !LocalSend.scanning
                        }
                    }
                }
            }
        }

        // ── 3. KDE CONNECT READY ────────────────────────────────────────
        ColumnLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            spacing: 6
            visible: root.isReadyKDE

            // Header: device info + status
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                // Device icon + status dot
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    width: 28; height: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, 0.15)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.kdeDevice ? (root.kdeDevice.type === "tablet" ? "tablet" : "smartphone") : "devices"
                            iconSize: 16
                            color: Appearance.colors.colSecondary
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: 8; height: 8; radius: 4
                        color: root.kdeAvailable ? Appearance.colors.colSecondary : Appearance.colors.colError
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.kdeDevice ? root.kdeDevice.name : Translation.tr("KDE Connect")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: {
                            if (!root.kdeAvailable) return Translation.tr("Offline")
                            if (root.kdeDevice && root.kdeDevice.charge >= 0) {
                                return root.kdeDevice.charging
                                    ? Translation.tr("Charging · %1%").arg(root.kdeDevice.charge)
                                    : Translation.tr("Battery %1%").arg(root.kdeDevice.charge)
                            }
                            return Translation.tr("Online")
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.kdeAvailable ? Appearance.colors.colSecondary : Appearance.colors.colError
                    }
                }

                // File count badge
                Rectangle {
                    visible: root.queueFiles.length > 0
                    height: 18
                    implicitWidth: kdeBadge.implicitWidth + 12
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondary
                    StyledText {
                        id: kdeBadge
                        anchors.centerIn: parent
                        text: root.queueFiles.length.toString()
                        font.pixelSize: 10; font.bold: true
                        color: Appearance.colors.colOnSecondary
                    }
                }
            }

            // KDE sending progress bar
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                visible: root.kdeSending

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: "upload"; iconSize: 14; color: Appearance.colors.colSecondary
                        SequentialAnimation on opacity {
                            running: root.kdeSending; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Sending via KDE Connect…")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    valueBarHeight: 4
                    indeterminate: true
                    highlightColor: Appearance.colors.colSecondary
                    trackColor: Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, 0.18)
                }
            }

            // Sent confirmation
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                visible: root.kdeSent

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 36; Layout.preferredHeight: 36
                        shapeString: "Cookie12Sided"
                        color: Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, 0.20)

                        MaterialSymbol { anchors.centerIn: parent; text: "task_alt"; iconSize: 20; color: Appearance.colors.colSecondary }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.kdeFilesSent === 1
                            ? Translation.tr("File sent!")
                            : Translation.tr("%1 files sent!").arg(root.kdeFilesSent)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            // Queued files list
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 80)
                model: root.queueFiles
                spacing: 4
                clip: true
                visible: root.queueFiles.length > 0 && !root.kdeSent && !root.kdeSending

                delegate: Rectangle {
                    id: kdeFileDel
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 32
                    radius: Appearance.rounding.small
                    color: kdeFMouse.containsMouse
                        ? Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, 0.15)
                        : Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, 0.08)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    MouseArea {
                        id: kdeFMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.fileIcon(kdeFileDel.modelData.split("/").pop())
                            iconSize: 16
                            color: Appearance.colors.colSecondary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: kdeFileDel.modelData.split("/").pop()
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideMiddle
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 24
                            implicitHeight: 24
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: {
                                var newFiles = root.queueFiles.slice()
                                newFiles.splice(kdeFileDel.index, 1)
                                root.queueFiles = newFiles
                            }
                            contentItem: Item {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }

            // No files hint
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                visible: root.queueFiles.length === 0 && !root.kdeSent && !root.kdeSending

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.kdeAvailable ? "add_to_drive" : "link_off"
                        iconSize: 24
                        color: Qt.rgba(Appearance.colors.colSecondary.r, Appearance.colors.colSecondary.g, Appearance.colors.colSecondary.b, root.kdeAvailable ? 0.5 : 0.3)
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.kdeAvailable
                            ? Translation.tr("Drop files to send")
                            : Translation.tr("Device offline")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.kdeAvailable ? Appearance.colors.colSubtext : Appearance.colors.colError
                    }
                }
            }

            // Action buttons row
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 6
                visible: !root.kdeSent && !root.kdeSending

                // Cancel button
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colErrorContainer
                    enabled: !root.kdeSending
                    onClicked: {
                        root.queueFiles = []
                        root.serviceChoice = 0
                    }
                    contentItem: StyledText {
                        text: Translation.tr("Cancel")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

                // Send button
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    visible: !root.kdeSent
                    enabled: root.kdeAvailable && !root.kdeSending
                    colBackground: root.kdeAvailable && !root.kdeSending
                        ? Appearance.colors.colSecondary
                        : Appearance.colors.colSurfaceContainerHighest

                    onClicked: {
                        if (!root.kdeAvailable || root.queueFiles.length === 0) return
                        root.kdeSending = true
                        root.kdeFilesSent = root.queueFiles.length
                        for (let i = 0; i < root.queueFiles.length; i++) {
                            KdeConnectService.shareUrl(
                                KdeConnectService.activeDeviceId,
                                "file://" + root.queueFiles[i]
                            )
                        }
                        Qt.callLater(function() {
                            root.kdeSending = false
                            root.kdeSent = true
                            root.queueFiles = []
                            kdeSentTimer.restart()
                        })
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "send"
                            iconSize: 14
                            color: root.kdeAvailable && !root.kdeSending
                                ? Appearance.colors.colOnSecondary
                                : Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: root.queueFiles.length === 1
                                ? Translation.tr("Send file")
                                : Translation.tr("Send %1 files").arg(root.queueFiles.length)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: root.kdeAvailable && !root.kdeSending
                                ? Appearance.colors.colOnSecondary
                                : Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        // Watcher to close widget when queueFiles becomes empty
        Connections {
            target: root
            function onQueueFilesChanged() {
                if (root.queueFiles.length === 0 && root.serviceChoice === 2 && !root.isDragOverNotch) {
                    root.serviceChoice = 0
                }
            }
        }

        // ── 4. IDLE EXPANDED (no service chosen) ────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10
            // Only show when no other state is active
            visible: !root.isIncoming && !root.isReadyLS && !root.isReadyKDE

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 32; height: 32; radius: 8
                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.15)
                    MaterialSymbol { anchors.centerIn: parent; text: "share"; iconSize: 18; color: Appearance.colors.colPrimary }
                }

                ColumnLayout {
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Share Files")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: Translation.tr("Drag files onto the notch to send")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
