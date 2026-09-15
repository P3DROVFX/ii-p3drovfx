pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono

Item {
    id: root

    property var items: []
    property real boundsWidth: 0
    property real boundsHeight: 0
    property real clickX: 0
    property real clickY: 0
    property bool showing: false
    property int submenuIndex: -1
    property real submenuY: 0

    property bool anchorAbove: false

    readonly property int itemHeight: 36
    readonly property int sepHeight: 9
    readonly property int cardPadding: 8
    readonly property int cardWidth: 232
    readonly property int radius: Appearance.rounding.normal
    readonly property int sminK: 9
    readonly property int pad: 16
    readonly property int overlap: radius

    property real subProgress: 0
    property real rippleProgress: 1
    readonly property real rippleAmp: 4
    property real rippleOX: 0
    property real rippleOY: 0

    property var itemsSlotA: []
    property var itemsSlotB: []
    property bool frontA: true
    property real crossA: frontA ? 1 : 0
    property real crossB: frontA ? 0 : 1

    property real subCY: subY + subH / 2
    property real subHH: subH / 2
    readonly property real subGate: Math.max(0, Math.min(1, (subProgress - 0.5) / 0.5))

    property var subItems: (root.submenuIndex >= 0 && root.items[root.submenuIndex]) ? (root.items[root.submenuIndex].submenu ?? []) : []

    visible: showing
    z: 200

    function colHeight(arr) {
        if (!arr || arr.length === 0)
            return 0;
        let h = 0;
        for (const it of arr)
            h += (it.separator === true ? root.sepHeight : root.itemHeight);
        return h + root.cardPadding * 2;
    }

    readonly property bool subOpen: subItems.length > 0
    readonly property real mainH: colHeight(items)
    readonly property real subH: colHeight(subItems)
    readonly property real mainX: anchorAbove
        ? Math.min(Math.max(8, clickX - cardWidth / 2), Math.max(8, boundsWidth - cardWidth - 8))
        : Math.min(Math.max(8, clickX), Math.max(8, boundsWidth - cardWidth - 8))
    readonly property real mainY: anchorAbove
        ? Math.min(Math.max(8, clickY - 8 - mainH), Math.max(8, boundsHeight - mainH - 8))
        : Math.min(Math.max(8, clickY), Math.max(8, boundsHeight - mainH - 8))
    readonly property bool flipped: (mainX + cardWidth + cardWidth + 8 > boundsWidth)
    readonly property real subX: flipped ? (mainX - cardWidth + overlap) : (mainX + cardWidth - overlap)
    readonly property real subY: Math.min(Math.max(8, submenuY), Math.max(8, boundsHeight - subH - 8))
    readonly property real uL: subOpen ? Math.min(mainX, subX) : mainX
    readonly property real uR: subOpen ? Math.max(mainX + cardWidth, subX + cardWidth) : (mainX + cardWidth)
    readonly property real uT: subOpen ? Math.min(mainY, subCY - subHH) : mainY
    readonly property real uB: subOpen ? Math.max(mainY + mainH, subCY + subHH) : (mainY + mainH)
    readonly property real menuX: uL - pad
    readonly property real menuY: uT - pad
    readonly property real menuW: (uR - uL) + pad * 2
    readonly property real menuH: (uB - uT) + pad * 2

    function open(x, y) {
        root.clickX = x;
        root.clickY = y;
        root.submenuIndex = -1;
        root.subProgress = 0;
        root.itemsSlotA = [];
        root.itemsSlotB = [];
        root.frontA = true;
        root.showing = true;
        root.rippleOX = root.mainX + root.cardWidth / 2;
        root.rippleOY = root.mainY + root.mainH / 2;
        Qt.callLater(() => rippleAnim.restart());
    }

    function show(menuItems, x, y) {
        root.items = menuItems;
        root.open(x, y);
    }

    function dismiss() {
        growAnim.stop();
        closeSubAnim.stop();
        root.showing = false;
        root.submenuIndex = -1;
        root.subProgress = 0;
    }

    function trigger(action) {
        if (action)
            action();
        root.dismiss();
    }

    function requestSub(index, rowY) {
        const entry = root.items[index];
        const hasSub = (entry?.submenu?.length ?? 0) > 0 || entry?.hasSubmenu === true;
        if (!hasSub) {
            root.requestCloseSub();
            return;
        }
        if (index === root.submenuIndex && root.subProgress > 0.05)
            return;
        const wasOpen = root.submenuIndex >= 0 && root.subProgress > 0.05;
        closeSubAnim.stop();
        root.submenuIndex = index;
        root.submenuY = root.mainY + root.cardPadding + rowY;
        if (wasOpen) {
            root.subProgress = 1;
        } else {
            root.subProgress = 0;
            growAnim.restart();
            root.rippleOX = root.flipped ? root.subX : (root.subX + root.cardWidth);
            root.rippleOY = root.subCY;
            rippleAnim.restart();
        }
    }

    function requestCloseSub() {
        if (root.submenuIndex < 0)
            return;
        growAnim.stop();
        closeSubAnim.restart();
        root.rippleOX = root.flipped ? (root.mainX + root.overlap) : (root.mainX + root.cardWidth - root.overlap);
        root.rippleOY = root.submenuY + root.itemHeight / 2;
        rippleAnim.restart();
    }

    onSubItemsChanged: {
        if (root.subItems && root.subItems.length > 0) {
            if (root.frontA)
                root.itemsSlotB = root.subItems;
            else
                root.itemsSlotA = root.subItems;
            root.frontA = !root.frontA;
        }
    }

    Behavior on subCY { enabled: root.subProgress > 0.5; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on subHH { enabled: root.subProgress > 0.5; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on crossA { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on crossB { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    NumberAnimation {
        id: growAnim
        target: root
        property: "subProgress"
        from: 0
        to: 1
        duration: 210
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: closeSubAnim
        target: root
        property: "subProgress"
        to: 0
        duration: 380
        easing.type: Easing.OutCubic
        onFinished: root.submenuIndex = -1
    }
    NumberAnimation {
        id: rippleAnim
        target: root
        property: "rippleProgress"
        from: 0
        to: 1
        duration: 600
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.showing
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.dismiss()
    }

    Item {
        id: menu
        x: root.menuX
        y: root.menuY
        width: root.menuW
        height: root.menuH
        opacity: root.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Quickshell.shellPath("assets/shaders/akebono/menu.frag.qsb")

            property vector2d size: Qt.vector2d(width, height)
            property color color: (Config?.options.appearance.transparency.enable ?? false)
                ? Qt.rgba(Appearance.colors.colLayer2Base.r, Appearance.colors.colLayer2Base.g, Appearance.colors.colLayer2Base.b,
                    Math.max(0.8, 1 - Config.options.appearance.transparency.backgroundTransparency))
                : Appearance.colors.colLayer2
            property real radius: root.radius
            property real smoothing: AkebonoAppearance.squircleSmoothing
            property real sminK: root.sminK
            property vector2d mainCenter: Qt.vector2d(root.mainX - root.menuX + root.cardWidth / 2, root.mainY - root.menuY + root.mainH / 2)
            property vector2d mainHalf: Qt.vector2d(root.cardWidth / 2, root.mainH / 2)
            property vector2d subCenter: Qt.vector2d(root.subX - root.menuX + root.cardWidth / 2, root.subCY - root.menuY)
            property vector2d subHalf: Qt.vector2d(root.cardWidth / 2, root.subHH)
            property real subProgress: root.subProgress
            property real attachY: root.submenuY + root.itemHeight / 2 - root.menuY
            property real subSide: root.flipped ? -1 : 1
            property real overlap: root.overlap
            property vector2d rippleOrigin: Qt.vector2d(root.rippleOX - root.menuX, root.rippleOY - root.menuY)
            property real rippleProgress: root.rippleProgress
            property real rippleAmp: root.rippleAmp
        }

        Column {
            id: mainCol
            x: root.mainX - root.menuX + root.cardPadding
            y: root.mainY - root.menuY + root.cardPadding
            width: root.cardWidth - root.cardPadding * 2
            spacing: 0

            Repeater {
                model: root.items
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    width: mainCol.width
                    entry: modelData
                    onHoveredAt: y => {
                        if (((entry.submenu?.length ?? 0) > 0) || entry.hasSubmenu === true)
                            root.requestSub(index, y);
                        else
                            root.requestCloseSub();
                    }
                    onActivated: {
                        if (!(((entry.submenu?.length ?? 0) > 0) || entry.hasSubmenu === true))
                            root.trigger(entry.action);
                    }
                }
            }
        }

        Column {
            id: subSlotA
            visible: root.subOpen && root.itemsSlotA.length > 0
            z: root.frontA ? 1 : 0
            enabled: root.frontA
            opacity: root.subGate * root.crossA
            x: root.subX - root.menuX + root.cardPadding
            y: (root.subCY - root.subHH) - root.menuY + root.cardPadding
            width: root.cardWidth - root.cardPadding * 2
            spacing: 0

            Repeater {
                model: root.itemsSlotA
                delegate: MenuRow {
                    required property var modelData
                    width: subSlotA.width
                    entry: modelData
                    onActivated: root.trigger(entry.action)
                }
            }
        }

        Column {
            id: subSlotB
            visible: root.subOpen && root.itemsSlotB.length > 0
            z: root.frontA ? 0 : 1
            enabled: !root.frontA
            opacity: root.subGate * root.crossB
            x: root.subX - root.menuX + root.cardPadding
            y: (root.subCY - root.subHH) - root.menuY + root.cardPadding
            width: root.cardWidth - root.cardPadding * 2
            spacing: 0

            Repeater {
                model: root.itemsSlotB
                delegate: MenuRow {
                    required property var modelData
                    width: subSlotB.width
                    entry: modelData
                    onActivated: root.trigger(entry.action)
                }
            }
        }
    }

    component MenuRow: Item {
        id: menuRow
        property var entry: ({})
        readonly property bool isSeparator: entry.separator === true
        readonly property bool hasSubmenu: (entry.submenu?.length ?? 0) > 0 || entry.hasSubmenu === true
        readonly property bool enabled: entry.enabled !== false
        signal hoveredAt(real itemY)
        signal activated()

        implicitHeight: isSeparator ? root.sepHeight : root.itemHeight

        Rectangle {
            visible: menuRow.isSeparator
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            height: 1
            color: Qt.alpha(Appearance.colors.colOnLayer2, 0.15)
        }

        Rectangle {
            visible: !menuRow.isSeparator
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            radius: Appearance.rounding.small
            color: (itemMouse.containsMouse && menuRow.enabled)
                ? (menuRow.entry.danger ? Qt.alpha(Appearance.colors.colError, 0.1) : Appearance.colors.colLayer2Hover)
                : "transparent"

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: menuRow.enabled && !menuRow.isSeparator
                cursorShape: Qt.PointingHandCursor
                onEntered: menuRow.hoveredAt(menuRow.y)
                onClicked: menuRow.activated()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Item {
                    Layout.preferredWidth: Appearance.font.pixelSize.large
                    Layout.preferredHeight: Appearance.font.pixelSize.large

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: !menuRow.entry.iconSource
                        text: menuRow.entry.icon ?? ""
                        iconSize: Appearance.font.pixelSize.large
                        color: menuRow.entry.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                        opacity: menuRow.enabled ? 1 : 0.4
                    }
                    Image {
                        anchors.fill: parent
                        visible: !!menuRow.entry.iconSource
                        source: menuRow.entry.iconSource ?? ""
                        sourceSize.width: width
                        sourceSize.height: height
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        opacity: menuRow.enabled ? 1 : 0.4
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: menuRow.entry.label ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: menuRow.entry.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                    opacity: menuRow.enabled ? 1 : 0.4
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    visible: menuRow.hasSubmenu
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }
}
