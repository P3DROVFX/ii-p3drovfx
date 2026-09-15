import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/**
 * Every one of a widget's own settings, beside its Edit Mode menu.
 *
 * The controls already exist: each widget names a Settings page in the
 * registry (`configPage`), and those pages are the only description of what a
 * widget can be told to do. Re-stating them here - one panel per widget, fifty
 * widgets - would be thousands of lines that go stale the day someone adds a
 * toggle to the real page. So this LOADS that page and draws it in the popup
 * instead: whatever Settings shows, this shows, forever, for nothing.
 *
 * Two things make a Settings page fit a popup. `headerVisible` takes off the
 * page's own back-button header, because the card already says which widget
 * this is and there is no navigation stack behind it; and the height follows
 * the loaded page's content until it hits the screen, so a widget with two
 * toggles gets a short card and the clock's forty get a scrolling one.
 *
 * The sub-page host is there for the pages that grow one later - a config row
 * that opens a detail page walks up the parent chain looking for something
 * with `activeSubPage`, and finds this.
 */
Item {
    id: root

    property string widgetId: ""
    // What the card is allowed to take of the screen it is drawn on.
    property real maxHeight: 640
    property real maxWidth: 440

    signal dismissRequested()

    property alias activeSubPage: subPageHost.activeSubPage

    readonly property var metadata: root.widgetId !== ""
        ? WidgetsRegistry.getWidgetMetadata(root.widgetId) : null
    readonly property string configPage: String(root.metadata?.configPage ?? "")
    // The registry stores the page relative to Settings' own config folder,
    // which is where WidgetsConfig resolves it from too.
    readonly property url pageUrl: root.configPage === ""
        ? "" : Qt.resolvedUrl("../../settings/configs/" + root.configPage)
    readonly property bool hasPage: root.configPage !== ""

    readonly property int padding: 8
    readonly property real headerHeight: 44
    // The page reports what it needs through its own flickable. Until it has
    // loaded there is nothing to ask, so the card holds a line's worth of
    // room for the progress bar rather than collapsing and popping open.
    readonly property real pageContentHeight: (pageLoader.item && pageLoader.item.flickable)
        ? pageLoader.item.flickable.contentHeight : 0
    readonly property real wantedHeight: root.headerHeight + root.padding * 2
        + Math.max(64, root.pageContentHeight)

    implicitWidth: Math.max(280, root.maxWidth)
    implicitHeight: Math.max(140, Math.min(root.maxHeight, root.wantedHeight))
    width: implicitWidth
    height: implicitHeight

    // The chrome holds the keyboard while this is open, so Escape lands here
    // rather than on the desktop's canvas. It closes the panel, which gives
    // the keyboard back - a second Escape then leaves the mode as it always
    // did. A text field inside takes the key first and keeps its own meaning.
    focus: true
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Escape)
            return;
        event.accepted = true;
        root.dismissRequested();
    }

    Behavior on implicitHeight {
        enabled: !Appearance.reducedMotion && pageLoader.status === Loader.Ready
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    StyledRectangularShadow {
        target: card
    }

    // A click anywhere on the card is a click ON it, never a click away.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    RowLayout {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding
        anchors.leftMargin: root.padding + 8
        height: root.headerHeight
        spacing: 8

        MaterialSymbol {
            text: root.metadata?.icon ?? "tune"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.metadata?.name ?? Translation.tr("Widget")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Widget options")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 32
            implicitHeight: 32
            radius: width / 2
            color: closeMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                : closeMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighest
                : "transparent"

            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: 19
                color: Appearance.colors.colOnSurfaceVariant
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismissRequested()
            }
        }
    }

    Item {
        id: pageHost
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.bottomMargin: root.padding
        clip: true

        Loader {
            id: pageLoader
            anchors.fill: parent
            asynchronous: true
            active: root.hasPage
            source: root.pageUrl
            onLoaded: {
                // The card is the title, and there is nowhere to go back to.
                if (item.hasOwnProperty("headerVisible"))
                    item.headerVisible = false;
                // Settings pads a hundred pixels under the last control so a
                // long page can be scrolled clear of the window's edge. A card
                // that is only as tall as its content would just be padding.
                if (item.hasOwnProperty("bottomContentPadding"))
                    item.bottomContentPadding = 4;
            }
        }

        StyledIndeterminateProgressBar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 24
            visible: root.hasPage && pageLoader.status !== Loader.Ready
        }

        EditPanelNotice {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.hasPage
            symbol: "tune"
            text: Translation.tr("This widget has nothing to set.")
        }

        ConfigSubPageHost {
            id: subPageHost
            anchors.fill: parent
            z: 10
        }
    }
}
