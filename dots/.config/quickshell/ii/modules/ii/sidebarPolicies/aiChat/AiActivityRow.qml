pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * One line of what the model did before it answered.
 *
 * Reasoning, a web search, a tool it reached for: each is a quiet row above
 * the answer rather than a card inside it, because none of them is the
 * answer. A row that is still happening carries a light travelling across
 * its own label — the one thing on screen that says the wait is not a stall.
 * Rows that can be opened say so with a caret and keep whatever they hold in
 * a strip that grows out of the row itself.
 */
Item {
    id: root

    property string symbol: "neurology"
    property string label: ""
    /** Set while the step is still happening: the row sheens and dims. */
    property bool running: false
    /** Whether there is anything behind the row worth opening. */
    property bool expandable: false
    property bool expanded: false
    /** Shared with Search so activity never moves when motion is reduced. */
    property bool reducedMotion: Config.options.sidebar.ai.reducedMotion
    /** How tall the opened strip may get before it scrolls on its own. */
    property real maximumContentHeight: Appearance.font.pixelSize.huge * 9

    /**
     * What the row opens into. It is a Component rather than a default
     * property because a default alias in a file like this one swallows the
     * component's own children too — the row's header would end up inside
     * the strip it is supposed to open.
     */
    property Component expandedContent: null

    /**
     * Whether this step belongs on screen at all. Separate from `visible` so
     * a step that starts partway through an answer — a search, a tool — can
     * arrive rather than appear.
     */
    property bool shown: true

    /**
     * Whether a timeline rule runs down this row's icon column. Set by the
     * step group that draws the rule, so a lone row does not pay for one.
     * The row answers by clearing a disc for its own icon and carrying the
     * rule on down whatever it opens, which is what makes a sequence of
     * steps read as one thread rather than as stacked rows.
     */
    property bool onTimeline: false
    /** The surface the rule is drawn on, so the disc can hide it. */
    property color timelineSurface: Appearance.colors.colLayer1

    signal toggled

    readonly property real rowSpacing: Appearance.rounding.unsharpenmore
    readonly property real iconSize: Appearance.font.pixelSize.larger
    readonly property real contentInset: root.iconSize + root.rowSpacing * 2

    implicitHeight: activityColumn.implicitHeight
    implicitWidth: activityColumn.implicitWidth

    // A row that can be opened can be opened with the keyboard too.
    activeFocusOnTab: root.expandable
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Keys.onPressed: event => {
        if (!root.expandable)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.toggled();
            event.accepted = true;
        }
    }

    // A step that begins partway through an answer slides in rather than
    // blinking into the column above the bubble.
    visible: root.shown || root.opacity > 0.01
    opacity: root.shown ? 1 : 0
    transform: Translate {
        y: root.shown ? 0 : -Appearance.rounding.small

        Behavior on y {
            enabled: !root.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    Behavior on opacity {
        enabled: !root.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: activityColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        Item {
            id: headerItem
            Layout.fillWidth: true
            implicitHeight: Math.round(headerRow.implicitHeight + Appearance.rounding.unsharpenmore * 1.5)

            MouseArea {
                id: headerMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.expandable
                cursorShape: root.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.toggled()
            }

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.rowSpacing

                MaterialSymbol {
                    id: leadingGlyph
                    Layout.alignment: Qt.AlignVCenter
                    text: root.symbol
                    fill: 1
                    iconSize: root.iconSize
                    color: Appearance.colors.colSubtext
                    opacity: headerMouse.containsMouse || root.activeFocus ? 1 : 0.9

                    Behavior on opacity {
                        enabled: !root.reducedMotion
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Rectangle {
                        // Behind the glyph, wide enough to swallow the rule
                        // passing through: a timeline reads as a thread with
                        // beads on it, not as a line drawn over icons.
                        z: -1
                        anchors.centerIn: parent
                        visible: root.onTimeline
                        implicitWidth: root.iconSize + Appearance.rounding.unsharpenmore
                        implicitHeight: implicitWidth
                        radius: Appearance.rounding.full
                        color: root.timelineSurface
                    }
                }

                SheenText {
                    // The label carries the progress, so the row needs no
                    // spinner of its own beside it.
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.label
                    running: root.running
                    color: headerMouse.containsMouse || root.activeFocus ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.expandable
                    text: "chevron_right"
                    fill: 1
                    iconSize: root.iconSize
                    color: headerMouse.containsMouse || root.activeFocus ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    rotation: root.expanded ? 90 : 0

                    Behavior on rotation {
                        enabled: !root.reducedMotion
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Behavior on color {
                        enabled: !root.reducedMotion
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }

        Item {
            // The strip the row opens into. It grows from nothing, so opening
            // one reads as the row unfolding rather than as a panel appearing.
            id: contentClip
            Layout.fillWidth: true
            Layout.leftMargin: root.contentInset
            Layout.bottomMargin: contentClip.implicitHeight > 0 ? Appearance.rounding.unsharpenmore : 0
            // Measured off the loaded item rather than off the Loader: a
            // Loader anchored to a width does not always carry its item's
            // implicit height back out, and the strip stayed shut.
            implicitHeight: root.expanded ? Math.min(contentLoader.contentHeight, root.maximumContentHeight) : 0
            clip: true
            opacity: root.expanded ? 1 : 0
            // Visibility follows the choice, never the measurement: a layout
            // gives no width to an invisible child, and a strip with no width
            // has nothing to measure — which kept it shut for good.
            visible: root.expanded || contentClip.implicitHeight > 0.5

            Behavior on implicitHeight {
                enabled: !root.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            Behavior on opacity {
                enabled: !root.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Loader {
                id: contentLoader
                readonly property real contentHeight: contentLoader.item?.implicitHeight ?? 0

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: contentLoader.contentHeight
                // Nothing is built for a row nobody has opened.
                active: root.expanded && root.expandedContent !== null
                sourceComponent: root.expandedContent
            }
        }
    }

    /**
     * Text with a light passing over it while something is still happening.
     *
     * The sweep is masked by the glyphs themselves, so it reads as the words
     * catching the light rather than as a bar sliding over them. It exists
     * only while `running`, and takes nothing at all once the step is done.
     */
    component SheenText: Item {
        id: sheen

        property string text: ""
        property color color: Appearance.colors.colSubtext
        property color highlight: Appearance.m3colors.m3onSurface
        property bool running: false
        readonly property bool animating: sheen.running && !root.reducedMotion

        implicitWidth: sheenLabel.implicitWidth
        implicitHeight: sheenLabel.implicitHeight

        StyledText {
            id: sheenLabel
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: sheen.text
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: sheen.color
            // While the sweep is on, this same text is the mask it is cut
            // with, and drawing it twice would only thicken it.
            visible: !sheen.animating

            Behavior on color {
                enabled: !root.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Loader {
            anchors.fill: parent
            active: sheen.animating

            sourceComponent: Item {
                Item {
                    id: sweepSource
                    anchors.fill: parent
                    visible: false

                    Rectangle {
                        // The label's own colour, always under the sweep, so
                        // the words never blink out between passes.
                        anchors.fill: parent
                        color: sheen.color
                    }

                    Rectangle {
                        id: sweepBand
                        height: parent.height
                        width: Math.max(parent.width, Appearance.font.pixelSize.huge) * 0.9

                        NumberAnimation on x {
                            running: true
                            loops: Animation.Infinite
                            from: -sweepBand.width
                            to: Math.max(sweepSource.width, Appearance.font.pixelSize.huge)
                            duration: Math.round(Appearance.animation.elementMoveSlow.duration * 2.2)
                            easing.type: Easing.InOutSine
                        }

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: "transparent"
                            }
                            GradientStop {
                                position: 0.5
                                color: sheen.highlight
                            }
                            GradientStop {
                                position: 1.0
                                color: "transparent"
                            }
                        }
                    }
                }

                OpacityMask {
                    anchors.fill: parent
                    source: sweepSource
                    maskSource: sheenLabel
                }
            }
        }
    }
}
