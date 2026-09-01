import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * "Remote access & IPC" sub-page. Moved off the main AI dashboard: it is
 * reference documentation for driving this chat over Quickshell IPC, not a
 * set of preferences — it holds no control of its own.
 */
ContentPage {
    id: page

    property bool showBackButton: false
    signal goBack()

    forceWidth: false

    RowLayout {
        visible: page.showBackButton
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: page.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Remote Access & IPC")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "terminal"
        title: Translation.tr("Remote access")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "dns"
            isFirst: true
            text: Translation.tr("This chat can be asked a question from outside the shell entirely — a script, a cron job, another shell over SSH — through Quickshell's own IPC socket. It runs like a message typed into the composer: same chat, same tools, same model, one exchange at a time.")
        }

        HelperCodeBox {
            Layout.fillWidth: true
            icon: "send"
            title: Translation.tr("Ask a question")
            text: Translation.tr("Returns immediately with accepted/rejected as JSON — busy, a missing key, a disabled policy. The answer itself is not in that reply; it lands separately once the model is done.")
            codeSnippet: "qs -c ii ipc call ai ask \"What is using the most memory right now?\""
            snippetWrapMode: Text.WrapAnywhere
        }

        HelperCodeBox {
            Layout.fillWidth: true
            icon: "chat"
            title: Translation.tr("Read the answer back")
            text: Translation.tr("Either works: the IPC call below returns the same JSON that is kept on disk, updated once per finished exchange.")
            codeSnippet: "qs -c ii ipc call ai lastAnswer\ncat " + Directories.aiLastAnswer
            snippetWrapMode: Text.WrapAnywhere
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "warning"
            isLast: true
            text: Translation.tr("A real limit, not a bug: running a shell command always asks for approval first, and that approval has no deadline — it waits for a click in the transcript. Asked this way, with no window open to click anything, that wait never ends until you open the chat yourself and answer the card. Read-only tools (settings lookups, system status, file search) need no approval and work exactly as well remotely as they do in the composer.")
        }
    }
}
