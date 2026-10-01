pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * One condition of a mode or routine: its summary, whether it holds right now, and —
 * unfolded — the form for its parameters. Each change is written back as a whole trigger
 * object; the engine normalizes it.
 *
 * Drawn as the clock's picker row: a shaped icon that turns while the form is open, the
 * summary leading, a live verdict chip, and the fold and remove buttons on the right.
 */
Rectangle {
    id: root

    required property var trigger
    property var watcher: null
    property int triggerIndex: 0
    property bool expanded: false

    readonly property string type: root.trigger?.type ?? ""
    readonly property var condition: root.watcher?.conditionAt(root.triggerIndex) ?? null
    readonly property bool supported: root.condition?.supported ?? true
    readonly property bool misplacedEvent: root.condition?.misplacedEvent ?? false
    /// The owning mode or routine's id (shortcut triggers derive their name from it).
    property string ownerId: ""
    readonly property bool negated: root.trigger?.not === true
    readonly property int forSec: ModeSchema.durationSec(root.trigger?.forSec)
    // The verdict the engine uses (after the dwell); `counting` is the gap between the
    // condition turning true and the dwell running out.
    readonly property bool holds: root.condition ? (root.condition.ok ?? false)
        : ((root.condition?.item?.satisfied ?? false) !== root.negated)
    readonly property bool counting: root.condition?.counting ?? false
    readonly property string liveReason: root.condition?.item?.reason ?? ""

    onExpandedChanged: formLoader.sync()

    signal changed(var trigger)
    signal removeRequested()

    function set(changes) {
        root.changed(Object.assign({}, ModeSchema.clone(root.trigger), changes));
    }

    implicitHeight: column.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusSmall
    color: root.expanded ? ClockStyle.colPane
        : headerArea.containsMouse ? ClockStyle.colIdleCardHover : ClockStyle.colPane
    clip: true

    Behavior on implicitHeight {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    // The header is the unfold button too: a click on it, outside the controls, folds
    // the form open or shut.
    MouseArea {
        id: headerArea
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: header.height + ClockStyle.gap * 2
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: ClockStyle.gap
            leftMargin: ClockStyle.gap
            rightMargin: ClockStyle.gapSmall
        }
        spacing: ClockStyle.gap

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: ModeUi.triggerTypeIcon(root.type)
                iconSize: 18
                padding: 9
                shape: MaterialShape.Shape.Cookie7Sided
                color: root.expanded ? ClockStyle.colTertiaryContainer : ClockStyle.colPrimaryContainer
                colSymbol: root.expanded ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnPrimaryContainer
                rotation: root.expanded || headerArea.containsMouse ? 20 : 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: ModeUi.triggerText(root.trigger)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: ModeUi.triggerTypeLabel(root.type)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                }
            }

            // Live verdict, so a mode that "should have started" is diagnosable from its
            // own row.
            Rectangle {
                id: verdict
                visible: root.watcher !== null
                implicitWidth: verdictRow.implicitWidth + ClockStyle.gap + 4
                implicitHeight: 28
                radius: ClockStyle.radiusSmall
                color: !root.supported ? ClockStyle.colErrorContainer
                    : (root.holds ? ClockStyle.colPrimaryContainer
                    : (root.counting ? ClockStyle.colTertiaryContainer : ClockStyle.colSurfaceHigh))

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                MouseArea {
                    id: verdictArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                StyledToolTip {
                    extraVisibleCondition: verdictArea.containsMouse
                        && (root.liveReason.length > 0 || root.counting || root.misplacedEvent)
                    text: root.misplacedEvent
                        ? Translation.tr("A moment, not a state: only a routine of type \"When conditions become true\" can fire on it")
                        : (root.counting
                            ? Translation.tr("True right now; counts once it has held for %1").arg(ModeUi.durationText(root.forSec))
                            : root.liveReason)
                }

                RowLayout {
                    id: verdictRow
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny

                    readonly property color fg: !root.supported ? ClockStyle.colOnErrorContainer
                        : (root.holds ? ClockStyle.colOnPrimaryContainer
                        : (root.counting ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurfaceVariant))

                    MaterialSymbol {
                        text: !root.supported ? "error" : (root.holds ? "check" : (root.counting ? "timer" : "remove"))
                        iconSize: ClockStyle.iconSmall - 1
                        fill: root.holds ? 1 : 0
                        color: verdictRow.fg
                    }

                    StyledText {
                        text: !root.supported
                            ? (root.misplacedEvent ? Translation.tr("Needs a \"when\" routine") : Translation.tr("Unsupported"))
                            : (ModeSchema.isEventTrigger(root.type)
                                ? (root.holds ? Translation.tr("Just fired") : Translation.tr("Listening"))
                                : (root.holds ? Translation.tr("Holds now")
                                : (root.counting ? Translation.tr("Counting") : Translation.tr("Not now"))))
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                        color: verdictRow.fg
                    }
                }
            }

            FormIconButton {
                buttonIcon: root.expanded ? "expand_less" : "expand_more"
                tooltip: root.expanded ? Translation.tr("Fold") : Translation.tr("Edit")
                onClicked: root.expanded = !root.expanded
            }

            FormIconButton {
                buttonIcon: "close"
                tooltip: Translation.tr("Remove condition")
                onClicked: root.removeRequested()
            }
        }

        // The parameter form lives in forms/Trigger<Editor>.qml and gets this row as
        // `row`; it is created on unfold and torn down on fold.
        Loader {
            id: formLoader
            Layout.fillWidth: true
            Layout.leftMargin: 46
            Layout.rightMargin: ClockStyle.gapSmall
            visible: status === Loader.Ready && item !== null
            readonly property string formUrl: ModeUi.triggerFormUrl(root.type)
            onFormUrlChanged: formLoader.sync()

            function sync() {
                if (!root.expanded || !formLoader.formUrl.length) {
                    formLoader.source = "";
                    return;
                }
                formLoader.setSource(formLoader.formUrl, { row: root });
            }
        }

        // Every condition can be read the other way round: "Zoom is not running" is how
        // "when Zoom closes" is said.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 46
            Layout.rightMargin: ClockStyle.gapSmall
            Layout.bottomMargin: ClockStyle.gapTiny
            visible: root.expanded
            spacing: ClockStyle.gap

            StyledSwitch {
                checked: root.negated
                onClicked: root.set({ not: checked })
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                FormLabel {
                    text: Translation.tr("Invert")
                }

                FormHint {
                    text: root.negated ? Translation.tr("Holds while the above is not the case")
                        : Translation.tr("Hold when the above is not the case instead")
                }
            }
        }

        // "Idle for 10 minutes", "in a game for 5 minutes": the verdict has to last this
        // long before it counts. Zero means at once. A moment (an event) cannot be held.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 46
            Layout.rightMargin: ClockStyle.gapSmall
            Layout.bottomMargin: ClockStyle.gapTiny
            visible: root.expanded && !ModeSchema.isEventTrigger(root.type)
            spacing: ClockStyle.gap

            StyledSwitch {
                checked: root.forSec > 0
                onClicked: root.set({ forSec: checked ? 300 : 0 })
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                FormLabel {
                    text: Translation.tr("For at least")
                }

                FormHint {
                    text: root.forSec > 0
                        ? Translation.tr("Counts only once it has held for %1 without a break").arg(ModeUi.durationText(root.forSec))
                        : Translation.tr("Counts the moment it holds")
                }
            }

            // Created on demand: a field built while hidden measures its unit strip at
            // zero width and keeps it.
            Loader {
                active: root.forSec > 0
                visible: active

                sourceComponent: DurationField {
                    seconds: root.forSec
                    minimum: 1
                    onCommitted: sec => root.set({ forSec: sec })
                }
            }
        }
    }
}
