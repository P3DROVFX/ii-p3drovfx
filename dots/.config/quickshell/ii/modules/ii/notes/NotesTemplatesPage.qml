pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes
import "../../../services/notes/NotesTemplates.js" as Templates

/**
 * Starting from a template rather than an empty page.
 *
 * Designed in Google Material 3 Expressive style: a responsive split layout
 * utilizing the full pane width. On the left, an expressive template catalog
 * with hero icon badges, category tags, structural metadata, and smooth hover/selection
 * state animations. On the right, a live document preview rendering instantiated
 * headings, callouts with tonal containers, checklists, code blocks, and quotes,
 * topped with a prominent primary CTA button.
 */
Item {
    id: root

    signal templateChosen(string title, var tags, var blocks)

    clip: true
    focus: true

    readonly property var templates: Templates.getBuiltinTemplates()
    property int selectedIndex: 0
    readonly property var selected: root.templates[root.selectedIndex] ?? root.templates[0] ?? null
    readonly property var previewBlocks: root.selected ? Templates.instantiateBlocks(root.selected) : []

    readonly property bool isSplit: root.width >= 700

    function use(): void {
        if (!root.selected)
            return;
        const item = root.selected;
        root.templateChosen(item.name,
            Array.isArray(item.tags) ? item.tags.slice() : [],
            Templates.instantiateBlocks(item));
    }

    Keys.onUpPressed: event => {
        if (root.selectedIndex > 0) {
            root.selectedIndex--;
            event.accepted = true;
        }
    }

    Keys.onDownPressed: event => {
        if (root.selectedIndex < root.templates.length - 1) {
            root.selectedIndex++;
            event.accepted = true;
        }
    }

    Keys.onReturnPressed: event => {
        event.accepted = true;
        root.use();
    }

    Component.onCompleted: entrance.restart()

    ParallelAnimation {
        id: entrance

        NumberAnimation {
            target: root
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: contentArea
            property: "y"
            from: NotesMetrics.panePadding + 12
            to: NotesMetrics.panePadding
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    // A slab on layer 1 with transparency, matching the notes sidebars.
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        clip: true
    }

    ColumnLayout {
        id: contentArea
        anchors.fill: parent
        anchors.margins: NotesMetrics.panePadding
        spacing: 12

        // ── Expressive Header Bar ─────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 12

            Rectangle {
                implicitWidth: 38
                implicitHeight: 38
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "dashboard_customize"
                    iconSize: 20
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Template Gallery")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Jumpstart your note with structured blocks and layouts")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                implicitHeight: 28
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                implicitWidth: countBadgeText.implicitWidth + 18

                StyledText {
                    id: countBadgeText
                    anchors.centerIn: parent
                    text: Translation.tr("%1 templates").arg(root.templates.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── Main Content Area (Split View) ────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ── Left: Template Catalog Cards ──────────────────────────────────
            Item {
                Layout.preferredWidth: root.isSplit
                    ? Math.max(300, Math.min(420, Math.round(root.width * 0.42)))
                    : -1
                Layout.fillWidth: !root.isSplit
                Layout.fillHeight: true

                StyledListView {
                    id: catalogView
                    anchors.fill: parent
                    clip: true
                    spacing: NotesMetrics.cardSpacing
                    model: root.templates

                    delegate: RippleButton {
                        id: card
                        required property var modelData
                        required property int index

                        width: catalogView.width
                        implicitHeight: cardLayout.implicitHeight + 22
                        toggled: root.selectedIndex === card.index

                        buttonRadius: NotesMetrics.pillRadius(card.implicitHeight)
                        colBackground: card.toggled
                            ? Appearance.colors.colSecondaryContainer
                            : Appearance.colors.colLayer2
                        colBackgroundHover: card.toggled
                            ? Appearance.colors.colSecondaryContainerHover
                            : Appearance.colors.colLayer2Hover
                        colBackgroundActive: card.toggled
                            ? Appearance.colors.colSecondaryContainerActive
                            : Appearance.colors.colLayer2Active
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive

                        scale: card.down ? 0.97 : (card.hovered ? 1.01 : 1.0)
                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        onClicked: root.selectedIndex = card.index
                        onDoubleClicked: {
                            root.selectedIndex = card.index;
                            root.use();
                        }

                        contentItem: Item {
                            anchors.fill: parent

                            ColumnLayout {
                                id: cardLayout
                                anchors.fill: parent
                                anchors.leftMargin: NotesMetrics.cardPadding
                                anchors.rightMargin: NotesMetrics.cardPadding
                                anchors.topMargin: 10
                                anchors.bottomMargin: 10
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        implicitWidth: 34
                                        implicitHeight: 34
                                        radius: Appearance.rounding.normal
                                        color: card.toggled
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer1

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: card.modelData.icon
                                            iconSize: 18
                                            color: card.toggled
                                                ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colPrimary
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: card.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: card.toggled
                                            ? Appearance.m3colors.m3onSecondaryContainer
                                            : Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        implicitHeight: 22
                                        radius: Appearance.rounding.full
                                        color: card.toggled
                                            ? Qt.rgba(1, 1, 1, 0.14)
                                            : Appearance.colors.colLayer1
                                        implicitWidth: tagLabel.implicitWidth + 12
                                        visible: card.modelData.tags && card.modelData.tags.length > 0

                                        StyledText {
                                            id: tagLabel
                                            anchors.centerIn: parent
                                            text: "#" + (card.modelData.tags ? card.modelData.tags[0] : "")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Medium
                                            color: card.toggled
                                                ? Appearance.m3colors.m3onSecondaryContainer
                                                : Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.description
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: card.toggled
                                        ? Appearance.m3colors.m3onSecondaryContainer
                                        : Appearance.colors.colSubtext
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "view_agenda"
                                        iconSize: 13
                                        color: card.toggled
                                            ? Appearance.m3colors.m3onSecondaryContainer
                                            : Appearance.colors.colSubtext
                                        opacity: 0.7
                                    }

                                    StyledText {
                                        text: Translation.tr("%1 blocks").arg(card.modelData.blocks ? card.modelData.blocks.length : 0)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: card.toggled
                                            ? Appearance.m3colors.m3onSecondaryContainer
                                            : Appearance.colors.colSubtext
                                        opacity: 0.8
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    MaterialSymbol {
                                        text: card.toggled ? "arrow_forward" : "chevron_right"
                                        iconSize: 16
                                        color: card.toggled
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Right: Live Document Preview ──────────────────────────────────
            Rectangle {
                id: previewCard
                visible: root.isSplit
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: NotesMetrics.panePadding
                    spacing: 12

                    // Preview Card Header with Action Button
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        spacing: 10

                        MaterialSymbol {
                            text: root.selected ? root.selected.icon : "description"
                            iconSize: 22
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: root.selected ? root.selected.name : ""
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }

                        Rectangle {
                            implicitHeight: 22
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer1
                            implicitWidth: previewBadge.implicitWidth + 12

                            StyledText {
                                id: previewBadge
                                anchors.centerIn: parent
                                text: Translation.tr("Live Preview")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        RippleButton {
                            id: useButton
                            implicitHeight: 40
                            implicitWidth: useBtnContent.implicitWidth + 32
                            buttonRadius: NotesMetrics.pillRadius(useButton.implicitHeight)
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colBackgroundActive: Appearance.colors.colPrimaryActive

                            scale: useButton.down ? 0.95 : (useButton.hovered ? 1.02 : 1.0)
                            Behavior on scale {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            onClicked: root.use()

                            contentItem: RowLayout {
                                id: useBtnContent
                                anchors.centerIn: parent
                                spacing: 8

                                MaterialSymbol {
                                    text: "note_add"
                                    iconSize: 18
                                    color: Appearance.colors.colOnPrimary
                                }

                                StyledText {
                                    text: Translation.tr("Use template")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }

                    // Rendered Document Preview Content
                    StyledFlickable {
                        id: previewScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: previewBody.implicitHeight + 16
                        clip: true

                        ColumnLayout {
                            id: previewBody
                            width: previewScroll.width - 12
                            spacing: 8

                            Repeater {
                                model: root.previewBlocks

                                delegate: Item {
                                    id: blockRow
                                    required property var modelData
                                    required property int index

                                    Layout.fillWidth: true
                                    implicitHeight: blockContent.implicitHeight

                                    Item {
                                        id: blockContent
                                        width: parent.width
                                        implicitHeight: blockLoader.implicitHeight

                                        Loader {
                                            id: blockLoader
                                            width: parent.width
                                            sourceComponent: {
                                                const type = blockRow.modelData.type;
                                                if (type === "heading") return headingComp;
                                                if (type === "callout") return calloutComp;
                                                if (type === "list") return listComp;
                                                if (type === "code") return codeComp;
                                                if (type === "quote") return quoteComp;
                                                return textComp;
                                            }
                                        }

                                        // Heading Block Component
                                        Component {
                                            id: headingComp

                                            StyledText {
                                                width: parent.width
                                                text: blockRow.modelData.text ?? ""
                                                font.pixelSize: blockRow.modelData.level === 1
                                                    ? Appearance.font.pixelSize.huge
                                                    : Appearance.font.pixelSize.larger
                                                font.weight: Font.Bold
                                                color: Appearance.colors.colOnSurface
                                                wrapMode: Text.WordWrap
                                            }
                                        }

                                        // Callout Block Component
                                        Component {
                                            id: calloutComp

                                            Rectangle {
                                                width: parent.width
                                                implicitHeight: calloutRow.implicitHeight + 18
                                                radius: Appearance.rounding.normal
                                                color: {
                                                    const tone = blockRow.modelData.tone;
                                                    if (tone === "success") return Appearance.m3colors.m3successContainer;
                                                    if (tone === "warning") return Appearance.m3colors.m3tertiaryContainer;
                                                    if (tone === "error") return Appearance.m3colors.m3errorContainer;
                                                    return Appearance.colors.colSecondaryContainer;
                                                }

                                                readonly property color onToneColor: {
                                                    const tone = blockRow.modelData.tone;
                                                    if (tone === "success") return Appearance.m3colors.m3onSuccessContainer;
                                                    if (tone === "warning") return Appearance.m3colors.m3onTertiaryContainer;
                                                    if (tone === "error") return Appearance.m3colors.m3onErrorContainer;
                                                    return Appearance.m3colors.m3onSecondaryContainer;
                                                }

                                                RowLayout {
                                                    id: calloutRow
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    anchors.topMargin: 9
                                                    anchors.bottomMargin: 9
                                                    spacing: 10

                                                    MaterialSymbol {
                                                        text: {
                                                            const tone = blockRow.modelData.tone;
                                                            if (tone === "success") return "check_circle";
                                                            if (tone === "warning") return "warning";
                                                            if (tone === "error") return "error";
                                                            return "info";
                                                        }
                                                        iconSize: 18
                                                        color: parent.parent.onToneColor
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: blockRow.modelData.text ?? ""
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.Medium
                                                        color: parent.parent.onToneColor
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }
                                            }
                                        }

                                        // List Block Component (Checkboxes, Bullets, Numbers)
                                        Component {
                                            id: listComp

                                            RowLayout {
                                                width: parent.width
                                                spacing: 10

                                                MaterialSymbol {
                                                    visible: blockRow.modelData.style === "checkbox"
                                                    text: blockRow.modelData.checked ? "check_box" : "check_box_outline_blank"
                                                    iconSize: 18
                                                    color: blockRow.modelData.checked
                                                        ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colSubtext
                                                }

                                                MaterialSymbol {
                                                    visible: blockRow.modelData.style === "bullet" || !blockRow.modelData.style
                                                    text: "fiber_manual_record"
                                                    iconSize: 8
                                                    color: Appearance.colors.colPrimary
                                                }

                                                Rectangle {
                                                    visible: blockRow.modelData.style === "number"
                                                    implicitWidth: 18
                                                    implicitHeight: 18
                                                    radius: Appearance.rounding.full
                                                    color: Appearance.colors.colLayer1

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: String(blockRow.index + 1)
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: Font.Bold
                                                        color: Appearance.colors.colPrimary
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(blockRow.modelData.text ?? "").length > 0
                                                        ? blockRow.modelData.text
                                                        : Translation.tr("Item to fill in")
                                                    opacity: String(blockRow.modelData.text ?? "").length > 0 ? 1 : 0.5
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colOnSurface
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }

                                        // Code Block Component
                                        Component {
                                            id: codeComp

                                            Rectangle {
                                                width: parent.width
                                                implicitHeight: codeCol.implicitHeight + 18
                                                radius: Appearance.rounding.normal
                                                color: Appearance.colors.colLayer1

                                                ColumnLayout {
                                                    id: codeCol
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 4

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        StyledText {
                                                            text: (blockRow.modelData.language ?? "code").toUpperCase()
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: Font.Bold
                                                            color: Appearance.colors.colPrimary
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                        MaterialSymbol {
                                                            text: "code"
                                                            iconSize: 14
                                                            color: Appearance.colors.colSubtext
                                                        }
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(blockRow.modelData.text ?? "").length > 0
                                                            ? blockRow.modelData.text
                                                            : Translation.tr("// Add code snippet here")
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colOnSurface
                                                        opacity: String(blockRow.modelData.text ?? "").length > 0 ? 0.95 : 0.5
                                                    }
                                                }
                                            }
                                        }

                                        // Quote Block Component
                                        Component {
                                            id: quoteComp

                                            RowLayout {
                                                width: parent.width
                                                spacing: 10

                                                Rectangle {
                                                    Layout.fillHeight: true
                                                    implicitWidth: 3
                                                    radius: 2
                                                    color: Appearance.colors.colPrimary
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: blockRow.modelData.text ?? ""
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.italic: true
                                                    color: Appearance.colors.colOnSurfaceVariant
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }

                                        // Plain Text Component
                                        Component {
                                            id: textComp

                                            StyledText {
                                                width: parent.width
                                                text: String(blockRow.modelData.text ?? "").length > 0
                                                    ? blockRow.modelData.text
                                                    : Translation.tr("Paragraph text...")
                                                opacity: String(blockRow.modelData.text ?? "").length > 0 ? 1 : 0.45
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: Appearance.colors.colOnSurface
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Bottom Action Button (visible only in narrow single-column mode) ─
        RippleButton {
            id: mobileUseButton
            visible: !root.isSplit
            Layout.fillWidth: true
            implicitHeight: 48
            buttonRadius: NotesMetrics.pillRadius(mobileUseButton.implicitHeight)
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colBackgroundActive: Appearance.colors.colPrimaryActive

            onClicked: root.use()

            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    text: "note_add"
                    iconSize: 20
                    color: Appearance.colors.colOnPrimary
                }

                StyledText {
                    text: root.selected
                        ? Translation.tr("Create note from %1").arg(root.selected.name)
                        : Translation.tr("Create note")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
