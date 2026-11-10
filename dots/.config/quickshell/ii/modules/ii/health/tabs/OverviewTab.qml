pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.health.components

/**
 * Overview: how many things need attention, as the one big number, and what they are.
 *
 * The hero is the page's single technique: a giant condensed digit beside a wide italic
 * caption, and the module's only clipped ornament. With nothing to report it steps down
 * to the pane colour and says so. Beside it, the findings in their severity colours;
 * under both, three vitals — memory pressure as the app's only sparkline, throttling and
 * the root filesystem.
 */
Item {
    id: root

    property double now: Date.now()
    property bool compact: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null
    property HealthAssistant assistant: null

    signal tabRequested(string tabId)

    readonly property bool sideBySide: root.layoutWidth >= HealthStyle.sideBySideMin
    readonly property var attention: HealthService.attention

    /// What the assistant is told about everything at once, at send time.
    function facts(): var {
        return {
            needAttention: root.attention.map(f => ({ id: f.id, kind: f.kind, title: HealthText.title(f), detail: HealthText.detail(f, Date.now()), data: f.data })),
            alsoKnown: root.info.slice(0, 8).map(f => HealthText.title(f))
        };
    }
    readonly property int count: HealthService.attentionCount
    readonly property var info: HealthService.findings.filter(f => !root.attention.includes(f) && !HealthService.isSnoozed(f))
    /// Folded groups under the list: what was snoozed, and what got fixed this week.
    property bool showSnoozed: false
    property bool showFixed: false
    readonly property var fixed: HealthService.resolved.slice().reverse().slice(0, 12)
    readonly property bool clear: root.count === 0
    readonly property bool loading: HealthService.enabled && !HealthService.synced && HealthService.findings.length === 0

    readonly property string pageSubtitle: !HealthService.running ? Translation.tr("Starting the checks…")
        : !HealthService.synced ? Translation.tr("Checking…")
        : root.clear ? Translation.tr("All clear")
        : HealthText.plural(root.count, Translation.tr("%1 needs attention"), Translation.tr("%1 need attention"))

    function primaryAction(): void {
        HealthService.rescan();
    }

    function showFinding(id): void {
        root.open(HealthService.finding(id));
    }

    function open(f): void {
        if (!f)
            return;
        if (f.kind === "crash") {
            HealthService.openFinding(f.id);
            return;
        }
        root.panels?.show(findingSheet, { findingId: f.id, assistant: root.assistant });
    }

    /// A card's click: the open card's second click closes its sheet.
    function toggle(f): void {
        if (f && root.panels?.open && root.panels.current?.findingId === f.id)
            root.panels.close();
        else
            root.open(f);
    }

    /// Keyboard, from the app: as on Services — ↑ ↓ (k j) open the previous or next
    /// card's sheet, Enter opens or closes it, a asks, s snoozes. Crash cards are
    /// skipped: they open on their own page.
    function handleNavKey(event): bool {
        const list = root.attention.concat(root.info.slice(0, 6)).filter(f => f.kind !== "crash");
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier) || list.length === 0)
            return false;
        const sheet = root.panels?.open ? root.panels.current : null;
        const cur = list.findIndex(f => f.id === String(sheet?.findingId ?? ""));
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            root.open(list[Math.min(list.length - 1, cur + 1)]);
            return true;
        case Qt.Key_Up:
        case Qt.Key_K:
            root.open(list[Math.max(0, cur - 1)]);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (cur >= 0)
                root.panels.close();
            else
                root.open(list[0]);
            return true;
        case Qt.Key_A:
            if (cur < 0 || typeof sheet?.askAssistant !== "function")
                return false;
            sheet.askAssistant();
            return true;
        case Qt.Key_S:
            if (cur < 0 || !sheet)
                return false;
            sheet.snoozeOpen = !sheet.snoozeOpen;
            return true;
        }
        return false;
    }

    Component {
        id: findingSheet
        FindingSheet {}
    }

    // Wide: the hero and the vitals on the left, the findings as their own scrolling
    // column on the right, so a long list never stretches the page under the hero.
    // Narrow: one scrolling column, the list between the hero and the vitals.
    Loader {
        anchors.fill: parent
        sourceComponent: root.sideBySide ? sideLayout : stackLayout
    }

    Component {
        id: sideLayout
        RowLayout {
            spacing: ClockStyle.paneGap

            StyledFlickable {
                id: leftFlick
                Layout.preferredWidth: Math.round((root.width - ClockStyle.paneGap) * 0.56)
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: leftColumn.implicitHeight + ClockStyle.gapHuge
                clip: true

                ColumnLayout {
                    id: leftColumn
                    width: leftFlick.width
                    spacing: ClockStyle.paneGap

                    QtHookOffer {
                        Layout.fillWidth: true
                    }
                    DumpOffer {
                        Layout.fillWidth: true
                    }
                    Hero {
                        Layout.fillWidth: true
                    }
                    Vitals {
                        Layout.fillWidth: true
                        availableWidth: leftFlick.width
                    }
                    HealthHistoryChart {
                        Layout.fillWidth: true
                    }
                }
            }

            AttentionList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                scrolling: true
            }
        }
    }

    Component {
        id: stackLayout
        StyledFlickable {
            id: flick
            contentWidth: width
            contentHeight: column.implicitHeight + ClockStyle.fabClearance
            clip: true

            ColumnLayout {
                id: column
                width: flick.width
                spacing: ClockStyle.paneGap

                QtHookOffer {
                    Layout.fillWidth: true
                }
                DumpOffer {
                    Layout.fillWidth: true
                }
                Hero {
                    Layout.fillWidth: true
                }
                AttentionList {
                    Layout.fillWidth: true
                }
                Vitals {
                    Layout.fillWidth: true
                    availableWidth: flick.width
                }
                HealthHistoryChart {
                    Layout.fillWidth: true
                }
            }
        }
    }

    // Once, the first time the helper runs without the pacman hook: recommended, so the
    // install is the filled button. Said in words before any password prompt.
    component QtHookOffer: Rectangle {
        visible: HealthService.offerQtHook
        implicitHeight: hookColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPrimaryContainer

        ColumnLayout {
            id: hookColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gapSmall

            RowLayout {
                spacing: ClockStyle.gapSmall
                StyledText {
                    text: HealthService.qtHookStatus === "outdated" ? Translation.tr("Update the pacman hook?") : Translation.tr("Install the pacman hook?")
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnPrimaryContainer
                }
                Rectangle {
                    implicitWidth: recommendedText.implicitWidth + ClockStyle.gap * 2
                    implicitHeight: recommendedText.implicitHeight + 4
                    radius: height / 2
                    color: ClockStyle.colPrimary
                    StyledText {
                        id: recommendedText
                        anchors.centerIn: parent
                        text: Translation.tr("Recommended")
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Bold
                        color: ClockStyle.colOnPrimary
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: HealthService.qtHookStatus === "outdated"
                    ? Translation.tr("The installed hook is from an older version of ii. The new one keeps warning when a Qt update leaves Quickshell needing a rebuild.")
                    : Translation.tr("After a Qt update, Quickshell needs a rebuild or the shell may not start. The hook says so during the update itself, while the shell still runs. It only reads and warns. Settings can remove it.")
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textSmall + 1
                color: ClockStyle.colOnPrimaryContainer
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: ClockStyle.gapSmall
                ClockButton {
                    variant: "text"
                    label: Translation.tr("Not now")
                    onClicked: HealthService.answerQtHookOffer(false)
                }
                ClockButton {
                    variant: "filled"
                    symbol: "package_2"
                    label: HealthService.qtHookStatus === "outdated" ? Translation.tr("Update, ask for my password") : Translation.tr("Install, ask for my password")
                    onClicked: HealthService.answerQtHookOffer(true)
                }
            }
        }
    }

    // Once, the first time the helper runs without dump access: the offer, said in
    // words before any password prompt.
    component DumpOffer: Rectangle {
        visible: HealthService.offerDumpAccess
        implicitHeight: offerColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colTertiaryContainer

        ColumnLayout {
            id: offerColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gapSmall

            StyledText {
                text: Translation.tr("Read crash dumps of system programs?")
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textLarge
                color: ClockStyle.colOnTertiaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Programs like fprintd run as root, and only root can read their dumps. Allowing your account lets you debug them here. A dump is a copy of a program's memory and can contain passwords or keys. They never leave this computer, and the assistant never sees them. Settings can revoke it any time.")
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textSmall + 1
                color: ClockStyle.colOnTertiaryContainer
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: ClockStyle.gapSmall
                ClockButton {
                    variant: "text"
                    label: Translation.tr("Not now")
                    onClicked: HealthService.answerDumpOffer(false)
                }
                ClockButton {
                    variant: "filled"
                    symbol: "lock_open"
                    label: Translation.tr("Allow, ask for my password")
                    onClicked: HealthService.answerDumpOffer(true)
                }
            }
        }
    }

    // ── Hero ────────────────────────────────────────────────────────────
    component Hero: Rectangle {
        id: hero

        readonly property color colContent: root.clear ? ClockStyle.colOnSurface : ClockStyle.colOnPrimaryContainer
        readonly property real digitSize: Math.round(Math.max(HealthStyle.heroDigitMin, Math.min(HealthStyle.heroDigitMax, hero.width * 0.3)))

        implicitHeight: Math.max(HealthStyle.heroMinHeight, heroColumn.implicitHeight + ClockStyle.cardPadding * 2 + 8)
        radius: ClockStyle.radiusExtraLarge
        color: root.clear ? ClockStyle.colPane : ClockStyle.colPrimaryContainer

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        StaggeredEntrance {
            index: 0
            active: !ClockStyle.reducedMotion
        }

        // The module's one ornament: a Sunny shape far larger than the tile, parked off
        // its right edge and cut by a mask of the tile so the rounded corners stay round.
        Item {
            id: ornament
            anchors.fill: parent
            visible: false

            MaterialShape {
                width: Math.round(hero.height * 1.6)
                height: width
                x: hero.width - width * 0.42
                y: (hero.height - height) / 2
                shapeString: root.clear ? "Cookie12Sided" : "Sunny"
                color: hero.colContent
            }
        }

        Rectangle {
            id: heroMask
            anchors.fill: parent
            radius: hero.radius
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: ornament
            maskEnabled: true
            maskSource: heroMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            opacity: 0.09
        }

        ColumnLayout {
            id: heroColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.cardPadding + 4
            }
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: root.clear ? Translation.tr("All clear") : Translation.tr("Needs attention")
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Black
                    font.letterSpacing: 1.2
                    font.capitalization: Font.AllUppercase
                    color: hero.colContent
                    opacity: 0.8
                }

                HealthAssistantButton {
                    visible: root.assistant !== null && root.assistant.allowed && !root.clear && HealthService.synced
                    assistant: root.assistant ?? placeholder
                    key: "overview"
                    label: Translation.tr("Explain everything with the assistant")
                    colIcon: hero.colContent
                    provider: () => root.facts()
                }
            }

            HealthAssistantPanel {
                Layout.fillWidth: true
                assistant: root.assistant ?? placeholder
                key: "overview"
                placeholder: Translation.tr("Ask about what needs attention")
                colCard: ClockStyle.colSecondaryContainer
                colOnCard: ClockStyle.colOnSecondaryContainer
                provider: () => root.facts()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapLarge

                StyledText {
                    visible: !root.clear
                    text: String(root.count)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ({ "wght": 800, "wdth": 30, "ROND": 100 })
                    font.pixelSize: hero.digitSize
                    color: hero.colContent
                    Layout.alignment: Qt.AlignBottom
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: root.clear ? 0 : hero.digitSize * 0.12
                    text: root.loading ? Translation.tr("Checking services,\ncrashes and disks…")
                        : root.clear ? Translation.tr("Nothing broke\nquietly")
                        : root.count === 1 ? Translation.tr("thing broke\nquietly")
                        : Translation.tr("things broke\nquietly")
                    font.family: ClockStyle.fontMain
                    font.variableAxes: HealthStyle.axesWideItalic
                    font.italic: true
                    font.pixelSize: Math.round(root.clear ? hero.digitSize * 0.42 : hero.digitSize * 0.2)
                    lineHeight: 0.95
                    color: hero.colContent
                    wrapMode: Text.Wrap
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 560
                text: HealthService.synced ? HealthText.summary(root.attention, root.now) : ""
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textNormal + 1
                color: hero.colContent
                opacity: 0.92
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapSmall
                spacing: ClockStyle.gapSmall
                visible: !root.clear

                Repeater {
                    model: ScriptModel {
                        values: root.attention.slice(0, 3)
                        objectProp: "id"
                    }

                    // Each opens its finding where the fix lives; nothing runs from here.
                    ClockChip {
                        required property var modelData
                        readonly property string name: String((modelData.kind === "crash" ? modelData.data?.name : (modelData.data?.unit ?? modelData.data?.mount)) ?? "")
                        symbol: modelData.kind === "crash" ? "bug_report" : HealthService.primaryFix(modelData) ? "build" : "open_in_new"
                        label: modelData.kind === "crash" ? Translation.tr("See the %1 crash").arg(name)
                            : name.length > 0 ? Translation.tr("Fix %1").arg(name) : HealthText.title(modelData)
                        colIdle: ColorUtils.applyAlpha(hero.colContent, 0.1)
                        colIdleHover: ColorUtils.applyAlpha(hero.colContent, 0.18)
                        colOnIdle: hero.colContent
                        onClicked: root.open(modelData)
                    }
                }
            }
        }
    }

    HealthAssistant {
        id: placeholder
    }

    // ── Attention list ──────────────────────────────────────────────────
    component AttentionList: ColumnLayout {
        id: att

        /// Scrolls on its own and fills the height it is given (the wide layout);
        /// otherwise it is as tall as its cards and the page scrolls.
        property bool scrolling: false

        spacing: ClockStyle.gapTiny

        StyledText {
            Layout.leftMargin: ClockStyle.gapTiny
            Layout.bottomMargin: ClockStyle.gapTiny
            text: root.attention.length > 0 ? Translation.tr("Needs attention") : Translation.tr("For your information")
            font.pixelSize: ClockStyle.textSmall
            font.weight: Font.Black
            font.letterSpacing: 1.0
            font.capitalization: Font.AllUppercase
            color: ClockStyle.colSubtext
            visible: root.attention.length > 0 || root.info.length > 0
        }

        StyledFlickable {
            id: attFlick
            Layout.fillWidth: true
            Layout.fillHeight: att.scrolling
            Layout.preferredHeight: att.scrolling ? -1 : cards.implicitHeight
            visible: cards.count > 0
            contentWidth: width
            // The page FAB sits over this column's bottom corner: the last card can
            // always scroll clear of it.
            contentHeight: cards.implicitHeight + (att.scrolling ? ClockStyle.fabClearance : 0)
            interactive: att.scrolling && contentHeight > height
            clip: att.scrolling

            Column {
                id: cards
                readonly property int count: cardRepeater.count + HealthService.snoozedFindings.length + root.fixed.length
                width: attFlick.width
                spacing: ClockStyle.gapTiny

                Repeater {
                    id: cardRepeater
                    // Any finding's update makes a new list: matched by id, cards update
                    // in place and only new ones enter.
                    model: ScriptModel {
                        values: root.attention.concat(root.info.slice(0, 6))
                        objectProp: "id"
                    }

                    FindingCard {
                        required property var modelData
                        required property int index
                        width: cards.width
                        finding: modelData
                        entranceIndex: index + 1
                    }
                }

                FoldHeader {
                    width: cards.width
                    visible: HealthService.snoozedFindings.length > 0
                    symbol: "snooze"
                    label: Translation.tr("Snoozed")
                    count: HealthService.snoozedFindings.length
                    open: root.showSnoozed
                    onFoldRequested: root.showSnoozed = !root.showSnoozed
                }
                Repeater {
                    model: ScriptModel {
                        values: root.showSnoozed ? HealthService.snoozedFindings : []
                        objectProp: "id"
                    }
                    FindingCard {
                        required property var modelData
                        width: cards.width
                        finding: modelData
                        opacity: 0.6
                    }
                }

                FoldHeader {
                    width: cards.width
                    visible: root.fixed.length > 0
                    symbol: "task_alt"
                    label: Translation.tr("Fixed recently")
                    count: root.fixed.length
                    open: root.showFixed
                    onFoldRequested: root.showFixed = !root.showFixed
                }
                Repeater {
                    model: root.showFixed ? root.fixed : []
                    FixedRow {
                        required property var modelData
                        width: cards.width
                        entry: modelData
                    }
                }
            }
        }

        Item {
            // Keeps the header at the top when the list is empty in the wide layout.
            Layout.fillHeight: att.scrolling && cards.count === 0
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ClockStyle.gapHuge
            visible: HealthService.synced && root.attention.length === 0 && root.info.length === 0
            symbol: "verified"
            shape: "Clover8Leaf"
            shapeSize: ClockStyle.emptyShapeSmall
            title: Translation.tr("Nothing to look at")
            subtitle: Translation.tr("New problems show up here and on the island.")
        }
    }

    // A folded group's line: its name and count, the chevron that opens it.
    component FoldHeader: RippleButton {
        id: fold
        property string symbol: ""
        property string label: ""
        property int count: 0
        property bool open: false
        // Not `toggled`: the button already has a signal by that name.
        signal foldRequested()

        implicitHeight: 44
        buttonRadius: ClockStyle.radiusLarge
        colBackground: "transparent"
        colBackgroundHover: ClockStyle.colSurfaceHover
        colRipple: ClockStyle.colSurfaceActive
        onClicked: fold.foldRequested()

        contentItem: RowLayout {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: ClockStyle.gapLarge
                rightMargin: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            MaterialSymbol {
                text: fold.symbol
                iconSize: ClockStyle.iconSmall
                color: ClockStyle.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: `${fold.label} · ${fold.count}`
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Bold
                color: ClockStyle.colSubtext
            }
            MaterialSymbol {
                text: fold.open ? "expand_less" : "expand_more"
                iconSize: ClockStyle.iconSmall
                color: ClockStyle.colSubtext
            }
        }
    }

    // A finding that went away: what it was, when, and whether the user's own action
    // did it. Read from the helper's memory, so it outlives the finding.
    component FixedRow: Rectangle {
        id: fixedRow
        property var entry: null
        readonly property string by: String(fixedRow.entry?.by ?? "self")

        implicitHeight: fixedLayout.implicitHeight + ClockStyle.gap * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        RowLayout {
            id: fixedLayout
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: ClockStyle.gapLarge
                rightMargin: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            MaterialSymbol {
                text: "check_circle"
                iconSize: ClockStyle.iconNormal
                fill: 1
                color: ClockStyle.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: HealthText.title(fixedRow.entry)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: fixedRow.by === "self"
                        ? Translation.tr("Fixed %1 ago, on its own").arg(HealthText.age(fixedRow.entry?.resolvedAt, root.now))
                        : Translation.tr("Fixed %1 ago, after you chose %2").arg(HealthText.age(fixedRow.entry?.resolvedAt, root.now)).arg(HealthText.verbLabel(fixedRow.by))
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }
        }
    }

    component FindingCard: RippleButton {
        id: card

        property var finding: null
        property int entranceIndex: 0
        readonly property string sev: card.finding?.sev ?? "info"
        readonly property color colContent: HealthStyle.colOnSeverity(card.sev)

        implicitHeight: cardRow.implicitHeight + ClockStyle.gap * 2
        buttonRadius: ClockStyle.radiusLarge
        colBackground: HealthStyle.colSeverity(card.sev)
        colBackgroundHover: HealthStyle.colSeverityHover(card.sev)
        colRipple: HealthStyle.colSeverityHover(card.sev)
        onClicked: root.toggle(card.finding)

        StaggeredEntrance {
            index: card.entranceIndex
            active: !ClockStyle.reducedMotion
        }

        contentItem: RowLayout {
            id: cardRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: ClockStyle.gapLarge
                rightMargin: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            MaterialSymbol {
                text: HealthStyle.severitySymbol(card.finding?.kind)
                iconSize: ClockStyle.iconNormal
                fill: card.sev === "critical" ? 1 : 0
                color: card.colContent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: HealthText.title(card.finding)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: card.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    text: HealthText.detail(card.finding, root.now)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: card.colContent
                    opacity: 0.85
                }
            }

            HealthAnswerMark {
                assistant: root.assistant
                key: HealthService.answerKey(card.finding)
                color: card.colContent
            }

            MaterialSymbol {
                text: card.finding?.kind === "crash" ? "arrow_forward" : "chevron_right"
                iconSize: ClockStyle.iconSmall
                color: card.colContent
                opacity: 0.7
            }
        }
    }

    // ── Vitals ──────────────────────────────────────────────────────────
    component Vitals: GridLayout {
        id: vitals

        readonly property var v: HealthService.vitals
        readonly property var rootFs: Array.from(vitals.v?.fs ?? []).find(f => f.mount === "/") ?? (vitals.v?.fs ?? [])[0] ?? null
        readonly property var nvme: HealthService.drives[0] ?? null

        property real availableWidth: root.layoutWidth
        columns: Math.max(1, Math.min(3, Math.floor((vitals.availableWidth + ClockStyle.paneGap) / (HealthStyle.vitalMinWidth + ClockStyle.paneGap))))
        columnSpacing: ClockStyle.paneGap
        rowSpacing: ClockStyle.paneGap
        visible: vitals.v !== null

        VitalTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: Translation.tr("Memory pressure")
            value: Number(vitals.v?.psi?.memory?.some10 ?? 0).toFixed(2)
            unit: Translation.tr("% stalled · 10 s")
            note: vitals.v?.memory ? Translation.tr("%1 available").arg(HealthText.bytes(vitals.v.memory.available)) : ""

            Sparkline {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                values: Array.from(vitals.v?.psiHistory ?? [])
            }
        }

        VitalTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: Translation.tr("CPU throttling")
            value: String(vitals.v?.throttle?.last5min ?? 0)
            unit: Translation.tr("events in 5 min")
            note: vitals.v?.cpuTempC ? Translation.tr("Processor at %1 °C").arg(Math.round(vitals.v.cpuTempC)) : Translation.tr("%1 since boot").arg(vitals.v?.throttle?.total ?? 0)
        }

        VitalTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: Translation.tr("Root disk")
            value: vitals.rootFs ? String(Math.round(vitals.rootFs.usedPct)) : "—"
            unit: vitals.rootFs ? Translation.tr("% used · %1 free").arg(HealthText.bytes(vitals.rootFs.avail)) : ""
            note: vitals.nvme ? Translation.tr("Drive wear %1 % · %2 °C").arg(vitals.nvme.percentUsed ?? "—").arg(vitals.nvme.tempC ?? "—") : ""
            clickable: true
            onClicked: root.tabRequested("storage")
        }
    }

    component VitalTile: Rectangle {
        id: tile

        property string label: ""
        property string value: ""
        property string unit: ""
        property string note: ""
        property bool clickable: false
        default property alias extra: tileColumn.data

        signal clicked()

        implicitHeight: Math.max(118, tileColumn.implicitHeight + ClockStyle.gapLarge * 2)
        radius: ClockStyle.radiusLarge
        color: tileMouse.containsMouse && tile.clickable ? ClockStyle.colIdleCardHover : ClockStyle.colPane

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: tile.clickable
            enabled: tile.clickable
            cursorShape: tile.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: tile.clicked()
        }

        ColumnLayout {
            id: tileColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gapTiny

            StyledText {
                text: tile.label
                font.pixelSize: ClockStyle.textSmall - 1
                font.weight: Font.Black
                font.letterSpacing: 0.8
                font.capitalization: Font.AllUppercase
                color: ClockStyle.colSubtext
            }

            RowLayout {
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: tile.value
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ({ "wght": 720, "wdth": 45, "ROND": 100 })
                    font.pixelSize: 32
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: tile.unit
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: tile.note.length > 0
                text: tile.note
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
                opacity: 0.85
            }
        }
    }

    // The page's only sparkline: memory stall over the last few minutes, area and line,
    // the newest sample marked. Drawn on a Canvas that repaints only when values change.
    component Sparkline: Canvas {
        id: spark

        property var values: []
        readonly property color colLine: ClockStyle.colPrimary

        onValuesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onColLineChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const vals = spark.values;
            if (!vals || vals.length < 2 || spark.width <= 0)
                return;
            const max = Math.max(1, ...vals);
            const step = spark.width / (vals.length - 1);
            const y = v => spark.height - 3 - (v / max) * (spark.height - 6);
            ctx.beginPath();
            ctx.moveTo(0, spark.height);
            vals.forEach((v, i) => ctx.lineTo(i * step, y(v)));
            ctx.lineTo(spark.width, spark.height);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(spark.colLine.r, spark.colLine.g, spark.colLine.b, 0.18);
            ctx.fill();
            ctx.beginPath();
            vals.forEach((v, i) => i === 0 ? ctx.moveTo(0, y(v)) : ctx.lineTo(i * step, y(v)));
            ctx.strokeStyle = spark.colLine;
            ctx.lineWidth = 2;
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(spark.width - 2, y(vals[vals.length - 1]), 3, 0, Math.PI * 2);
            ctx.fillStyle = spark.colLine;
            ctx.fill();
        }
    }
}
