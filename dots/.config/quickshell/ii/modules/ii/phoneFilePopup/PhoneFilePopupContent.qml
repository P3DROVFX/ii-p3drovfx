pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.ii.dock.utilities

/**
 * The card for a file from the phone, in three states: receiving (a progress bar under
 * the file), received (Open / Copy / Show in folder, and the file itself can be dragged
 * out of the card into any app; it leaves on its own after a while unless hovered or being
 * dragged) and failed. The close button only hides it: a transfer still running goes on.
 */
Item {
    id: root

    property var transfer
    signal dismissed()

    readonly property string state_: root.transfer?.state ?? "receiving"
    readonly property bool receiving: root.state_ === "receiving"
    readonly property bool done: root.state_ === "done"
    readonly property bool failed: root.state_ === "failed"
    readonly property real progress: (root.transfer?.size ?? 0) > 0 ? Math.min(1, (root.transfer.received ?? 0) / root.transfer.size) : 0
    readonly property string path: root.transfer?.path ?? ""

    readonly property bool isHovered: popupHoverHandler.hovered

    // A finished transfer leaves by itself, as the LocalSend popup does; a running one
    // stays until it is done or closed.
    Timer {
        id: dismissTimer
        interval: 8000
        running: !root.receiving && !root.isHovered && !GlobalStates.fileDragActive
        onTriggered: root.dismissed()
    }

    readonly property bool isImage: /\.(png|jpe?g|webp|gif|bmp|avif)$/i.test(root.path)

    // The file the way a file manager's Copy puts it: pastes as a file in chats, as a
    // picture where an image is wanted.
    function copy(): void {
        if (root.path === "")
            return;
        Quickshell.execDetached([`${Directories.scriptPath}/clipboard/copy_file_to_clipboard.py`, root.path]);
        root.dismissed();
    }

    function open(folder: bool): void {
        if (root.path === "")
            return;
        Qt.openUrlExternally("file://" + (folder ? root.path.slice(0, root.path.lastIndexOf("/")) : root.path));
        root.dismissed();
    }

    property real popupWidth: 320
    property real horizontalPadding: 20
    property real verticalPadding: 20
    readonly property real surfaceMargin: Appearance.sizes.elevationMargin

    implicitWidth: popupWidth + 2 * root.surfaceMargin
    implicitHeight: contentLayout.implicitHeight + verticalPadding * 2 + 2 * root.surfaceMargin

    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
    }

    StyledRectangularShadow {
        target: contentBackground
    }

    Rectangle {
        id: contentBackground
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
        radius: Appearance.rounding.large
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        opacity: 0
        scale: 0.85
        transformOrigin: Item.TopRight
        Component.onCompleted: entranceAnim.start()

        ParallelAnimation {
            id: entranceAnim
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                from: 0
                to: 1
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: contentBackground
                property: "scale"
                from: 0.85
                to: 1
                duration: 400
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => mouse.accepted = true
            onPressed: mouse => mouse.accepted = true
            onReleased: mouse => mouse.accepted = true
        }

        HoverHandler {
            id: popupHoverHandler
        }

        ColumnLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.horizontalPadding
                topMargin: root.verticalPadding
            }
            spacing: 12

            // === WHO SENDS, AND THE CLOSE BUTTON ===
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: root.transfer?.from || Translation.tr("Phone")
                    font.pixelSize: 26
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.dismissed()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            StyledText {
                Layout.topMargin: -8
                text: root.receiving ? Translation.tr("Receiving a file")
                    : root.done ? Translation.tr("Received in Downloads")
                    : Translation.tr("The transfer failed")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
            }

            // === COOKIE: the transfer's state at a glance ===
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                implicitHeight: 160
                Layout.topMargin: 4

                MaterialCookie {
                    anchors.centerIn: parent
                    implicitSize: 150
                    color: root.failed ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: root.receiving ? 6000 : 15000
                        loops: Animation.Infinite
                        running: true
                    }
                    NumberAnimation on scale {
                        from: 0
                        to: 1
                        duration: 650
                        easing.type: Easing.OutBack
                        easing.overshoot: 2.5
                    }
                }

                MaterialSymbol {
                    id: stateIcon
                    anchors.centerIn: parent
                    text: root.receiving ? "download" : root.done ? "download_done" : "error"
                    iconSize: 64
                    color: root.failed ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer

                    // A little bounce when the state changes.
                    onTextChanged: bounce.restart()
                    NumberAnimation on scale {
                        from: 0
                        to: 1
                        duration: 750
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                    SequentialAnimation {
                        id: bounce
                        NumberAnimation {
                            target: stateIcon
                            property: "scale"
                            to: 1.25
                            duration: 160
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: stateIcon
                            property: "scale"
                            to: 1
                            duration: 380
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }
                    }
                }
            }

            // === FILE CARD, with the progress under it while receiving ===
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fileColumn.implicitHeight + 24
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHighest
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // Press and move: the file leaves with the pointer, for any app, the shelf
                // or the AI chat to take. Only a finished file has anything to drag.
                FileDragArea {
                    anchors.fill: parent
                    enabled: root.done
                    paths: root.done ? [root.path] : []
                    dragIcon: root.isImage ? "image-x-generic" : "text-x-generic"
                    onClicked: root.open(false)
                    onDragFinished: root.dismissed()
                    StyledToolTip {
                        requireOverlay: false
                        extraVisibleCondition: root.done
                        text: Translation.tr("Click to open, drag to move the file")
                    }
                }

                ColumnLayout {
                    id: fileColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 12
                    }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ClippingRectangle {
                            visible: root.done && root.isImage
                            implicitWidth: 48
                            implicitHeight: 48
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSurfaceContainerHigh
                            Image {
                                anchors.fill: parent
                                source: root.done && root.isImage ? "file://" + root.path : ""
                                sourceSize: Qt.size(96, 96)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        MaterialSymbol {
                            visible: !(root.done && root.isImage)
                            text: "description"
                            iconSize: 24
                            color: Appearance.colors.colOnSurface
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: root.transfer?.name ?? ""
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideMiddle
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.receiving
                                    ? Translation.tr("%1 of %2").arg(LocalSend.formatFileSize(root.transfer?.received ?? 0)).arg(LocalSend.formatFileSize(root.transfer?.size ?? 0))
                                    : LocalSend.formatFileSize(root.transfer?.size ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        StyledText {
                            visible: root.receiving
                            text: `${Math.round(root.progress * 100)}%`
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                        }
                        MaterialSymbol {
                            visible: root.done
                            text: "drag_indicator"
                            iconSize: 24
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        visible: root.receiving
                        Layout.preferredHeight: 8
                        valueBarHeight: 8
                        from: 0
                        to: 1
                        value: root.progress
                        highlightColor: Appearance.colors.colPrimary
                        trackColor: Appearance.colors.colSurfaceContainerHigh
                        Behavior on value {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            // === WHEN DONE: OPEN IT, COPY IT, OR ITS FOLDER (icons: the card is too narrow for words) ===
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.done
                spacing: 8

                PillButton {
                    Layout.preferredWidth: 64
                    icon: "folder_open"
                    tip: Translation.tr("Show in folder")
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colForeground: Appearance.colors.colOnSurface
                    onClicked: root.open(true)
                }
                PillButton {
                    Layout.preferredWidth: 64
                    icon: "content_copy"
                    tip: Translation.tr("Copy")
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    colForeground: Appearance.colors.colOnSurface
                    onClicked: root.copy()
                }
                PillButton {
                    Layout.fillWidth: true
                    icon: "open_in_new"
                    tip: Translation.tr("Open")
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colForeground: Appearance.colors.colOnPrimaryContainer
                    onClicked: root.open(false)
                }
            }
        }
    }

    /** The LocalSend popup's pill button. */
    component PillButton: Rectangle {
        id: pill
        property string icon
        // Icon-only when empty; `tip` then names it on hover.
        property string label: ""
        property string tip: ""
        property color colBackground
        property color colBackgroundHover
        property color colForeground
        signal clicked()

        Layout.preferredHeight: 40
        implicitHeight: 40
        radius: Appearance.rounding.full
        color: pillMa.containsMouse ? pill.colBackgroundHover : pill.colBackground
        scale: pillMa.pressed ? 0.96 : (pillMa.containsMouse ? 1.02 : 1.0)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                text: pill.icon
                iconSize: pill.label === "" ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.large
                color: pill.colForeground
            }
            StyledText {
                visible: pill.label !== ""
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: pill.colForeground
            }
        }

        MouseArea {
            id: pillMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: pill.clicked()
        }

        StyledToolTip {
            requireOverlay: false
            extraVisibleCondition: pill.tip !== "" && pillMa.containsMouse
            text: pill.tip
        }
    }
}
