import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("System Prompt & Privacy")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "description"
            title: Translation.tr("System Prompt")
            tooltip: Translation.tr("Base instructions provided to all model requests when no custom persona is selected.")

            TipBox {
                Layout.fillWidth: true
                text: Translation.tr("A persona replaces this while it is picked. This is what the assistant falls back to.")
            }

            ScrollView {
                id: promptScroll
                Layout.fillWidth: true
                implicitHeight: Math.min(systemPromptArea.implicitHeight, 240)
                clip: true

                ScrollBar.vertical: ScrollBar {
                    id: promptScrollBar
                    policy: ScrollBar.AsNeeded
                    opacity: size < 1 ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2Active
                    }
                }

                MaterialTextArea {
                    id: systemPromptArea
                    width: promptScroll.width
                    placeholderText: Translation.tr("System prompt")
                    text: Config.options.ai.systemPrompt
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Qt.callLater(() => {
                            Config.options.ai.systemPrompt = text;
                        });
                    }
                }
            }
        }

        ContentSection {
            icon: "privacy_tip"
            title: Translation.tr("Privacy & context")
            tooltip: Translation.tr("Manage how active window information and attachments are shared.")

            TipBox {
                Layout.fillWidth: true
                text: Translation.tr("Clipboard text, a launcher result, and active-app metadata are sent only when you attach them in the composer. Each attachment shows its source, size, destination, and a remove action before sending.")
            }

            TipBox {
                Layout.fillWidth: true
                text: String(Config.options.ai.systemPrompt ?? "").includes("{WINDOWCLASS}")
                    ? Translation.tr("Your system prompt currently includes {WINDOWCLASS}; it is replaced with the active application's class on every request.")
                    : Translation.tr("Your system prompt does not include active-window metadata.")
            }

            RippleButton {
                Layout.fillWidth: true
                visible: String(Config.options.ai.systemPrompt ?? "").includes("{WINDOWCLASS}")
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: Config.options.ai.systemPrompt = String(Config.options.ai.systemPrompt ?? "").replace("{WINDOWCLASS}", "")

                contentItem: RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        text: "visibility_off"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Remove active-window metadata from the prompt")
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
