import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: rootBox
    property string title: ""
    property string text: ""
    property string codeSnippet: ""
    property string icon: "code"
    /// Snippets that are shell commands rather than data want `Text.Wrap`: breaking
    /// anywhere splits a path mid-token and the reader has to reassemble it.
    property int snippetWrapMode: Text.WrapAnywhere

    // ── Running it here instead ─────────────────────────────────────────────
    /**
     * An optional button that performs what the snippet describes.
     *
     * A command in a copyable box assumes a terminal and a keyboard to paste it into.
     * That assumption holds on a desktop and fails completely on the device this shell's
     * tablet family is for — and the commands that end up in these boxes are exactly the
     * ones standing between that device and a working keyboard. So the snippet stays,
     * for the people who want to read what will run, and it gets a button beside it.
     *
     * Left empty the box behaves exactly as it always did.
     */
    property string actionText: ""
    property string actionIcon: "play_arrow"
    /// While true the button shows `busyText` and cannot be pressed again.
    property bool actionBusy: false
    property string busyText: ""
    /// Shown under the snippet once something has been attempted: what happened.
    property string statusText: ""
    property bool statusIsError: false

    signal actionClicked()

    readonly property int itemIndex: {
        var p = parent;
        if (!p) return 0;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === rootBox) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1) return 0;
        
        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }
        
        var idx = 0;
        for (var i = startIdx; i < selfIdx; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius !== "undefined") {
                idx++;
            }
        }
        return idx;
    }

    readonly property int totalItems: {
        var p = parent;
        if (!p) return 1;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === rootBox) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1) return 1;
        
        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }
        
        var endIdx = children.length - 1;
        for (var i = selfIdx + 1; i < children.length; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                endIdx = i - 1;
                break;
            }
        }
        
        var count = 0;
        for (var i = startIdx; i <= endIdx; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius !== "undefined") {
                count++;
            }
        }
        return count;
    }

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1

    readonly property bool isPressed: {
        for (var i = 0; i < snippetRow.children.length; ++i) {
            var child = snippetRow.children[i];
            if (child.isPressed === true || (child.down !== undefined && child.down === true))
                return true;
        }
        return false;
    }

    readonly property bool prevIsPressed: {
        var p = parent;
        if (!p) return false;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === rootBox) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx <= 0) return false;
        
        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }
        
        for (var i = selfIdx - 1; i >= startIdx; --i) {
            var child = children[i];
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property bool nextIsPressed: {
        var p = parent;
        if (!p) return false;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === rootBox) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1 || selfIdx >= children.length - 1) return false;
        
        var endIdx = children.length - 1;
        for (var i = selfIdx + 1; i < children.length; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                endIdx = i - 1;
                break;
            }
        }
        
        for (var i = selfIdx + 1; i <= endIdx; ++i) {
            var child = children[i];
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(rootBox) }
    Behavior on topRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(rootBox) }
    Behavior on bottomLeftRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(rootBox) }
    Behavior on bottomRightRadius { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(rootBox) }

    color: Appearance.colors.colTertiaryContainer
    implicitWidth: mainColumn.implicitWidth
    implicitHeight: mainColumn.implicitHeight + 24

    ColumnLayout {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 8

        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            MaterialShapeWrappedMaterialSymbol {
                id: icon
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignTop
                text: rootBox.icon
                shape: MaterialShape.Shape.Cookie4Sided
                iconSize: 18
                padding: 6
                color: Appearance.colors.colTertiary
                colSymbol: Appearance.colors.colOnTertiary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: rootBox.title
                    font.bold: true
                    color: Appearance.colors.colOnTertiaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: rootBox.text
                    color: Appearance.colors.colOnTertiaryContainer
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    visible: rootBox.text !== ""
                }
            }
        }

        // Snippet container with copy button
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: snippetRow.implicitHeight + 12
            radius: Appearance.rounding.small
            color: Appearance.colors.colSurfaceContainerHigh
            visible: rootBox.codeSnippet !== ""

            RowLayout {
                id: snippetRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: rootBox.codeSnippet
                    font.family: Appearance.font.family.monospace || "monospace"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurface
                    wrapMode: rootBox.snippetWrapMode
                }

                RippleButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Layout.alignment: Qt.AlignTop
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    property bool copied: false

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: parent.copied ? "check" : "content_copy"
                        iconSize: 16
                        color: parent.copied ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                    }

                    onClicked: {
                        Quickshell.execDetached(["bash", "-c", "wl-copy '" + rootBox.codeSnippet.replace(/'/g, "'\\''") + "'"]);
                        copied = true;
                        copyResetTimer.restart();
                    }

                    Timer {
                        id: copyResetTimer
                        interval: 1500
                        repeat: false
                        onTriggered: parent.copied = false;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: rootBox.actionText !== "" || rootBox.statusText !== ""

            RippleButtonWithIcon {
                visible: rootBox.actionText !== ""
                buttonRadius: Appearance.rounding.small
                materialIcon: rootBox.actionBusy ? "hourglass_top" : rootBox.actionIcon
                mainText: rootBox.actionBusy && rootBox.busyText !== ""
                    ? rootBox.busyText : rootBox.actionText
                enabled: !rootBox.actionBusy
                colBackground: Appearance.colors.colTertiary
                colText: Appearance.colors.colOnTertiary
                onClicked: rootBox.actionClicked()
            }

            StyledText {
                Layout.fillWidth: true
                visible: rootBox.statusText !== ""
                text: rootBox.statusText
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: rootBox.statusIsError
                    ? Appearance.colors.colError : Appearance.colors.colOnTertiaryContainer
            }
        }
    }
}
