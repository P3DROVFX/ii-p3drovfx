import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland

RippleButton {
    id: root
    signal resultExecuted(string feedbackText)
    // The keybind capture row closed; the host hands focus back to the field.
    signal keybindCaptureFinished
    property var entry
    readonly property bool keepsOverviewOpen: entry?.keepOverviewOpen ?? false
    property string query
    property bool entryShown: entry?.shown ?? true
    property string itemType: entry?.type ?? Translation.tr("App")
    property string itemName: entry?.name ?? ""
    property var iconType: entry?.iconType
    property string iconName: entry?.iconName ?? ""
    property var itemExecute: entry?.execute
    property var fontType: switch (entry?.fontType) {
    case LauncherSearchResult.FontType.Monospace:
        return "monospace";
    case LauncherSearchResult.FontType.Normal:
        return "main";
    default:
        return "main";
    }
    property string itemClickActionName: entry?.verb ?? "Open"
    property string bigText: entry?.iconType === LauncherSearchResult.IconType.Text ? entry?.iconName ?? "" : ""
    property string materialSymbol: entry?.iconType === LauncherSearchResult.IconType.Material ? entry?.iconName ?? "" : ""
    property string cliphistRawString: entry?.rawValue ?? ""
    readonly property string fallbackIconName: entry?.fallbackIconName ?? ""
    property bool blurImage: entry?.blurImage ?? false
    readonly property bool hasInlineSwitch: entry?.controlKind === "switch"

    function formatMathResult(raw) {
        if (!raw)
            return {
                expression: "",
                value: ""
            };
        let parts = raw.split("=");
        if (parts.length >= 2) {
            let lhs = parts[0].trim();
            let rhs = parts.slice(1).join("=").trim();

            // Clean up LHS
            lhs = lhs.replace(/\s*\*\s*/g, " ").replace(/\bdeg\s*\*\s*/gi, "°").replace(/\bdeg\b/gi, "°");

            // Clean up RHS
            rhs = rhs.replace(/\s*\*\s*/g, " ").replace(/\bdeg\s*\*\s*/gi, "°").replace(/\bdeg\b/gi, "°").replace(/\bapprox\.\s*/gi, "≈ ");

            return {
                expression: lhs,
                value: rhs
            };
        }
        return {
            expression: "",
            value: raw
        };
    }

    property bool actionPanelOpen: false
    readonly property bool isBuiltinItem: (root.entry?.key?.startsWith("mock:") || root.entry?.key?.startsWith("shortcut:")) || !!root.entry?.isBuiltin
    readonly property var entryActions: entry?.actions ?? []
    readonly property bool hasCustomActions: root.entryActions.length > 0
    readonly property bool hasActions: root.hasCustomActions || root.itemType === Translation.tr("App")

    visible: root.entryShown
    // Hosts override this; it is the inset the row keeps from the panel edge.
    property int horizontalMargin: Appearance.sizes.elevationMargin
    property int buttonHorizontalPadding: 10
    property int buttonVerticalPadding: 8
    /**
     * AGENTS requires durations to come from `Appearance.animation.*` so the
     * user's animation multiplier applies to them. These row micro-transitions
     * have no matching token — they are deliberately shorter than
     * elementMoveFast, which is what makes a row feel responsive rather than
     * animated — so they take the multiplier directly instead of ignoring it,
     * which is the part that actually mattered.
     */
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"

    function scaledDuration(milliseconds: int): int {
        if (root.animationsDisabled)
            return 0;
        return Math.max(0, Math.round(milliseconds * (Appearance.animMultiplier ?? 1.0)));
    }

    property bool keyboardDown: false
    // Hosts that already animate their rows (the launcher list animates the
    // delegate) turn this off rather than stacking a second fade underneath.
    property bool animateEntrance: !root.animationsDisabled
    property real entryOpacity: root.animateEntrance ? 0.0 : 1.0
    property real entryTranslateY: root.animateEntrance ? -Appearance.sizes.elevationMargin : 0

    opacity: entryOpacity
    transform: Translate {
        y: root.entryTranslateY
    }

    property int listIndex: 0
    property int listCount: ListView.view ? ListView.view.count : 1
    property int listCurrentIndex: ListView.view ? ListView.view.currentIndex : -1

    property bool isFirst: listIndex === 0
    property bool isLast: listIndex === listCount - 1
    readonly property bool isSelected: listIndex === listCurrentIndex
    readonly property bool isAboveSelected: !root.isLast && listCurrentIndex === listIndex + 1 && listCurrentIndex !== -1
    readonly property bool isBelowSelected: !root.isFirst && listCurrentIndex === listIndex - 1 && listCurrentIndex !== -1
    readonly property real pillRadius: Math.min(height / 2, Appearance.rounding.large)
    readonly property int activeHIndex: root.actionPanelOpen ? root.actionSelectedIndex + 1 : 0

    /**
     * The selection pill, in this row's own coordinates.
     *
     * The launcher list slides a single pill between rows and binds these to
     * the part of it that lies over this row; a host that does not simply gets
     * a pill covering the selected row. Nothing here animates by itself, so a
     * row the cursor has left shows nothing the moment the pill is gone — no
     * trail. `selectionProgress` is how much of the row the pill covers, and
     * the foreground, icon circle and own corners read it, which keeps them in
     * step with the pill as it passes.
     */
    readonly property int selectionMotionDuration: root.animationsDisabled ? 0 : Appearance.animation.elementMoveFast.duration
    property real indicatorTop: 0
    property real indicatorBottom: root.isSelected ? root.height : 0
    // Only the row being selected draws the pill. Letting the row it left draw
    // its share too put a primary sliver on that row while the pill travelled,
    // which read as a leftover selection.
    readonly property real indicatorClipTop: root.isSelected ? Math.max(0, Math.min(root.height, root.indicatorTop)) : 0
    readonly property real indicatorClipBottom: root.isSelected ? Math.max(0, Math.min(root.height, root.indicatorBottom)) : 0
    readonly property real selectionProgress: root.height > 0
        ? Math.max(0, root.indicatorClipBottom - root.indicatorClipTop) / root.height
        : (root.isSelected ? 1 : 0)

    // The corners a neighbour opens towards the selected row. These are the
    // only animated selection values: they are shape, not position.
    property real neighbourTopOpen: root.isBelowSelected ? 1 : 0
    property real neighbourBottomOpen: root.isAboveSelected ? 1 : 0
    Behavior on neighbourTopOpen {
        enabled: !root.animationsDisabled
        NumberAnimation {
            duration: root.selectionMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    Behavior on neighbourBottomOpen {
        enabled: !root.animationsDisabled
        NumberAnimation {
            duration: root.selectionMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    /**
     * Arrival accent for the row the cursor lands on: the icon lifts slightly
     * past its size and settles, the text eases a few pixels in, and the
     * secondary line brightens. It is a one-shot on selection with an
     * overshooting spatial curve, and it marks state — which row just became
     * the target — rather than decorating a static row.
     */
    property real selectionAccent: root.isSelected ? 1 : 0
    Behavior on selectionAccent {
        enabled: !root.animationsDisabled
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    readonly property real topOpenProgress: Math.max(root.selectionProgress, root.neighbourTopOpen)
    readonly property real bottomOpenProgress: Math.max(root.selectionProgress, root.neighbourBottomOpen)

    function mixReal(from: real, to: real, progress: real): real {
        return from + (to - from) * progress;
    }

    readonly property real restTopRadius: root.isFirst
        ? Appearance.rounding.large
        : root.mixReal(Appearance.rounding.small, root.pillRadius, root.topOpenProgress)
    readonly property real restBottomRadius: root.isLast
        ? Appearance.rounding.large
        : root.mixReal(Appearance.rounding.small, root.pillRadius, root.bottomOpenProgress)

    readonly property real contractedWidth: 160
    readonly property real actionBtnSpacing: 4
    readonly property real actionBtnPadY: 4

    property var allActionItems: {
        // Lazy: only compute when this item is selected or the panel is open.
        // Avoids creating closures for every off-screen / unselected item.
        if (!root.isSelected && !root.actionPanelOpen)
            return [];
        return SearchResultActions.build(root.entry, {
            onDone: () => {
                root.actionPanelOpen = false;
            },
            onExecuted: feedbackText => root.resultExecuted(feedbackText),
            onCaptureKeybind: () => root.openKeybindCapture(),
            onCaptureAlias: () => root.openAliasCapture()
        });
    }

    property int actionSelectedIndex: 0

    /**
     * Keybind capture: More actions → Add keybind turns this row into a
     * recorder. Ctrl is fixed; the first letter pressed fills the slot and
     * locks it until Clear. Enter saves, Esc cancels.
     */
    property bool keybindCaptureOpen: false
    property string capturedLetter: ""
    property string captureNotice: ""
    readonly property string itemKeybindKey: LauncherSearch.keybindableKey(root.entry)
    readonly property var itemKeybind: root.itemKeybindKey.length > 0 ? LauncherSearch.keybindForKey(root.itemKeybindKey) : null
    readonly property string captureHint: {
        if (root.captureNotice.length > 0)
            return root.captureNotice;
        if (root.capturedLetter.length === 0)
            return Translation.tr("Press a letter · Esc cancels");
        const conflict = LauncherSearch.keybindForLetter(root.capturedLetter);
        if (conflict && conflict.key !== root.itemKeybindKey)
            return Translation.tr("Replaces %1 · Enter saves").arg(String(conflict.name ?? ""));
        return Translation.tr("Enter saves · Esc cancels");
    }

    function openKeybindCapture() {
        root.actionPanelOpen = false;
        root.aliasCaptureOpen = false;
        root.capturedLetter = String(root.itemKeybind?.letter ?? "");
        root.captureNotice = "";
        root.keybindCaptureOpen = true;
        root.forceActiveFocus();
    }

    function closeKeybindCapture() {
        if (!root.keybindCaptureOpen)
            return;
        root.keybindCaptureOpen = false;
        root.captureNotice = "";
        root.keybindCaptureFinished();
    }

    function saveKeybindCapture() {
        if (root.capturedLetter.length === 0) {
            root.captureNotice = Translation.tr("Press a letter first");
            return;
        }
        if (LauncherSearch.setResultKeybind(root.entry, root.capturedLetter))
            root.resultExecuted(Translation.tr("Ctrl+%1 opens %2").arg(root.capturedLetter.toUpperCase()).arg(root.itemName));
        root.closeKeybindCapture();
    }

    /**
     * Alias capture: More actions → Add alias uses the same row, with a text
     * field where the keybind recorder has its letter slot.
     */
    property bool aliasCaptureOpen: false
    property string aliasText: ""
    property string aliasNotice: ""
    readonly property string aliasHint: root.aliasNotice.length > 0
        ? root.aliasNotice
        : Translation.tr("Type the alias · Enter saves · Esc cancels")
    readonly property string activeCaptureNotice: root.aliasCaptureOpen ? root.aliasNotice : root.captureNotice

    function openAliasCapture() {
        root.actionPanelOpen = false;
        root.keybindCaptureOpen = false;
        root.aliasText = String(LauncherSearch.aliasForResult(root.entry)?.alias ?? "");
        aliasInput.text = root.aliasText;
        root.aliasNotice = "";
        root.aliasCaptureOpen = true;
        Qt.callLater(() => {
            aliasInput.forceActiveFocus();
            aliasInput.selectAll();
        });
    }

    function closeAliasCapture() {
        if (!root.aliasCaptureOpen)
            return;
        root.aliasCaptureOpen = false;
        root.aliasNotice = "";
        root.keybindCaptureFinished();
    }

    function saveAliasCapture() {
        const alias = root.aliasText.trim();
        const error = LauncherSearch.saveAliasForResult(root.entry, alias);
        if (error.length > 0) {
            root.aliasNotice = error;
            return;
        }
        root.resultExecuted(Translation.tr("“%1” now opens %2").arg(alias).arg(root.itemName));
        root.closeAliasCapture();
    }

    function clearActiveCapture() {
        if (root.aliasCaptureOpen) {
            root.aliasText = "";
            aliasInput.text = "";
            root.aliasNotice = "";
            aliasInput.forceActiveFocus();
            return;
        }
        root.capturedLetter = "";
        root.captureNotice = "";
        root.forceActiveFocus();
    }

    onIsSelectedChanged: {
        if (!root.isSelected) {
            root.closeKeybindCapture();
            root.closeAliasCapture();
        }
    }

    property real normalHeight: 52
    readonly property real rowHeight: 52
    onActionPanelOpenChanged: {
        if (actionPanelOpen) {
            normalHeight = root.height > 0 ? root.height : contentRow.implicitHeight + buttonVerticalPadding * 2;
        }
    }

    /**
     * The Ctrl+K panel is one progress value.
     *
     * The width and position Behaviors used to be enabled from
     * `onActionPanelOpenChanged` — which runs after the bindings it was meant
     * to animate had already jumped, so the panel snapped open. The row now
     * shrinks and the actions slide in from its trailing edge on this value;
     * the geometry itself stays a plain binding of the row's live width.
     */
    property real actionProgress: root.actionPanelOpen ? 1 : 0
    Behavior on actionProgress {
        enabled: !root.animationsDisabled
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    // Where the row scrolls to keep the chosen action in view once open. It
    // uses the contracted width, not the animating one, so it is stable while
    // the panel opens and only moves when the chosen action changes.
    readonly property real actionOpenX: {
        let btnX = root.contractedWidth + root.actionBtnSpacing;
        for (let i = 0; i < root.actionSelectedIndex; i++) {
            const btn = actionRepeater.itemAt(i);
            btnX += (btn ? btn.width : 0) + root.actionBtnSpacing;
        }
        const selBtn = actionRepeater.itemAt(root.actionSelectedIndex);
        const selRight = btnX + (selBtn ? selBtn.width : 0);
        return Math.min(root.horizontalMargin, root.width - 4 - selRight);
    }
    property real actionScrollX: root.actionOpenX
    Behavior on actionScrollX {
        enabled: root.actionPanelOpen && !root.animationsDisabled
        NumberAnimation {
            duration: root.selectionMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    readonly property real actionTrailingRadius: (root.activeHIndex === 0 || root.activeHIndex === 1) ? root.pillRadius : Appearance.rounding.small
    property real animatedActionTrailingRadius: root.actionTrailingRadius
    Behavior on animatedActionTrailingRadius {
        enabled: root.actionPanelOpen && !root.animationsDisabled
        NumberAnimation {
            duration: root.selectionMotionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    function executeSelectedAction() {
        if (actionSelectedIndex >= 0 && actionSelectedIndex < allActionItems.length)
            allActionItems[actionSelectedIndex].execute();
    }

    implicitHeight: root.actionPanelOpen ? normalHeight : root.rowHeight
    implicitWidth: contentRow.implicitWidth + root.buttonHorizontalPadding * 2

    Behavior on implicitHeight {
        enabled: !root.animationsDisabled
        NumberAnimation {
            duration: root.scaledDuration(250)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    buttonRadius: 0

    // Resting surface only. The selected state is drawn by `selectionIndicator`, so
    // this no longer flips to primary and back on every cursor move.
    colBackground: root.isBuiltinItem ? ((root.down || root.keyboardDown) ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colTertiaryContainer) : ((root.down || root.keyboardDown) ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHigh)
    colBackgroundHover: root.isBuiltinItem ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colPrimaryContainerActive
    readonly property color colRestForeground: root.isBuiltinItem ? Appearance.colors.colOnTertiaryContainer : Appearance.m3colors.m3onSurface
    readonly property color colRestSubtext: root.isBuiltinItem ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSubtext
    // Foreground follows the fill as it grows underneath, on the same progress.
    property color colForeground: ColorUtils.mix(Appearance.colors.colOnPrimary, root.colRestForeground, root.selectionProgress)
    property color colSubtextForeground: ColorUtils.mix(Appearance.colors.colOnPrimary, root.colRestSubtext, root.selectionProgress)

    readonly property string highlightPrefix: `<u><font color="${Appearance.colors.colPrimary}">`
    readonly property string highlightSuffix: `</font></u>`
    /**
     * Underline the query inside a result name.
     *
     * Only the first contiguous fuzzy-match run is emphasized. Highlighting
     * every later island made long names look like confetti and obscured the
     * suffix that actually distinguishes similarly named applications.
     */
    function highlightContent(content, query) {
        if (!query || query.length === 0 || content === query || root.fontType === "monospace")
            return StringUtils.escapeHtml(content);

        const contentLower = content.toLowerCase();
        const queryLower = query.toLowerCase();
        let runStart = -1;
        let runEnd = -1;
        let queryIndex = 0;

        for (let i = 0; i < content.length; i++) {
            const matches = queryIndex < query.length && contentLower[i] === queryLower[queryIndex];
            if (matches) {
                if (runStart === -1)
                    runStart = i;
                queryIndex++;
            } else if (runStart !== -1) {
                runEnd = i;
                break;
            }
        }
        if (runStart === -1)
            return StringUtils.escapeHtml(content);
        if (runEnd === -1)
            runEnd = content.length;
        return StringUtils.escapeHtml(content.slice(0, runStart))
            + root.highlightPrefix
            + StringUtils.escapeHtml(content.slice(runStart, runEnd))
            + root.highlightSuffix
            + StringUtils.escapeHtml(content.slice(runEnd));
    }

    property string displayContent: {
        // Skip highlight computation when selected — text shows itemName directly
        if (root.isSelected)
            return "";
        return highlightContent(root.itemName, root.query);
    }

    property list<string> urls: {
        if (!root.itemName)
            return [];
        const urlRegex = /https?:\/\/[^\s<>"{}|\\^`[\]]+/gi;
        const matches = root.itemName?.match(urlRegex)?.filter(url => !url.includes("…"));
        return matches ? matches : [];
    }

    property string contentType: entry?.category ?? ""

    PointingHandInteraction {}

    background: Rectangle {
        id: bgRect
        anchors.fill: root
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        color: "transparent"
        antialiasing: true
        clip: true

        // Already animated through the open progress values; a Behavior here
        // would restart on every frame of that motion and lag behind it.
        topLeftRadius: root.restTopRadius
        topRightRadius: topLeftRadius
        bottomLeftRadius: root.restBottomRadius
        bottomRightRadius: bottomLeftRadius

        Row {
            id: slideRow
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: root.actionBtnSpacing

            x: root.mixReal(root.horizontalMargin, root.actionScrollX, root.actionProgress)

            Rectangle {
                id: itemRect
                width: root.mixReal(bgRect.width - root.horizontalMargin * 2, root.contractedWidth, root.actionProgress)
                height: slideRow.height
                y: 0
                topLeftRadius: bgRect.topLeftRadius
                topRightRadius: root.mixReal(bgRect.topRightRadius, root.animatedActionTrailingRadius, root.actionProgress)
                bottomLeftRadius: bgRect.bottomLeftRadius
                bottomRightRadius: root.mixReal(bgRect.bottomRightRadius, root.animatedActionTrailingRadius, root.actionProgress)
                // The resting surface never changes colour on selection: the
                // sliding pill passes over it instead.
                color: root.colBackground
                clip: true
                antialiasing: true

                Behavior on color {
                    enabled: !root.animationsDisabled
                    ColorAnimation {
                        duration: root.scaledDuration(90)
                    }
                }

                /**
                 * The slice of the list's selection pill that lies over this row.
                 *
                 * An edge of the pill that is inside the row is the pill's own
                 * rounded end; an edge cut by the row's border takes the row's
                 * corner instead, so the pill never paints past the row's shape
                 * while it slides through the gap to the next one.
                 */
                Rectangle {
                    id: selectionIndicator
                    readonly property real span: Math.max(0, root.indicatorClipBottom - root.indicatorClipTop)
                    readonly property real endRadius: Math.min(root.pillRadius, span / 2)
                    readonly property bool enteredFromTop: root.indicatorTop <= 0.5
                    readonly property bool exitsAtBottom: root.indicatorBottom >= itemRect.height - 0.5
                    visible: span > 0.5
                    x: 0
                    y: root.indicatorClipTop
                    width: itemRect.width
                    height: span
                    topLeftRadius: Math.min(enteredFromTop ? itemRect.topLeftRadius : endRadius, span / 2)
                    topRightRadius: Math.min(enteredFromTop ? itemRect.topRightRadius : endRadius, span / 2)
                    bottomLeftRadius: Math.min(exitsAtBottom ? itemRect.bottomLeftRadius : endRadius, span / 2)
                    bottomRightRadius: Math.min(exitsAtBottom ? itemRect.bottomRightRadius : endRadius, span / 2)
                    color: (root.down || root.keyboardDown) ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimary
                    antialiasing: true
                }

                MouseArea {
                    anchors.fill: parent
                    visible: root.actionPanelOpen
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.actionPanelOpen = false
                }

                RowLayout {
                    id: contentRow
                    spacing: root.actionPanelOpen ? 6 : 10
                    anchors.fill: parent
                    anchors.leftMargin: root.buttonHorizontalPadding
                    anchors.rightMargin: root.buttonHorizontalPadding

                    Item {
                        id: iconContainer
                        Layout.preferredWidth: iconVisible ? 36 : 0
                        Layout.preferredHeight: 36
                        visible: iconVisible
                        readonly property bool iconVisible: root.iconType !== LauncherSearchResult.IconType.None
                        // Lifts past its size on the overshooting accent curve and
                        // settles at a slightly larger resting size while selected.
                        transform: Scale {
                            origin.x: iconContainer.width / 2
                            origin.y: iconContainer.height / 2
                            xScale: 1 + 0.08 * root.selectionAccent
                            yScale: 1 + 0.08 * root.selectionAccent
                        }

                        // A circle that also masks the icon. Application icons
                        // fill almost all of it, so a square icon with no
                        // rounding of its own has its corners cut to the circle
                        // instead of poking out past it.
                        ClippingRectangle {
                            anchors.fill: parent
                            visible: root.iconType === LauncherSearchResult.IconType.System
                            radius: width / 2
                            color: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colSurfaceContainerHighest, root.actionPanelOpen ? 1 : root.selectionProgress)

                            IconImage {
                                source: Quickshell.iconPath(root.iconName, "image-missing")
                                anchors.centerIn: parent
                                implicitSize: Math.round(parent.width * 0.84)
                                smooth: true
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.iconType === LauncherSearchResult.IconType.Material
                                || (root.iconType === LauncherSearchResult.IconType.Image && resultImage.status !== Image.Ready)
                            text: root.iconType === LauncherSearchResult.IconType.Image
                                ? (root.fallbackIconName.length > 0 ? root.fallbackIconName : "link")
                                : root.materialSymbol
                            iconSize: 26
                            fill: root.isSelected ? 1.0 : 0.0
                            color: root.colForeground
                            Behavior on iconSize {
                                enabled: !root.animationsDisabled
                                NumberAnimation {
                                    duration: root.scaledDuration(150)
                                }
                            }
                        }

                        // Rounded so a photo reads as part of the row rather than
                        // a rectangle dropped into it.
                        ClippingRectangle {
                            anchors.centerIn: parent
                            implicitWidth: 32
                            implicitHeight: 32
                            visible: root.iconType === LauncherSearchResult.IconType.Image
                                && resultImage.status === Image.Ready
                            color: "transparent"
                            radius: Appearance.rounding.verysmall

                            StyledImage {
                                id: resultImage
                                anchors.fill: parent
                                // Without a source size Qt decodes the file at full
                                // resolution to paint 32 pixels — a wallpaper hit
                                // would cost tens of megabytes per row.
                                sourceSize.width: 64
                                sourceSize.height: 64
                                visible: root.iconType === LauncherSearchResult.IconType.Image
                                source: visible ? root.iconName : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                        }

                        Item {
                            anchors.fill: parent
                            visible: root.iconType === LauncherSearchResult.IconType.Text

                            MaterialShape {
                                anchors.fill: parent
                                shape: MaterialShape.Shape.Sunny
                                color: root.isSelected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                                Behavior on color {
                                    enabled: !root.animationsDisabled
                                    ColorAnimation {
                                        duration: root.scaledDuration(80)
                                    }
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: root.bigText
                                font.pixelSize: root.actionPanelOpen ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.normal
                                color: root.isSelected ? Appearance.colors.colOnPrimaryContainer : root.colForeground
                            }
                        }
                    }

                    Rectangle {
                        width: 14
                        height: 14
                        radius: Appearance.rounding.full
                        color: root.itemName || "transparent"
                        visible: root.contentType === "hex-color" && !root.actionPanelOpen
                    }

                    ColumnLayout {
                        id: contentColumn
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0
                        // Swapped for the compact name halfway through the slide,
                        // when the row is already too narrow to read either.
                        visible: root.actionProgress < 0.5
                        // The text eases in beside the lifted icon.
                        transform: Translate {
                            x: 3 * root.selectionAccent
                        }

                        RowLayout {
                            id: titleRow
                            visible: !root.entry?.isMath
                            Layout.fillWidth: true
                            Rectangle {
                                implicitWidth: activeText.implicitHeight
                                implicitHeight: activeText.implicitHeight
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colPrimary
                                visible: itemName == Quickshell.clipboardText && root.cliphistRawString
                                MaterialSymbol {
                                    id: activeText
                                    anchors.centerIn: parent
                                    text: "check"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.m3colors.m3onPrimary
                                }
                            }

                            // Visible only when there is a glyph to draw. Apps carry
                            // their type as the category, which maps to no glyph:
                            // an empty but visible symbol still took its width in
                            // this row and pushed every app's name to the right of
                            // its own description.
                            MaterialSymbol {
                                visible: iconText !== ""
                                text: iconText
                                readonly property string iconText: {
                                    switch (root.contentType) {
                                    case "url":
                                        return "link";
                                    case "email":
                                        return "alternate_email";
                                    case "phone":
                                        return "phone";
                                    case "json":
                                        return "data_object";
                                    case "filepath":
                                        return "folder_open";
                                    case "markdown":
                                        return "markdown";
                                    case "number":
                                        return "tag";
                                    case "multiline":
                                        return "notes";
                                    default:
                                        return "";
                                    }
                                }
                                iconSize: Appearance.font.pixelSize.normal
                                color: root.colForeground
                            }

                            Repeater {
                                model: root.query == root.itemName ? [] : root.urls
                                Favicon {
                                    required property var modelData
                                    size: Math.max(1, titleRow.height)
                                    url: modelData
                                }
                            }

                            StyledText {
                                id: nameText
                                Layout.fillWidth: true
                                textFormat: Text.StyledText
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: (root.fontType === "monospace" || root.contentType === "json") ? Appearance.font.family.monospace : Appearance.font.family.main
                                color: root.colForeground
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideMiddle
                                text: root.isSelected ? root.itemName : root.displayContent
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            visible: (root.itemType && root.itemType != Translation.tr("App") && !root.entry?.isMath) || (!!root.entry?.comment && !root.entry?.isMath)

                            StyledText {
                                text: root.itemType
                                color: root.colSubtextForeground
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.main
                                opacity: root.isSelected ? 0.7 : (root.isBuiltinItem ? 1.0 : 0.7)
                                visible: root.itemType && root.itemType != Translation.tr("App") && !root.entry?.isMath
                            }

                            StyledText {
                                text: "•"
                                color: root.colSubtextForeground
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                opacity: 0.5
                                visible: (root.itemType && root.itemType != Translation.tr("App") && !root.entry?.isMath) && (!!root.entry?.comment && !root.entry?.isMath)
                            }

                            StyledText {
                                text: root.entry?.comment ?? ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: root.colSubtextForeground
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.main
                                visible: !!root.entry?.comment && !root.entry?.isMath
                                // The secondary line brightens with the arrival accent.
                                opacity: 0.7 + 0.3 * Math.min(1, root.selectionAccent)
                            }
                        }

                        // Structured Math & Unit Conversion breakdown
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !!root.entry?.isMath
                            spacing: 4

                            StyledText {
                                text: Translation.tr("Math & Unit Converter")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                font.family: Appearance.font.family.main
                                opacity: 0.7
                            }

                            RowLayout {
                                spacing: 8
                                Layout.fillWidth: true

                                // Input Expression
                                StyledText {
                                    text: {
                                        let parsed = root.formatMathResult(root.itemName);
                                        return parsed.expression || root.query;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.monospace
                                    color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                }

                                // Elegant Arrow Indicator
                                MaterialSymbol {
                                    text: "arrow_forward"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                }

                                // Evaluated Result
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        let parsed = root.formatMathResult(root.itemName);
                                        return parsed.value;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.monospace
                                    font.bold: true
                                    color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                }
                            }
                        }

                        Loader {
                            active: root.cliphistRawString && Cliphist.entryIsImage(root.cliphistRawString)
                            sourceComponent: CliphistImage {
                                Layout.fillWidth: true
                                entry: root.cliphistRawString
                                maxWidth: contentColumn.width
                                maxHeight: 140
                                blur: root.blurImage
                            }
                        }

                    }

                    StyledText {
                        visible: root.actionProgress >= 0.5
                        Layout.fillWidth: true
                        text: root.itemName
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.main
                        font.weight: Font.Medium
                        color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideMiddle
                    }

                    Item {
                        id: actionIndicator
                        readonly property bool shouldShow: root.isSelected && !root.actionPanelOpen && !root.hasInlineSwitch && root.allActionItems.length > 1
                        visible: (shouldShow || indicatorAnim.running) && !root.actionPanelOpen
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 44
                        implicitHeight: 16
                        opacity: shouldShow ? 1.0 : 0.0
                        // Slides in from the trailing edge as it appears.
                        transform: Translate {
                            x: (1 - actionIndicator.opacity) * Appearance.sizes.elevationMargin
                        }
                        Behavior on opacity {
                            enabled: !root.animationsDisabled
                            NumberAnimation {
                                id: indicatorAnim
                                duration: root.scaledDuration(100)
                                easing.type: Easing.OutQuad
                            }
                        }
                        KeyHint {
                            anchors.centerIn: parent
                            keys: ["Ctrl", "K"]
                            surface: root.selectionProgress > 0.5 ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                            onSurface: root.selectionProgress > 0.5 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }
                    }

                    KeyHint {
                        visible: !root.actionPanelOpen && (root.entry?.keyHints?.length ?? 0) > 0
                        Layout.alignment: Qt.AlignVCenter
                        keys: root.entry?.keyHints ?? []
                        surface: root.selectionProgress > 0.5 ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                        onSurface: root.selectionProgress > 0.5 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    }

                    // The user's own Ctrl+letter for this result.
                    KeyHint {
                        visible: !!root.itemKeybind && LauncherSearch.resultKeybindsEnabled && !root.actionPanelOpen && !root.keybindCaptureOpen
                        Layout.alignment: Qt.AlignVCenter
                        keys: ["Ctrl", String(root.itemKeybind?.letter ?? "").toUpperCase()]
                        surface: root.selectionProgress > 0.5 ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                        onSurface: root.selectionProgress > 0.5 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    }

                    StyledSwitch {
                        visible: root.hasInlineSwitch && !root.actionPanelOpen
                        Layout.alignment: Qt.AlignVCenter
                        sizeScale: 0.62
                        checked: Boolean(root.entry?.controlValue)
                        onToggled: {
                            if (typeof root.itemExecute === "function") {
                                root.itemExecute();
                                root.resultExecuted(String(root.entry?.feedbackText ?? ""));
                            }
                        }
                    }
                }
            }

            Repeater {
                id: actionRepeater
                model: root.allActionItems

                delegate: Rectangle {
                    id: actionBtn
                    required property var modelData
                    required property int index
                    readonly property bool isActionSelected: root.actionSelectedIndex === index
                    readonly property int hIdx: index + 1
                    readonly property bool isBtnActive: root.isSelected && isActionSelected

                    width: actionBtnContent.implicitWidth + 24
                    height: slideRow.height
                    y: 0
                    topLeftRadius: hIdx === root.activeHIndex || (hIdx - 1) === root.activeHIndex ? root.pillRadius : Appearance.rounding.small
                    bottomLeftRadius: topLeftRadius
                    topRightRadius: hIdx === root.allActionItems.length ? root.pillRadius : (hIdx === root.activeHIndex || (hIdx + 1) === root.activeHIndex ? root.pillRadius : Appearance.rounding.small)
                    bottomRightRadius: topRightRadius

                    color: isBtnActive ? Appearance.colors.colPrimaryContainer : (root.isSelected && actionBtnMa.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighest)
                    // Carried in by the shrinking row, plus a short slide of
                    // their own so they arrive from the trailing edge.
                    visible: root.actionProgress > 0.01
                    opacity: Math.min(1, root.actionProgress * 1.5)
                    transform: Translate {
                        x: (1 - root.actionProgress) * Appearance.sizes.elevationMargin * 3
                    }

                    Behavior on color {
                        enabled: !root.animationsDisabled
                        ColorAnimation {
                            duration: root.scaledDuration(80)
                        }
                    }
                    Behavior on topLeftRadius {
                        enabled: !root.animationsDisabled
                        NumberAnimation {
                            duration: root.scaledDuration(140)
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on topRightRadius {
                        enabled: !root.animationsDisabled
                        NumberAnimation {
                            duration: root.scaledDuration(140)
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on bottomLeftRadius {
                        enabled: !root.animationsDisabled
                        NumberAnimation {
                            duration: root.scaledDuration(140)
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on bottomRightRadius {
                        enabled: !root.animationsDisabled
                        NumberAnimation {
                            duration: root.scaledDuration(140)
                            easing.type: Easing.OutQuad
                        }
                    }

                    MouseArea {
                        id: actionBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: actionBtn.modelData.execute()
                        onEntered: root.actionSelectedIndex = actionBtn.index
                    }

                    RowLayout {
                        id: actionBtnContent
                        anchors.centerIn: parent
                        spacing: 8
                        Layout.leftMargin: 6
                        Layout.rightMargin: 10

                        Item {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36

                            MaterialShape {
                                anchors.fill: parent
                                shape: actionBtn.isBtnActive ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Cookie7Sided
                                color: actionBtn.isBtnActive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                Behavior on color {
                                    enabled: !root.animationsDisabled
                                    ColorAnimation {
                                        duration: root.scaledDuration(80)
                                    }
                                }
                            }

                            IconImage {
                                anchors.centerIn: parent
                                visible: actionBtn.modelData.nativeIcon ?? false
                                source: visible ? Quickshell.iconPath(actionBtn.modelData.icon, "image-missing") : ""
                                implicitSize: 22
                                smooth: true
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !(actionBtn.modelData.nativeIcon ?? false)
                                text: actionBtn.modelData.icon || "play_arrow"
                                iconSize: 22
                                fill: actionBtn.isBtnActive ? 1 : 0
                                color: actionBtn.isBtnActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnSurfaceVariant
                                Behavior on color {
                                    enabled: !root.animationsDisabled
                                    ColorAnimation {
                                        duration: root.scaledDuration(80)
                                    }
                                }
                            }
                        }

                        StyledText {
                            text: actionBtn.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.main
                            font.weight: Font.Medium
                            color: actionBtn.isBtnActive ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                            Behavior on color {
                                enabled: !root.animationsDisabled
                                ColorAnimation {
                                    duration: root.scaledDuration(80)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Keybind capture row ──
    Rectangle {
        id: keybindCapture
        anchors.fill: parent
        anchors.leftMargin: root.horizontalMargin
        anchors.rightMargin: root.horizontalMargin
        z: 20
        visible: root.keybindCaptureOpen || root.aliasCaptureOpen
        radius: root.pillRadius
        color: Appearance.colors.colSecondaryContainer

        // Swallows clicks, so the result underneath never runs.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.aliasCaptureOpen ? aliasInput.forceActiveFocus() : root.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Appearance.sizes.elevationMargin * 1.2
            anchors.rightMargin: Appearance.sizes.elevationMargin * 0.6
            spacing: Appearance.sizes.elevationMargin

            MaterialSymbol {
                text: root.aliasCaptureOpen ? "label" : "keyboard_command_key"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.aliasCaptureOpen
                        ? Translation.tr("Alias for %1").arg(root.itemName)
                        : Translation.tr("Keybind for %1").arg(root.itemName)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.aliasCaptureOpen ? root.aliasHint : root.captureHint
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.activeCaptureNotice.length > 0 ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
                    opacity: root.activeCaptureNotice.length > 0 ? 1 : 0.75
                }
            }

            // The alias field takes the letter slot's place.
            Rectangle {
                visible: root.aliasCaptureOpen
                implicitWidth: Math.max(Appearance.sizes.elevationMargin * 12, aliasInput.contentWidth + Appearance.sizes.elevationMargin * 2)
                implicitHeight: Appearance.sizes.elevationMargin * 3
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerHighest

                TextInput {
                    id: aliasInput
                    anchors.fill: parent
                    anchors.leftMargin: Appearance.sizes.elevationMargin * 0.7
                    anchors.rightMargin: Appearance.sizes.elevationMargin * 0.7
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    maximumLength: 32
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                    selectionColor: Appearance.colors.colPrimary
                    selectedTextColor: Appearance.colors.colOnPrimary
                    onTextEdited: {
                        root.aliasText = text;
                        root.aliasNotice = "";
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.closeAliasCapture();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.saveAliasCapture();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
                                || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                            event.accepted = true;
                        }
                    }
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Appearance.sizes.elevationMargin * 0.7
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.aliasText.length === 0
                    text: Translation.tr("alias")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            // Ctrl is fixed; the letter slot waits for the press.
            RowLayout {
                visible: root.keybindCaptureOpen
                spacing: 4

                Rectangle {
                    implicitWidth: ctrlKeyLabel.implicitWidth + Appearance.sizes.elevationMargin * 1.2
                    implicitHeight: Appearance.sizes.elevationMargin * 3
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerHighest

                    StyledText {
                        id: ctrlKeyLabel
                        anchors.centerIn: parent
                        text: "Ctrl"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                    }
                }
                StyledText {
                    text: "+"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }
                Rectangle {
                    implicitHeight: Appearance.sizes.elevationMargin * 3
                    implicitWidth: Math.max(implicitHeight, letterKeyLabel.implicitWidth + Appearance.sizes.elevationMargin * 1.2)
                    radius: Appearance.rounding.small
                    color: root.capturedLetter.length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest

                    StyledText {
                        id: letterKeyLabel
                        anchors.centerIn: parent
                        text: root.capturedLetter.length > 0 ? root.capturedLetter.toUpperCase() : "?"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.capturedLetter.length > 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                    }
                }
            }

            RippleButton {
                implicitWidth: clearKeyLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: Appearance.sizes.elevationMargin * 3.2
                buttonRadius: Appearance.rounding.full
                enabled: root.aliasCaptureOpen ? root.aliasText.length > 0 : root.capturedLetter.length > 0
                opacity: enabled ? 1 : 0.45
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.clearActiveCapture()

                StyledText {
                    id: clearKeyLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Clear")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                }
            }

            RippleButton {
                implicitWidth: doneKeyLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: Appearance.sizes.elevationMargin * 3.2
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.aliasCaptureOpen ? root.saveAliasCapture() : root.saveKeybindCapture()

                StyledText {
                    id: doneKeyLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Done")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    onClicked: {
        if (root.actionPanelOpen) {
            root.actionPanelOpen = false;
            return;
        }

        const isSystemControl = root.entry?.key?.startsWith("sys:");
        const cmdKey = isSystemControl ? root.entry.key.slice(4) : "";
        const isConfirming = isSystemControl && root.entry?.requiresConfirmation
            && LauncherSearch.confirmKey !== cmdKey;
        const isModeSwitch = root.keepsOverviewOpen || (root.entry?.key?.startsWith("mock:") && root.entry?.key !== "mock:settings") || (root.entry?.key?.startsWith("shortcut:") && root.entry?.key !== "shortcut:openSettings") || root.itemType === Translation.tr("Folder Alias");

        if (!isConfirming && !isModeSwitch) {
            GlobalStates.overviewOpen = false;
        }
        root.itemExecute();
        root.resultExecuted(String(root.entry?.feedbackText ?? ""));
    }

    Keys.onPressed: event => {
        // The alias field normally takes its own keys; this catches the ones
        // that reach the row after a click moved focus off it.
        if (root.aliasCaptureOpen) {
            event.accepted = true;
            if (event.key === Qt.Key_Escape)
                root.closeAliasCapture();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.saveAliasCapture();
            else
                aliasInput.forceActiveFocus();
            return;
        }
        // While recording a keybind, every key belongs to the recorder.
        if (root.keybindCaptureOpen) {
            event.accepted = true;
            if (event.key === Qt.Key_Escape) {
                root.closeKeybindCapture();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.saveKeybindCapture();
            } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                root.capturedLetter = "";
                root.captureNotice = "";
            } else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z && root.capturedLetter.length === 0) {
                const letter = String.fromCharCode(event.key).toLowerCase();
                if (LauncherSearch.reservedKeybindLetters().indexOf(letter) !== -1) {
                    root.captureNotice = Translation.tr("Ctrl+%1 is reserved by Search").arg(letter.toUpperCase());
                } else {
                    root.capturedLetter = letter;
                    root.captureNotice = "";
                }
            }
            return;
        }
        if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
            const deleteAction = root.entry.actions.find(action => action.name == Translation.tr("Delete"));
            if (deleteAction)
                deleteAction.execute();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.actionPanelOpen) {
                root.executeSelectedAction();
            } else {
                root.keyboardDown = true;
                root.clicked();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.actionPanelOpen) {
            root.actionPanelOpen = false;
            event.accepted = true;
        } else if (root.actionPanelOpen && event.key === Qt.Key_Left) {
            root.actionSelectedIndex = Math.max(0, root.actionSelectedIndex - 1);
            event.accepted = true;
        } else if (root.actionPanelOpen && event.key === Qt.Key_Right) {
            root.actionSelectedIndex = Math.min(root.allActionItems.length - 1, root.actionSelectedIndex + 1);
            event.accepted = true;
        } else if (root.actionPanelOpen && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            root.actionPanelOpen = false;
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = false;
            event.accepted = true;
        }
    }

    SequentialAnimation {
        id: entryAnim
        running: false

        PauseAnimation {
            duration: root.animationsDisabled ? 0 : Math.max(0, Math.min(6, root.listIndex) * Appearance.animation.elementMoveFast.duration / 4)
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "entryOpacity"
                to: 1.0
                duration: root.animationsDisabled ? 0 : Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: root
                property: "entryTranslateY"
                to: 0
                duration: root.animationsDisabled ? 0 : Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    Component.onCompleted: {
        if (root.animateEntrance)
            entryAnim.start();
    }
}
