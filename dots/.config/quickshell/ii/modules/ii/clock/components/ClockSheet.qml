import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Material 3 side sheet: the right-hand rail the app opens for anything that used to be
 * a dialog — a new alarm, a city search, a label. It takes room from the page instead of
 * covering it, exactly like the timetable's event rail, so the alarm you are editing
 * stays in sight while you edit it.
 *
 * Sheets are built by ClockSidePanel (`show(component, props)`) and destroyed after they
 * slide away, so a closed sheet holds no tree. Content goes in the default slot, the
 * footer buttons in `actions`, small icon buttons beside the title in `headerActions`.
 */
FocusScope {
    id: root

    property string title: ""
    property string subtitle: ""
    /// False when the body brings its own scrolling (a ListView that fills the sheet).
    property bool scrollable: true
    /// The ClockSidePanel that built this sheet; set on creation.
    property Item host: null
    default property alias content: body.data
    property alias actions: actionsColumn.data
    property alias headerActions: headerActionRow.data

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

    // The sheet's contents arrive a beat after the rail starts opening, from the side it
    // opens on — the rail's width animation carries the surface, this carries the words.
    opacity: 0
    transform: Translate {
        id: entrance
        x: ClockStyle.reducedMotion ? 0 : ClockStyle.gapHuge
        Behavior on x {
            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
        }
    }
    Component.onCompleted: {
        root.opacity = 1;
        entrance.x = 0;
    }
    Behavior on opacity {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSheet
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: headerActionRow
                spacing: 2
            }

            ClockIconButton {
                symbol: "close"
                size: 38
                iconSize: Appearance.font.pixelSize.larger
                tooltip: Translation.tr("Close")
                onClicked: root.close()
            }
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
                spacing: 10
            }
        }

        ColumnLayout {
            id: actionsColumn
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: 8
        }
    }
}
