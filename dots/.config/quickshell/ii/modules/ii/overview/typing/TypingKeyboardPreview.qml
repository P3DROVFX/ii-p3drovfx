pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import "TypingFingers.js" as Fingers

// The same geometry renderer serves static layouts and the real Vial board.
// Guidance never writes to hardware or tries to observe the user's hands.
Item {
    id: root

    property string layoutId: Config.options.search.typingTest.keyboard.layout
    property bool highlightNext: Config.options.search.typingTest.keyboard.highlightNextKey
    property bool fingerGuide: Config.options.search.typingTest.keyboard.fingerGuide
    property string nextChar: ""
    property string pressedChar: ""
    property real keySize: 32
    property real keySpacing: 5
    property real maxWidth: 0
    property real maxHeight: 0
    property bool editingFingers: false
    property int selectedKey: -1
    signal requestInputFocus

    readonly property bool vialMode: root.layoutId === TypingKeyboardLayouts.liveLayoutId
    readonly property var classic: Fingers.classicBoard(TypingKeyboardLayouts.rowsFor(root.layoutId), TypingKeyboardLayouts.labelFor(root.layoutId))
    readonly property var keys: root.vialMode ? VialKeyboard.keys : root.classic.keys
    readonly property var entries: root.vialMode ? VialKeyboard.activeLabels : root.classic.entries
    readonly property bool boardReady: !root.vialMode || VialKeyboard.ready
    readonly property string boardId: root.vialMode
        ? "vial:" + (VialKeyboard.snapshot.deviceUid || VialKeyboard.name) : "classic:" + root.layoutId
    readonly property real boardWidth: root.vialMode ? VialKeyboard.unitWidth : root.classic.width
    readonly property real boardHeight: root.vialMode ? VialKeyboard.unitHeight : root.classic.height
    readonly property real basicUnit: root.keySize + root.keySpacing
    readonly property real preferredUnit: root.keySize * (root.fingerGuide ? 2 : 1) + root.keySpacing
    readonly property real sectionSpacing: Appearance.sizes.elevationMargin * 2.4
    readonly property bool hasInfo: root.boardReady && (root.fingerGuide || (root.vialMode && VialKeyboard.layerCount > 1))
    readonly property real sidebarWidth: root.maxWidth > 0 && root.maxWidth < 1000 ? 180 : 320
    // Keep the board at least as wide as the ordinary preview before giving
    // space to a sidebar. Very narrow hosts retain the stacked arrangement.
    readonly property bool sideBySide: root.fingerGuide && root.boardReady
        && (root.maxWidth <= 0 || root.maxWidth >= root.boardWidth * root.basicUnit + root.sidebarWidth + root.sectionSpacing)
    readonly property real contentWidth: {
        const natural = root.boardWidth * root.preferredUnit
            + (root.sideBySide ? root.sidebarWidth + root.sectionSpacing : 0);
        return root.maxWidth > 0 ? Math.min(root.maxWidth, Math.max(natural, 440)) : Math.max(natural, 440);
    }
    // These widths never depend on the height-constrained key unit. The text
    // wraps here, and its height may in turn constrain a stacked keyboard.
    readonly property real infoWidth: root.sideBySide ? root.sidebarWidth : root.contentWidth
    readonly property real boardAvailableWidth: Math.max(1, root.contentWidth
        - (root.sideBySide ? root.infoWidth + root.sectionSpacing : 0))
    readonly property real infoHeightLimit: {
        if (root.maxHeight <= 0) return Infinity;
        if (root.sideBySide) return root.maxHeight;
        const basicBoardHeight = Math.min(root.basicUnit, root.boardAvailableWidth / Math.max(1, root.boardWidth)) * root.boardHeight;
        return Math.max(0, root.maxHeight - basicBoardHeight - content.rowSpacing);
    }
    readonly property real unit: {
        const widthLimit = root.boardWidth > 0 ? root.boardAvailableWidth / root.boardWidth : Infinity;
        const chrome = !root.sideBySide && root.hasInfo ? infoViewport.implicitHeight + content.rowSpacing : 0;
        const heightLimit = root.maxHeight > 0 && root.boardHeight > 0 ? Math.max(1, root.maxHeight - chrome) / root.boardHeight : Infinity;
        return Math.min(root.preferredUnit, widthLimit, heightLimit);
    }
    readonly property var automaticFingers: !root.fingerGuide ? []
        : root.vialMode ? Fingers.infer(root.keys) : root.classic.fingers
    readonly property var assignedFingers: !root.fingerGuide ? []
        : Fingers.assignments(root.automaticFingers, root.keys, root.boardId, Config.options.search.typingTest.keyboard.fingerAssignments)
    readonly property var keyHints: root.assignedFingers.map(finger => ({
        fill: finger ? TypingFingerPalette.fill(finger) : undefined,
        ink: finger ? TypingFingerPalette.ink(finger) : undefined,
        name: TypingFingerPalette.name(finger)
    }))
    readonly property var nextKeys: root.fingerGuide && root.highlightNext ? Fingers.targets(root.entries, root.nextChar) : []
    readonly property var nextFingers: root.nextKeys.map(index => root.assignedFingers[index]).filter((finger, index, all) => finger && all.indexOf(finger) === index)
    readonly property var fingerChoices: [0, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6]
    readonly property string nextHint: {
        if (root.editingFingers) return Translation.tr("Select a key to assign its finger");
        if (!root.highlightNext || !root.nextChar) return Translation.tr("Follow the colors · hover a key for its finger");
        if (root.nextFingers.length) return root.nextFingers.map(finger => TypingFingerPalette.name(finger)).join(" / ");
        return root.nextKeys.length ? Translation.tr("Assign a finger to this key")
            : Translation.tr("Next character is not mapped on this layer");
    }

    implicitWidth: root.contentWidth
    implicitHeight: content.implicitHeight
    onLayoutIdChanged: { root.selectedKey = -1; root.editingFingers = false; }
    onBoardIdChanged: root.selectedKey = -1
    onFingerGuideChanged: if (!root.fingerGuide) root.editingFingers = false
    onVialModeChanged: if (root.vialMode) VialKeyboard.ensureLoaded()
    Component.onCompleted: if (root.vialMode) VialKeyboard.ensureLoaded()

    Timer {
        id: flashTimer
        interval: 120
        onTriggered: root.pressedChar = ""
    }
    function flash(character: string) {
        root.pressedChar = String(character ?? "").toLowerCase();
        flashTimer.restart();
    }
    function assignFinger(finger: int) {
        const key = root.keys[root.selectedKey];
        if (!key) return;
        Config.options.search.typingTest.keyboard.fingerAssignments = Fingers.saveAssignment(
            Config.options.search.typingTest.keyboard.fingerAssignments, root.boardId, key, finger);
        root.requestInputFocus();
    }

    component SmallButton: RippleButton {
        id: smallButton
        implicitHeight: 30
        implicitWidth: label.implicitWidth + 20
        focusPolicy: Qt.NoFocus
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colRipple: Appearance.colors.colSurfaceContainerHighestActive
        StyledText {
            id: label
            anchors.centerIn: parent
            text: smallButton.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurface
        }
    }

    GridLayout {
        id: content
        width: root.contentWidth
        columns: root.sideBySide ? 2 : 1
        columnSpacing: root.sectionSpacing
        rowSpacing: root.keySpacing * 2

        Item {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.boardAvailableWidth
            implicitHeight: root.boardReady ? diagram.implicitHeight : unavailable.implicitHeight

            StyledText {
                id: unavailable
                width: parent.width
                anchors.centerIn: parent
                visible: !root.boardReady
                text: VialKeyboard.loading ? Translation.tr("Reading the keyboard…")
                    : Translation.tr("No Vial keyboard is readable. Plug it in, or pick another layout.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }

            KeyboardDiagram {
                id: diagram
                objectName: "typingKeyboardDiagram"
                anchors.centerIn: parent
                visible: root.boardReady
                keys: root.keys
                entries: root.entries
                unitWidth: root.boardWidth
                unitHeight: root.boardHeight
                unit: root.unit
                keySpacing: root.keySpacing
                labelSize: root.fingerGuide ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.small
                nextChar: root.highlightNext ? root.nextChar : ""
                pressedChar: root.pressedChar
                keyHints: root.keyHints
                hintTooltips: root.fingerGuide
                interactive: root.editingFingers
                preserveInputFocus: true
                selectedKey: root.editingFingers ? root.selectedKey : -1
                onKeyClicked: keyIndex => { root.selectedKey = keyIndex; root.requestInputFocus(); }
            }
        }

        StyledFlickable {
            id: infoViewport
            objectName: "typingFingerInfo"
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            Layout.fillWidth: !root.sideBySide
            implicitWidth: root.infoWidth
            // Layouts round both rows up; leave fractional pixels to the
            // keyboard so their combined height stays within the budget.
            implicitHeight: Math.floor(Math.min(info.implicitHeight, root.infoHeightLimit))
            visible: root.hasInfo
            contentWidth: width
            contentHeight: info.implicitHeight
            clip: true
            // Small hosts can scroll the guidance instead of taking height
            // from the words or shrinking the keyboard to fit the controls.
            interactive: contentHeight > height

            ColumnLayout {
                id: info
                width: infoViewport.width
                spacing: root.keySpacing * 2

                Loader {
                    id: guideLoader
                    Layout.fillWidth: true
                    active: root.fingerGuide && root.boardReady && !root.editingFingers
                    visible: active
                    sourceComponent: ColumnLayout {
                        spacing: root.keySpacing * 2
                        TypingFingerHands {
                            Layout.alignment: Qt.AlignHCenter
                            stacked: root.sideBySide && root.infoWidth < 300
                            activeFingers: root.nextFingers
                        }
                        StyledText {
                            Layout.fillWidth: true
                            // Reserve three lines so changes of finger or an
                            // unmapped character never move the typing stage.
                            Layout.preferredHeight: Math.ceil(font.pixelSize * 1.3) * 3
                            text: root.nextHint
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                            Accessible.name: root.nextHint
                            HoverHandler { id: cueHover }
                            StyledToolTip { text: root.nextHint; extraVisibleCondition: cueHover.hovered }
                        }
                    }
                }

                GridLayout {
                    id: layers
                    objectName: "typingLayerControls"
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.vialMode && root.boardReady && VialKeyboard.layerCount > 1
                    columns: Math.max(1, Math.floor(root.infoWidth / 42))
                    columnSpacing: root.keySpacing
                    rowSpacing: root.keySpacing
                    Repeater {
                        model: root.vialMode && root.boardReady ? VialKeyboard.layerCount : 0
                        delegate: SmallButton {
                            required property int index
                            text: "L" + index
                            colBackground: VialKeyboard.activeLayer === index ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colSurfaceContainerHigh
                            onClicked: { VialKeyboard.setLayer(index); root.requestInputFocus(); }
                        }
                    }
                }

                SmallButton {
                    objectName: "editFingersButton"
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.fingerGuide && root.boardReady
                    text: root.editingFingers ? Translation.tr("Done") : Translation.tr("Adjust fingers")
                    onClicked: {
                        root.editingFingers = !root.editingFingers;
                        infoViewport.contentY = 0;
                        root.requestInputFocus();
                    }
                }

                ColumnLayout {
                    id: editor
                    Layout.fillWidth: true
                    visible: root.editingFingers
                    spacing: root.keySpacing
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Suggested by position. Adjust any key for your keyboard or technique.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedKey >= 0 ? (root.entries[root.selectedKey]?.label || "—")
                            : Translation.tr("Select a key to assign its finger")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledComboBox {
                        objectName: "fingerAssignmentChoice"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        enabled: root.selectedKey >= 0 && root.selectedKey < root.keys.length
                        model: root.fingerChoices.map(finger => TypingFingerPalette.name(finger))
                        currentIndex: Math.max(0, root.fingerChoices.indexOf(root.assignedFingers[root.selectedKey] || 0))
                        Accessible.name: Translation.tr("Finger for the selected key")
                        onActivated: index => root.assignFinger(root.fingerChoices[index])
                    }
                    SmallButton {
                        text: Translation.tr("Reset fingers")
                        onClicked: {
                            Config.options.search.typingTest.keyboard.fingerAssignments = Fingers.resetBoard(
                                Config.options.search.typingTest.keyboard.fingerAssignments, root.boardId);
                            root.requestInputFocus();
                        }
                    }
                }
            }
        }
    }
}
