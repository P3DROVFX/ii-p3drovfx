import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets

/**
 * Local retrieval (RAG) settings sub-page.
 *
 * Off by default, and every folder here was chosen by hand through the
 * picker below — `rag_search` never reaches anything the user did not
 * explicitly index. Embedding happens on this machine through Ollama;
 * nothing indexed here leaves it.
 */
ContentPage {
    id: page

    property bool showBackButton: false
    signal goBack()

    forceWidth: false

    Component.onCompleted: AiRagService.refreshInstalledModels()

    property string folderPickerError: ""

    function openFolderPicker(): void {
        page.folderPickerError = "";
        folderPickerProc.running = false;
        folderPickerProc.running = true;
    }

    Process {
        id: folderPickerProc
        command: ["bash", "-c", "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory; elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME\"; else exit 127; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const selectedPath = text.trim();
                if (selectedPath.length > 0)
                    AiRagService.addCollection("", selectedPath);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 127)
                page.folderPickerError = Translation.tr("Install zenity or kdialog to choose a folder.");
        }
    }

    function humanSize(bytes: int): string {
        if (bytes >= 1024 * 1024)
            return Translation.tr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1));
        if (bytes >= 1024)
            return Translation.tr("%1 kB").arg(Math.round(bytes / 1024));
        return Translation.tr("%1 B").arg(bytes);
    }

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
            text: Translation.tr("Local Retrieval (RAG)")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "manage_search"
        title: Translation.tr("Local retrieval")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "lock"
            isFirst: true
            text: Translation.tr("Every folder below was chosen by hand. The assistant's rag_search tool can only search folders listed here — never a guess, never the whole home directory. Chunks are embedded on this machine through Ollama; nothing indexed here leaves it.")
        }

        ConfigSwitch {
            buttonIcon: "manage_search"
            text: Translation.tr("Let the assistant search indexed folders")
            checked: Config.options.ai.rag.enabled
            onCheckedChanged: {
                Config.options.ai.rag.enabled = checked;
            }
        }
    }

    ContentSection {
        icon: "smart_toy"
        title: Translation.tr("Embedding model")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            isFirst: true
            visible: AiRagService.modelsChecked && AiRagService.detectedEmbeddingModels.length === 0
            text: Translation.tr("No embedding model was detected in Ollama. Pull one to enable local retrieval, for example: ollama pull all-minilm")
        }

        Repeater {
            model: AiRagService.detectedEmbeddingModels

            RippleButton {
                id: modelRow
                required property string modelData

                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.normal
                colBackground: modelRow.modelData === AiRagService.embeddingModel ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: modelRow.modelData === AiRagService.embeddingModel ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                colRipple: modelRow.modelData === AiRagService.embeddingModel ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                onClicked: AiRagService.setEmbeddingModel(modelRow.modelData)

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    MaterialSymbol {
                        visible: modelRow.modelData === AiRagService.embeddingModel
                        text: "check_circle"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: modelRow.modelData
                        color: modelRow.modelData === AiRagService.embeddingModel ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: AiRagService.refreshInstalledModels()

            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    text: Translation.tr("Check again")
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    ContentSection {
        icon: "folder"
        title: Translation.tr("Indexed folders")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "warning"
            isFirst: true
            visible: page.folderPickerError.length > 0
            text: page.folderPickerError
        }

        Item {
            Layout.fillWidth: true
            visible: AiRagService.collections.length === 0
            implicitHeight: visible ? 140 : 0

            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "folder_off"
                title: Translation.tr("Nothing indexed yet")
                description: Translation.tr("Add a folder to let the assistant search it.")
            }
        }

        Repeater {
            model: AiRagService.collections

            ColumnLayout {
                id: collectionRow
                required property var modelData

                readonly property var stats: AiRagService.indexStats[collectionRow.modelData.id] ?? null
                readonly property bool isIndexing: AiRagService.indexingCollectionId === collectionRow.modelData.id

                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: "folder"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: String(collectionRow.modelData.name ?? "")
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: String(collectionRow.modelData.path ?? "")
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !collectionRow.isIndexing && collectionRow.stats !== null
                            text: collectionRow.stats
                                ? Translation.tr("%1 files · %2 chunks · %3").arg(collectionRow.stats.fileCount ?? 0).arg(collectionRow.stats.chunkCount ?? 0).arg(page.humanSize(collectionRow.stats.sizeBytes ?? 0))
                                : ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: collectionRow.isIndexing
                            text: {
                                const progress = AiRagService.indexingProgress;
                                const total = Number(progress?.chunksTotal ?? 0);
                                const done = Number(progress?.chunksDone ?? 0);
                                return total > 0
                                    ? Translation.tr("Indexing… %1 / %2 chunks").arg(done).arg(total)
                                    : Translation.tr("Indexing…");
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !collectionRow.isIndexing && AiRagService.indexingError.length > 0
                            text: AiRagService.indexingError
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3error
                        }
                    }

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        enabled: !collectionRow.isIndexing
                        onClicked: AiRagService.reindex(collectionRow.modelData.id)

                        Accessible.name: Translation.tr("Reindex")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "sync"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("Reindex")
                        }
                    }

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        visible: collectionRow.isIndexing
                        onClicked: AiRagService.cancelIndexing()

                        Accessible.name: Translation.tr("Stop indexing")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "stop"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("Stop indexing")
                        }
                    }

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainerHover
                        colRipple: Appearance.colors.colErrorContainerActive
                        onClicked: AiRagService.removeCollection(collectionRow.modelData.id)

                        Accessible.name: Translation.tr("Remove")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "delete"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnErrorContainer
                        }

                        StyledToolTip {
                            text: Translation.tr("Remove")
                        }
                    }
                }
            }
        }

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            onClicked: page.openFolderPicker()

            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    text: "create_new_folder"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    text: Translation.tr("Add a folder")
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}
