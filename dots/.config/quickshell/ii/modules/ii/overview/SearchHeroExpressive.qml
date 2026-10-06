pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets

/**
 * The top result in the expressive results style: a hero card, not a row.
 *
 * Same contract as `SearchBestMatch` (activate, clicked, runSecondary, the
 * shared action list), different voice: the name is set big in condensed heavy
 * type, the primary action is a filled pill on the trailing edge, the result's
 * own actions are tinted chips on the card's content colour, and a scalloped
 * ornament ~1.9× the card's height sits clipped past the right edge. Selection
 * fills the card with primary container and morphs the ornament.
 */
RippleButton {
    id: root

    property var entry
    property string query
    property int listIndex: 0
    property int listCurrentIndex: -1
    property int secondaryLimit: 4
    // Room under the card before the next group; the hero has no caption of
    // its own to carry the gap.
    property real bottomGap: Appearance.sizes.elevationMargin * 1.4

    signal resultExecuted(string feedbackText)

    readonly property bool isSelected: root.listIndex === root.listCurrentIndex
    readonly property string itemName: entry?.name ?? ""
    readonly property string itemComment: entry?.comment ?? ""
    readonly property string itemType: entry?.type ?? ""
    readonly property string verb: entry?.verb ?? Translation.tr("Open")
    readonly property var iconType: entry?.iconType

    readonly property var actionItems: SearchResultActions.build(root.entry, {
        onDone: function () {},
        onExecuted: feedbackText => root.resultExecuted(feedbackText)
    })
    readonly property var secondaryActions: root.actionItems.slice(1, 1 + Math.max(0, root.secondaryLimit))
    readonly property int hiddenActionCount: Math.max(0, root.actionItems.length - 1 - root.secondaryActions.length)

    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    readonly property int cardPadding: 20
    /**
     * The card's height, settled the frame the hero is built.
     *
     * Deriving it from the layouts (`RowLayout.implicitHeight`, a wrapping
     * `Flow`) let it grow a frame later, once they polished and the chips
     * wrapped to a second line: the hero opened at one height and jumped to
     * another. Only text implicit heights and constants go in here — those are
     * right immediately — and the chips keep to one line of fixed height.
     */
    readonly property real chipHeight: 32
    readonly property real chipGap: 14
    readonly property bool hasChips: root.secondaryActions.length > 0 || root.hiddenActionCount > 0
    readonly property real textBlockHeight: overline.implicitHeight + 2 + nameText.implicitHeight
        + (root.itemComment.length > 0 ? 2 + commentText.implicitHeight : 0)
    readonly property real topBlockHeight: Math.max(72, root.textBlockHeight)
    readonly property real cardHeight: root.cardPadding * 2 + root.topBlockHeight
        + (root.hasChips ? root.chipGap + root.chipHeight : 0)

    // One hue family for the whole card: its content colour tints the chips.
    readonly property color colCard: root.isSelected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    readonly property color colContent: root.isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface

    function activate(): bool {
        root.clicked();
        return true;
    }

    function runPrimary() {
        const primary = root.actionItems[0];
        if (primary && typeof primary.execute === "function")
            primary.execute();
    }

    function runSecondary(index: int) {
        const action = root.secondaryActions[index];
        if (action && typeof action.execute === "function")
            action.execute();
    }

    implicitHeight: root.cardHeight + root.bottomGap
    buttonRadius: Appearance.rounding.verylarge
    colBackground: "transparent"
    colBackgroundHover: "transparent"
    colRipple: "transparent"

    PointingHandInteraction {}
    onClicked: root.runPrimary()

    background: ClippingRectangle {
        id: card
        width: root.width
        height: root.cardHeight
        radius: Appearance.rounding.verylarge
        color: root.hovered && !root.isSelected ? Appearance.colors.colSurfaceContainerHighestHover : root.colCard

        Behavior on color {
            enabled: !root.animationsDisabled
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        // Ornament: big, clipped, quiet. It morphs with the selection
        // instead of moving.
        MaterialShape {
            readonly property real size: card.height * 1.9
            width: size
            height: size
            x: card.width - size * 0.42
            y: (card.height - size) / 2
            shape: root.isSelected ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.SoftBurst
            color: root.colContent
            opacity: root.isSelected ? 0.09 : 0.05
        }
    }

    RowLayout {
        id: content
        x: root.cardPadding
        y: root.cardPadding
        width: root.width - root.cardPadding * 2
        height: root.topBlockHeight
        spacing: 18

        // Apps carry their own silhouette; symbols and images get a rounded
        // square — the active shape — in primary.
        Item {
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
            Layout.alignment: Qt.AlignTop

            IconImage {
                anchors.centerIn: parent
                visible: root.iconType === LauncherSearchResult.IconType.System
                source: visible ? Quickshell.iconPath(root.entry?.iconName ?? "", "image-missing") : ""
                implicitSize: 64
                smooth: true
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                visible: root.iconType !== LauncherSearchResult.IconType.System
                radius: Appearance.rounding.large
                color: root.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.iconType !== LauncherSearchResult.IconType.Text
                        && !(root.iconType === LauncherSearchResult.IconType.Image && heroImage.status === Image.Ready)
                    text: root.iconType === LauncherSearchResult.IconType.Material
                        ? (root.entry?.iconName ?? "")
                        : (root.entry?.fallbackIconName || "search")
                    iconSize: 38
                    fill: 1
                    color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.iconType === LauncherSearchResult.IconType.Text
                    text: visible ? (root.entry?.iconName ?? "") : ""
                    font.pixelSize: 34
                    color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                }

                ClippingRectangle {
                    anchors.fill: parent
                    visible: root.iconType === LauncherSearchResult.IconType.Image && heroImage.status === Image.Ready
                    radius: parent.radius
                    color: "transparent"

                    StyledImage {
                        id: heroImage
                        anchors.fill: parent
                        sourceSize.width: 144
                        sourceSize.height: 144
                        source: root.iconType === LauncherSearchResult.IconType.Image ? (root.entry?.iconName ?? "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            // Overline: small, bold, spaced — the quiet label the big name
            // stands on.
            StyledText {
                id: overline
                Layout.fillWidth: true
                text: {
                    const label = Translation.tr("Top result");
                    return (root.itemType.length > 0 ? label + "  ·  " + root.itemType : label).toUpperCase();
                }
                color: root.isSelected ? root.colContent : Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                font.letterSpacing: 1.2
                elide: Text.ElideRight
            }

            StyledText {
                id: nameText
                Layout.fillWidth: true
                text: root.itemName
                color: root.colContent
                font.family: Appearance.font.family.main
                font.pixelSize: 30
                font.variableAxes: ({ "wght": 760, "wdth": 62, "ROND": 100 })
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                id: commentText
                Layout.fillWidth: true
                visible: root.itemComment.length > 0
                text: root.itemComment
                color: root.colContent
                opacity: 0.75
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
            }
        }

        // The primary action as a filled pill — the card's one loud control.
        RippleButton {
            id: primaryButton
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 52
            implicitWidth: primaryRow.implicitWidth + 36
            buttonRadius: root.isSelected ? Appearance.rounding.full : Appearance.rounding.large
            colBackground: root.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
            colBackgroundHover: root.isSelected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
            colRipple: root.isSelected ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

            PointingHandInteraction {}
            onClicked: root.runPrimary()

            RowLayout {
                id: primaryRow
                anchors.centerIn: parent
                spacing: 8

                StyledText {
                    Layout.maximumWidth: 120
                    text: root.verb
                    elide: Text.ElideRight
                    color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                }

                MaterialSymbol {
                    text: "keyboard_return"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3onSurface
                }
            }
        }
    }

    // One line of the result's own actions under the whole card width.
    Item {
        id: chipsBar
        x: root.cardPadding
        y: root.cardPadding + root.topBlockHeight + root.chipGap
        width: root.width - root.cardPadding * 2
        height: root.chipHeight
        visible: root.hasChips

        readonly property real chipsWidth: {
            let w = 0;
            for (let i = 0; i < chipRepeater.count; i++) {
                const c = chipRepeater.itemAt(i);
                if (c)
                    w += c.width + (i > 0 ? chipRow.spacing : 0);
            }
            return w;
        }
        readonly property int fittingCount: {
            let n = 0;
            for (let i = 0; i < chipRepeater.count; i++) {
                const c = chipRepeater.itemAt(i);
                if (c && c.fits)
                    n++;
            }
            return n;
        }
        // Decided on the full width, so reserving room for the hint can never
        // feed back into whether the hint is needed.
        readonly property bool overflows: root.hiddenActionCount > 0 || chipsWidth > width
        readonly property int moreCount: root.hiddenActionCount + root.secondaryActions.length - fittingCount

        Row {
            id: chipRow
            width: chipsBar.width - (chipsBar.overflows ? moreHint.implicitWidth + 10 : 0)
            height: parent.height
            spacing: 6

            Repeater {
                id: chipRepeater
                model: root.secondaryActions

                delegate: RippleButton {
                    id: chip
                    required property var modelData
                    required property int index

                    implicitHeight: root.chipHeight
                    // Chips past the bar's width hide instead of wrapping;
                    // they stay one Ctrl+K away and the hint counts them.
                    readonly property bool fits: chip.x + chip.width <= chipRow.width
                    opacity: fits ? 1 : 0
                    enabled: fits
                    implicitWidth: chipContent.implicitWidth + 22
                    buttonRadius: Appearance.rounding.full
                    // Tinted with the card's content colour (§2.3).
                    colBackground: ColorUtils.applyAlpha(root.colContent, 0.08)
                    colBackgroundHover: ColorUtils.applyAlpha(root.colContent, 0.16)
                    colRipple: ColorUtils.applyAlpha(root.colContent, 0.24)

                    PointingHandInteraction {}
                    onClicked: root.runSecondary(chip.index)

                    RowLayout {
                        id: chipContent
                        anchors.centerIn: parent
                        spacing: 6

                        Loader {
                            active: chip.modelData?.nativeIcon === true
                            visible: active
                            Layout.preferredWidth: active ? 16 : 0
                            Layout.preferredHeight: active ? 16 : 0
                            sourceComponent: IconImage {
                                source: Quickshell.iconPath(chip.modelData?.icon ?? "", "image-missing")
                                implicitSize: 16
                                smooth: true
                            }
                        }

                        MaterialSymbol {
                            visible: chip.modelData?.nativeIcon !== true && text.length > 0
                            text: chip.modelData?.icon ?? ""
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.colContent
                        }

                        StyledText {
                            Layout.maximumWidth: 140
                            elide: Text.ElideRight
                            text: chip.modelData?.name ?? ""
                            color: root.colContent
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            visible: Config.options.search.appearance.showKeyHints
                            text: "Alt " + String(chip.index + 1)
                            color: root.colContent
                            opacity: 0.55
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        StyledText {
            id: moreHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: chipsBar.overflows && chipsBar.moreCount > 0
            text: Translation.tr("+%1 · Ctrl K").arg(String(chipsBar.moreCount))
            color: root.colContent
            opacity: 0.6
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
        }
    }
}
