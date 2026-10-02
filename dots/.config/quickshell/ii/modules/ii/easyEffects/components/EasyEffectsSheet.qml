import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The app's side sheet: the clock's `ClockSheet` with this app's header — a badge carrying
 * the thing being edited, its name in the title face, a tonal close — and a roomier pane.
 * Built by ClockSidePanel (`show(component, props)`), so it keeps the same contract:
 * `host`, `closeRequested`, a default slot for the body, `actions` for the footer.
 */
FocusScope {
    id: root

    property string title: ""
    property string subtitle: ""
    /// The glyph and shape of the header badge; `badgeShape` morphs when it changes.
    property string badge: "tune"
    property int badgeShape: EasyEffectsStyle.shapeFor(root.title)
    /// False when the body brings its own scrolling.
    property bool scrollable: true
    /// The ClockSidePanel that built this sheet; set on creation.
    property Item host: null
    default property alias content: body.data
    property alias actions: actionsColumn.data
    property alias headerActions: headerActionRow.data
    /// The scrolling body, for a sheet that scrolls itself to something it just revealed.
    property alias flickable: flick

    /// Scrolls the body so `item` (inside it) is at the top, eased; nothing when it already is.
    function scrollTo(item: Item): void {
        if (!item)
            return;
        const top = item.mapToItem(flick.contentItem, 0, 0).y;
        scrollAnimation.to = Math.max(0, Math.min(flick.contentHeight - flick.height, top - EasyEffectsStyle.gapTiny));
        scrollAnimation.restart();
    }

    signal closeRequested()

    function close(): void {
        root.closeRequested();
    }

    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: event => {
        root.close();
        event.accepted = true;
    }

    // The words arrive a beat after the pane starts opening, from the side it opens on.
    opacity: 0
    transform: Translate {
        id: entrance
        x: EasyEffectsStyle.reducedMotion ? 0 : EasyEffectsStyle.gapHuge
        Behavior on x {
            animation: EasyEffectsStyle.motionSpatial.numberAnimation.createObject(this)
        }
    }
    Component.onCompleted: {
        root.opacity = 1;
        entrance.x = 0;
    }
    Behavior on opacity {
        animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: EasyEffectsStyle.radiusPane
        color: EasyEffectsStyle.colSheet
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: EasyEffectsStyle.cardPadding
        }
        spacing: EasyEffectsStyle.gapSmall + 2

        RowLayout {
            Layout.fillWidth: true
            spacing: EasyEffectsStyle.gap

            EasyEffectsBadge {
                size: EasyEffectsStyle.sheetBadge
                text: root.badge
                shape: root.badgeShape
                color: EasyEffectsStyle.colPrimary
                colSymbol: EasyEffectsStyle.colOnPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.family: EasyEffectsStyle.fontTitle
                    font.variableAxes: EasyEffectsStyle.axesName
                    font.pixelSize: EasyEffectsStyle.textCardTitle
                    color: EasyEffectsStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: EasyEffectsStyle.textSmall
                    color: EasyEffectsStyle.colSubtext
                }
            }

            RowLayout {
                id: headerActionRow
                spacing: EasyEffectsStyle.gapTiny
            }

            RippleButton {
                id: closeButton
                implicitWidth: EasyEffectsStyle.iconButton
                implicitHeight: EasyEffectsStyle.iconButton
                buttonRadius: EasyEffectsStyle.pill(EasyEffectsStyle.iconButton)
                buttonRadiusPressed: EasyEffectsStyle.radiusField
                colBackground: EasyEffectsStyle.colField
                colBackgroundHover: EasyEffectsStyle.colFieldHover
                colRipple: EasyEffectsStyle.colFieldHover
                onClicked: root.close()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: EasyEffectsStyle.iconNormal
                    color: EasyEffectsStyle.colOnSurface
                }

                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }

        NumberAnimation {
            id: scrollAnimation
            target: flick
            property: "contentY"
            duration: EasyEffectsStyle.reducedMotion ? 0 : EasyEffectsStyle.motionDefault.duration
            easing.type: Easing.OutCubic
        }

        StyledFlickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: root.scrollable && contentHeight > height
            contentWidth: width
            contentHeight: root.scrollable ? body.implicitHeight : height

            ColumnLayout {
                id: body
                width: flick.width
                height: root.scrollable ? implicitHeight : flick.height
                spacing: EasyEffectsStyle.gapSmall - 2
            }
        }

        ColumnLayout {
            id: actionsColumn
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: EasyEffectsStyle.gapSmall
        }
    }
}
