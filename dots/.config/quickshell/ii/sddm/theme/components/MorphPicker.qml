import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * An island that opens into its own list. Closed, it is a pill with the current
 * entry (avatar or icon, name, chevron). Open, the island itself grows: it
 * widens in the row, so the islands anchored to it slide aside instead of being
 * covered, and it grows upward into a card built like the bar popups (surface
 * container, large radius, 1 px outline, a header, then tiles as in the battery
 * popup). The current entry stays at the bottom, in the pill; the tiles list
 * the others.
 *
 * `entries` is a list of { icon, image, label, detail, active }.
 */
FocusScope {
    id: root

    property var entries: []
    property string icon: ""
    property string image: ""
    property string label: ""
    property string title: ""
    property int maxVisibleTiles: 5
    readonly property bool interactive: root.entries.length > 1
    readonly property bool open: root.isOpen
    signal picked(int index)
    // Closed by a pick, Escape or Return; not when focus simply moved elsewhere.
    signal dismissed

    property bool isOpen: false
    // Every entry but the current one, keeping its index in `entries`.
    readonly property var others: root.entries.map((e, i) => Object.assign({ index: i }, e)).filter(e => e.active !== true)

    readonly property real inset: 3                 // the toolbar's padding
    readonly property real pad: 10                  // the popups' margin
    readonly property real tileHeight: 56
    readonly property real tileSpacing: 6
    readonly property real iconSize: 36
    readonly property real tilesHeight: {
        const n = Math.min(root.others.length, root.maxVisibleTiles);
        return n > 0 ? n * root.tileHeight + (n - 1) * root.tileSpacing : 0;
    }
    readonly property real closedWidth: Math.min(320, face.implicitWidth + face.anchors.leftMargin + face.anchors.rightMargin + root.inset * 2)
    readonly property real openWidth: Math.ceil(Math.min(360, Math.max(root.closedWidth, 240, root.pad * 2 + 12 + root.iconSize + 12 + Math.max(longestLabel.advanceWidth, longestDetail.advanceWidth) + 12 + 4)))
    readonly property real openHeight: root.pad + header.implicitHeight + 8 + root.tilesHeight + 10 + 1 + 6 + Theme.toolbarHeight

    width: root.isOpen ? root.openWidth : root.closedWidth
    height: Theme.toolbarHeight
    Behavior on width {
        NumberAnimation {
            duration: Theme.ms(400)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveDefaultSpatial
        }
    }

    function show() {
        if (!root.interactive || root.isOpen)
            return;
        list.currentIndex = -1;
        list.positionViewAtBeginning();
        root.isOpen = true;
        root.forceActiveFocus();
    }
    function close() {
        root.isOpen = false;
    }
    function pick(index) {
        // Close before announcing: the pick rebuilds `entries` and the tiles with it.
        root.close();
        root.picked(index);
        root.dismissed();
    }

    onActiveFocusChanged: if (!activeFocus) root.close()

    Keys.onPressed: event => {
        if (!root.isOpen)
            return;
        switch (event.key) {
        case Qt.Key_Up:
            list.currentIndex = list.currentIndex < 0 ? list.count - 1 : Math.max(0, list.currentIndex - 1);
            break;
        case Qt.Key_Down:
            list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (list.currentIndex >= 0)
                root.pick(root.others[list.currentIndex].index);
            else {
                root.close();
                root.dismissed();
            }
            break;
        case Qt.Key_Escape:
            root.close();
            root.dismissed();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Measured with the tiles' own text style: TextMetrics skips the hinting
    // StyledText renders with and comes out a few pixels short.
    StyledText {
        id: longestLabel
        visible: false
        readonly property real advanceWidth: implicitWidth
        font.pixelSize: Theme.pxNormal
        font.weight: Font.Bold
        text: root.others.reduce((a, e) => String(e.label ?? "").length > a.length ? String(e.label) : a, "")
    }
    StyledText {
        id: longestDetail
        visible: false
        readonly property real advanceWidth: implicitWidth
        font.pixelSize: Theme.pxSmaller
        font.weight: Font.DemiBold
        text: root.others.reduce((a, e) => String(e.detail ?? "").length > a.length ? String(e.detail) : a, "")
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: 0.9 * Theme.elevationMargin
        offset: Qt.vector2d(0.0, 1.0)
        spread: 1
        color: Theme.colShadow
        cached: true
        visible: !Theme.transparency
    }

    Rectangle {
        id: card
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: root.isOpen ? root.openHeight : Theme.toolbarHeight
        radius: Theme.sharpMode ? Theme.roundingFull : (root.isOpen ? Theme.roundingLarge : Theme.toolbarHeight / 2)
        color: Theme.m3surfaceContainer
        border.width: 1
        border.color: root.isOpen && !Theme.transparency ? Theme.colLayer0Border : Theme.transparentize(Theme.colLayer0Border, 1)
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Theme.ms(400)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveDefaultSpatial
            }
        }
        Behavior on radius {
            NumberAnimation {
                duration: Theme.ms(300)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveEffects
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Theme.ms(200)
            }
        }

        // Keep clicks on the card from reaching the surface behind it.
        MouseArea {
            anchors.fill: parent
        }

        // ── open: header and tiles, laid out at the open width ─────────────
        // Anchored to the bottom so the card uncovers them as it grows,
        // without reflowing anything mid-animation.
        ColumnLayout {
            id: body
            x: root.pad
            width: root.openWidth - root.pad * 2
            anchors.bottom: divider.top
            anchors.bottomMargin: 10
            spacing: 8
            opacity: root.isOpen ? 1 : 0
            visible: opacity > 0
            enabled: root.isOpen
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.ms(root.isOpen ? 200 : 100)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveEffects
                }
            }

            StyledText {
                id: header
                Layout.leftMargin: 6
                text: root.title
                font.pixelSize: Theme.pxSmall
                color: Theme.m3onSurfaceVariant
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: root.tilesHeight
                spacing: root.tileSpacing
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                highlightFollowsCurrentItem: false
                model: root.others

                delegate: IslandButton {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: ListView.isCurrentItem
                    width: ListView.view.width
                    height: root.tileHeight
                    buttonRadius: Theme.roundingSmall
                    colBackground: isCurrent ? Theme.colSurfaceContainerHighestHover : Theme.m3surfaceContainerHigh
                    colBackgroundHover: Theme.colSurfaceContainerHighestHover
                    colBackgroundActive: Theme.m3surfaceContainerHighest
                    colRipple: Theme.mix(Theme.m3surfaceContainerHighest, Theme.m3onSurface, 0.85)
                    onHoveredChanged: if (hovered) list.currentIndex = index

                    // The battery popup's entrance, staggered by row.
                    opacity: 0
                    transform: Translate {
                        id: tileShift
                        y: 16
                    }
                    Connections {
                        target: root
                        function onIsOpenChanged() {
                            if (root.isOpen) {
                                tileIn.restart();
                            } else {
                                tileIn.stop();
                                tile.opacity = 0;
                                tileShift.y = 16;
                            }
                        }
                    }
                    Component.onCompleted: if (root.isOpen) tileIn.restart()
                    SequentialAnimation {
                        id: tileIn
                        PauseAnimation {
                            duration: 40 + tile.index * 40
                        }
                        ParallelAnimation {
                            NumberAnimation { target: tile; property: "opacity"; to: 1; duration: 250 }
                            NumberAnimation { target: tileShift; property: "y"; to: 0; duration: 380; easing.type: Easing.OutBack }
                        }
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Item {
                            Layout.preferredWidth: root.iconSize
                            Layout.preferredHeight: root.iconSize

                            MaterialShape {
                                anchors.fill: parent
                                visible: !picture.ready
                                shape: "Slanted"
                                color: Theme.m3secondaryContainer
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !picture.ready
                                text: tile.modelData.icon ?? ""
                                fill: 1
                                iconSize: Theme.pxNormal
                                color: Theme.m3onSecondaryContainer
                            }
                            RoundPicture {
                                id: picture
                                anchors.fill: parent
                                source: tile.modelData.image ?? ""
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -2

                            StyledText {
                                Layout.fillWidth: true
                                text: tile.modelData.label ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Theme.pxNormal
                                font.weight: Font.Bold
                                color: Theme.m3onSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: tile.modelData.detail ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Theme.pxSmaller
                                font.weight: Font.DemiBold
                                color: Theme.m3onSurfaceVariant
                            }
                        }
                    }

                    onClicked: {
                        const picker = root;
                        const picked = tile.modelData.index;
                        picker.pick(picked);
                    }
                }
            }
        }

        Rectangle {
            id: divider
            anchors {
                left: parent.left
                right: parent.right
                bottom: faceButton.top
                leftMargin: root.pad
                rightMargin: root.pad
                bottomMargin: 6 - root.inset
            }
            height: 1
            color: Theme.m3surfaceContainerHighest
            opacity: body.opacity
            visible: body.visible
        }

        // ── the current entry: the pill, always at the bottom ──────────────
        IslandButton {
            id: faceButton
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: root.inset
            }
            height: Theme.toolbarHeight - root.inset * 2
            enabled: root.interactive
            // Not dimmed when disabled: a single entry is shown, just not switchable.
            opacity: 1
            pointingHandCursor: root.interactive
            onClicked: {
                if (root.isOpen) {
                    root.close();
                    root.dismissed();
                } else {
                    root.show();
                }
            }

            contentItem: Item {
                RowLayout {
                    id: face
                    anchors.fill: parent
                    // Sized from whether there is a picture, never from its load
                    // state: that would resize, reload and resize again.
                    anchors.leftMargin: root.image !== "" ? 4 : 12
                    anchors.rightMargin: root.interactive ? 8 : 14
                    spacing: 8

                    Item {
                        Layout.preferredWidth: root.image !== "" ? Theme.toolbarHeight - 14 : Theme.pxLarger
                        Layout.preferredHeight: Layout.preferredWidth
                        RoundPicture {
                            id: facePicture
                            anchors.fill: parent
                            source: root.image
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !facePicture.ready
                            text: root.icon
                            fill: 1
                            iconSize: Theme.pxLarger
                            color: Theme.m3onSurfaceVariant
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.label
                        elide: Text.ElideRight
                        font.pixelSize: Theme.pxSmall
                        color: Theme.m3onSurface
                    }
                    MaterialSymbol {
                        visible: root.interactive
                        text: "keyboard_arrow_up"
                        iconSize: Theme.pxLarger
                        color: Theme.m3onSurfaceVariant
                        rotation: root.isOpen ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: Theme.ms(250)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveEffects
                            }
                        }
                    }
                }
            }
        }
    }

    // A picture cropped to a circle; `ready` once it has loaded.
    component RoundPicture: Item {
        id: pic
        property string source: ""
        readonly property bool ready: image.status === Image.Ready

        Image {
            id: image
            anchors.fill: parent
            source: pic.source
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectCrop
            visible: false
            asynchronous: true
        }
        OpacityMask {
            anchors.fill: parent
            source: image
            visible: pic.ready
            maskSource: Rectangle {
                width: image.width
                height: image.height
                radius: width / 2
            }
        }
    }
}
