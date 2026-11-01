import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Before the collection opens: probing, the one-time install of Anki's engine, the
 * install in progress, or a daemon that couldn't start. One expressive shape, one line
 * of context, one action.
 */
Item {
    id: root

    readonly property string mode: Anki.installed === null ? "probe"
        : Anki.installing ? "installing"
        : Anki.installed === false ? "install"
        : Anki.fatal.length > 0 ? "error"
        : "starting"

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - ClockStyle.gapHuge, 330)
        spacing: ClockStyle.gapLarge

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: root.mode === "probe" || root.mode === "starting" || root.mode === "installing"
            loading: visible
            implicitSize: 72
            shapeColor: ClockStyle.colPrimary
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            visible: root.mode === "install"
            symbol: "school"
            shape: "Cookie9Sided"
            colShape: ClockStyle.colPrimaryContainer
            colIcon: ClockStyle.colOnPrimaryContainer
            title: Translation.tr("Study with Anki")
            subtitle: Translation.tr("Installs Anki's own engine (scheduler, cards and AnkiWeb sync) in ~/.local/share/ii-anki. The Anki app isn't needed. About 100 MB.")
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            visible: root.mode === "error"
            symbol: "error"
            shape: "SoftBurst"
            colShape: ClockStyle.colErrorContainer
            colIcon: ClockStyle.colOnErrorContainer
            title: Translation.tr("Anki couldn't start")
            subtitle: Anki.fatal === "locked"
                ? Translation.tr("The collection is open in another program. Close it and try again.")
                : (Anki.lastError.length > 0 ? Anki.lastError : Translation.tr("The engine stopped while opening the collection."))
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.mode === "installing" || root.mode === "starting"
            text: root.mode === "installing" ? Anki.installStep : Translation.tr("Opening your collection")
            font.family: ClockStyle.fontTitle
            font.variableAxes: ClockStyle.axesTitle
            font.pixelSize: Appearance.font.pixelSize.larger
            color: ClockStyle.colOnSurface
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.mode === "install" && Anki.installError.length > 0
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            text: Anki.installError
            font.pixelSize: ClockStyle.textSmall
            color: Appearance.m3colors.m3error
        }

        ClockSheetAction {
            visible: root.mode === "install"
            primary: true
            symbol: "download"
            label: Anki.installError.length > 0 ? Translation.tr("Try again") : Translation.tr("Install")
            onClicked: Anki.install()
        }

        ClockSheetAction {
            visible: root.mode === "error"
            primary: true
            symbol: "refresh"
            label: Translation.tr("Try again")
            onClicked: Anki.retryStart()
        }
    }
}
