pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One app limit as an expressive tile: the apps it covers, the time left in tall
 * condensed digits that fill the tile, a wavy bar of the budget spent, and its switch.
 *
 * The tile's hue is its state — primary container while there is time, tertiary in the
 * warning window, error once spent, the pane colour when off or not today — and the
 * switch and hover actions follow that family, as the clock's alarm tiles do.
 */
Rectangle {
    id: root

    required property var limit
    property bool editing: false
    property real layoutWidth: root.width

    signal editRequested()
    signal deleteRequested()
    signal toggleRequested(bool on)

    readonly property string limitState: ScreenTimeLimits.stateFor(root.limit)
    readonly property real used: ScreenTimeLimits.usedFor(root.limit)
    readonly property real budget: ScreenTimeLimits.budgetFor(root.limit)
    readonly property bool spent: root.limitState === "reached" || root.limitState === "ignored"
    readonly property bool enabledRule: root.limit?.enabled !== false
    readonly property var keys: root.limit?.keys ?? []

    readonly property color colContainer: root.limitState === "off" ? ClockStyle.colIdleCard
        : root.spent ? ClockStyle.colErrorContainer
        : root.limitState === "warn" ? ClockStyle.colTertiaryContainer
        : ClockStyle.colPrimaryContainer
    readonly property color colContainerHover: root.limitState === "off" ? ClockStyle.colIdleCardHover
        : root.spent ? ClockStyle.colErrorContainerHover
        : root.limitState === "warn" ? ClockStyle.colTertiaryContainerHover
        : ClockStyle.colPrimaryContainerHover
    readonly property color colContent: root.limitState === "off" ? ClockStyle.colOnIdleCard
        : root.spent ? ClockStyle.colOnErrorContainer
        : root.limitState === "warn" ? ClockStyle.colOnTertiaryContainer
        : ClockStyle.colOnPrimaryContainer
    readonly property color colAccent: root.spent ? ClockStyle.colError
        : root.limitState === "warn" ? ClockStyle.colTertiary : ClockStyle.colPrimary
    readonly property color colOnAccent: root.spent ? ClockStyle.colOnError
        : root.limitState === "warn" ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimary

    // The digits get what the header and footer leave, sized from the settled width.
    readonly property real innerWidth: root.layoutWidth - ClockStyle.cardPadding * 2
    readonly property real digitsHeight: root.height - ClockStyle.gapLarge - ClockStyle.cardPadding - 40 - 62
    readonly property real digitSize: Math.round(Math.max(30, Math.min(root.digitsHeight * 0.98, root.innerWidth / 3.1)))

    // Off thins the digits the way the clock outlines an alarm that is off.
    property real boldness: root.limitState === "off" ? 0 : 1
    Behavior on boldness {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation {
            duration: ClockStyle.motionDefault.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
        }
    }
    readonly property var digitAxes: ({
        "wght": ClockStyle.axesDigits.wght + (ClockStyle.axesDigitsBold.wght - ClockStyle.axesDigits.wght) * root.boldness,
        "wdth": ClockStyle.axesDigits.wdth + (ClockStyle.axesDigitsBold.wdth - ClockStyle.axesDigits.wdth) * root.boldness,
        "ROND": 100
    })

    readonly property bool engaged: cardHover.hovered || editButton.activeFocus || deleteButton.activeFocus

    function digits(seconds: real): string {
        const m = Math.ceil(Math.max(0, seconds) / 60);
        return Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0");
    }

    function daysSummary(days): string {
        const list = days ?? [];
        if (list.length !== 7 || list.every(d => d))
            return Translation.tr("Every day");
        if (String(list) === String([false, true, true, true, true, true, false]))
            return Translation.tr("Weekdays");
        if (String(list) === String([true, false, false, false, false, false, true]))
            return Translation.tr("Weekends");
        if (!list.some(d => d))
            return Translation.tr("Never");
        const names = [];
        for (let i = 0; i < 7; i++)
            if (list[i])
                names.push(Qt.locale().dayName(i, Locale.ShortFormat));
        return names.join(", ");
    }

    radius: ClockStyle.radiusCard
    color: root.editing ? ClockStyle.colSecondaryContainer : root.engaged ? root.colContainerHover : root.colContainer
    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.editRequested()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
            topMargin: ClockStyle.gapLarge
            rightMargin: ClockStyle.gapLarge
        }
        spacing: 0

        // ── Apps and hover actions ──────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: ClockStyle.gapSmall

            // Up to three icons, overlapping like a group of avatars.
            Item {
                implicitWidth: 34 + Math.max(0, Math.min(3, root.keys.length) - 1) * 20
                implicitHeight: 34

                Repeater {
                    model: Math.min(3, root.keys.length)

                    Rectangle {
                        id: iconPad
                        required property int index
                        x: index * 20
                        z: 3 - index
                        width: 34
                        height: 34
                        radius: 17
                        color: root.editing ? ClockStyle.colSecondaryContainer : root.colContainer

                        LimitsAppIcon {
                            anchors.centerIn: parent
                            size: 28
                            appKey: root.keys[iconPad.index] ?? ""
                            colFallback: root.colContent
                        }
                    }
                }
            }

            StyledText {
                id: nameText
                Layout.fillWidth: true
                text: ScreenTimeLimits.ruleName(root.limit)
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                font.weight: Font.DemiBold
                color: root.colContent

                HoverHandler {
                    id: nameHover
                }
                StyledToolTip {
                    extraVisibleCondition: nameHover.hovered && nameText.truncated
                    text: nameText.text
                }
            }

            MaterialSymbol {
                visible: root.limit?.strict === true
                text: "lock"
                iconSize: ClockStyle.iconSmall
                fill: 1
                color: root.colContent

                HoverHandler {
                    id: lockHover
                }
                StyledToolTip {
                    extraVisibleCondition: lockHover.hovered
                    text: Translation.tr("More time needs the PIN")
                }
            }

            Item {
                id: actionSlot
                property real revealProgress: root.engaged ? 1 : 0

                Layout.preferredWidth: (actionRow.implicitWidth + 4) * actionSlot.revealProgress
                Layout.preferredHeight: actionRow.implicitHeight
                clip: true

                Behavior on revealProgress {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: actionRow
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    opacity: actionSlot.revealProgress
                    enabled: root.engaged

                    ClockCardAction {
                        id: editButton
                        symbol: "edit"
                        tip: Translation.tr("Edit limit")
                        colContent: root.colContent
                        onClicked: root.editRequested()
                    }
                    ClockCardAction {
                        id: deleteButton
                        symbol: "delete"
                        tip: Translation.tr("Delete")
                        danger: true
                        onClicked: root.deleteRequested()
                    }
                }
            }
        }

        // ── Time left ───────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            RowLayout {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: (root.limitState === "ignored" ? "+" : "") + root.digits(root.limitState === "ignored" ? root.used - root.budget : root.budget - root.used)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: root.digitAxes
                    font.pixelSize: root.digitSize
                    color: root.colContent
                }

                StyledText {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: root.digitSize * 0.16
                    text: root.limitState === "ignored" ? Translation.tr("over") : root.spent ? Translation.tr("time's up") : Translation.tr("left")
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: Math.round(Math.max(16, root.digitSize * 0.28))
                    color: root.colContent
                }
            }
        }

        StyledProgressBar {
            Layout.fillWidth: true
            Layout.bottomMargin: ClockStyle.gapSmall
            valueBarHeight: 6
            value: root.budget > 0 ? Math.min(1, root.used / root.budget) : 0
            wavy: !root.spent && root.limitState !== "off"
            animateWave: true
            highlightColor: root.colContent
            trackColor: ColorUtils.applyAlpha(root.colContent, 0.2)
        }

        // ── Budget and switch ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            spacing: ClockStyle.gap

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 of %2").arg(ScreenTimeLimits.formatCompact(root.used)).arg(ScreenTimeLimits.formatCompact(root.budget))
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: root.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.daysSummary(root.limit?.days)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContent
                    opacity: 0.8
                }
            }

            StyledSwitch {
                sizeScale: 1.0
                checked: root.enabledRule
                checkable: false
                activeColor: root.limitState === "off" ? ClockStyle.colPrimary : root.colAccent
                activeThumbColor: root.limitState === "off" ? ClockStyle.colOnPrimary : root.colOnAccent
                onClicked: root.toggleRequested(!root.enabledRule)
            }
        }
    }
}
