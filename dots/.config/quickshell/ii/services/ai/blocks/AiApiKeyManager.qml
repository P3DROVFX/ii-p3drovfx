pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Keys, in one place, for every provider that needs one.
 *
 * The only way to set a key used to be `/key VALUE`, typed into the chat —
 * which meant the secret was echoed into the transcript, and the way to find
 * out whether it worked was to send a real message and read an HTTP number.
 * Here a key is entered masked, and "Test connection" says in words what the
 * endpoint thinks of it.
 */
Item {
    id: root

    signal closed

    /** One card per key, not per provider: several can share a key id. */
    readonly property var entries: {
        const seen = {};
        const result = [];
        for (const id of Ai.providerIds) {
            const provider = Ai.providers[id];
            if (!provider?.requires_key)
                continue;
            const keyId = provider.key_id;
            if (!keyId || keyId.length === 0 || seen[keyId])
                continue;
            seen[keyId] = true;
            result.push(provider);
        }
        return result;
    }

    implicitHeight: contentColumnLayout.implicitHeight

    component KeyCard: Rectangle {
        id: card

        property var provider: null
        readonly property string keyId: card.provider?.key_id ?? ""
        readonly property string storedKey: Ai.apiKeys?.[card.keyId] ?? ""
        readonly property bool hasKey: card.storedKey.length > 0
        readonly property bool dirty: keyInput.text !== card.storedKey
        readonly property bool testing: Ai.keyTestId === card.keyId && Ai.keyTestState === "running"
        readonly property string testResult: Ai.keyTestId === card.keyId ? Ai.keyTestState : ""
        property bool revealed: false

        Layout.fillWidth: true
        implicitHeight: cardColumnLayout.implicitHeight + 12 * 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: cardColumnLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Loader {
                    active: (card.provider?.icon ?? "").length > 0
                    visible: active
                    sourceComponent: CustomIcon {
                        source: card.provider?.icon ?? ""
                        width: Appearance.font.pixelSize.larger
                        height: Appearance.font.pixelSize.larger
                        colorize: true
                        color: Appearance.colors.colOnLayer2
                    }
                }

                Loader {
                    active: (card.provider?.icon ?? "").length === 0
                    visible: active
                    sourceComponent: MaterialSymbol {
                        text: card.provider?.materialIcon ?? "key"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.provider?.name ?? card.keyId
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer2
                }

                Rectangle {
                    // Set, unset, or just refused: the one thing worth seeing
                    // without reading anything.
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: width / 2
                    color: {
                        if (card.testResult === "failed")
                            return Appearance.m3colors.m3error;
                        if (card.hasKey)
                            return Appearance.m3colors.m3primary;
                        return ColorUtils.transparentize(Appearance.colors.colSubtext, 0.5);
                    }
                }

                StyledText {
                    text: card.hasKey ? Translation.tr("Key set") : Translation.tr("No key")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 4

                    StyledTextInput {
                        id: keyInput
                        Layout.fillWidth: true
                        // The binding survives until the field is typed into,
                        // so a key that arrives from the keyring after this
                        // panel opened still shows up.
                        text: card.storedKey
                        echoMode: card.revealed ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        clip: true
                        onAccepted: Ai.setApiKeyFor(card.keyId, keyInput.text)

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: keyInput.text.length === 0
                            text: Translation.tr("Paste the key here")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.full
                        enabled: keyInput.text.length > 0
                        opacity: enabled ? 1 : 0.4
                        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: card.revealed = !card.revealed

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: card.revealed ? "visibility_off" : "visibility"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: card.revealed ? Translation.tr("Hide") : Translation.tr("Show")
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                RippleButton {
                    id: saveButton
                    leftPadding: 12
                    rightPadding: 12
                    topPadding: 5
                    bottomPadding: 5
                    buttonRadius: Appearance.rounding.full
                    enabled: card.dirty
                    opacity: enabled ? 1 : 0.4
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: Ai.setApiKeyFor(card.keyId, keyInput.text)

                    contentItem: StyledText {
                        text: Translation.tr("Save")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onPrimary
                    }
                }

                RippleButton {
                    leftPadding: 12
                    rightPadding: 12
                    topPadding: 5
                    bottomPadding: 5
                    buttonRadius: Appearance.rounding.full
                    enabled: card.hasKey && !card.dirty && !card.testing
                    opacity: enabled ? 1 : 0.4
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: Ai.testApiKey(card.keyId)

                    contentItem: RowLayout {
                        spacing: 5

                        MaterialSymbol {
                            text: card.testing ? "progress_activity" : "network_check"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1

                            RotationAnimator on rotation {
                                running: card.testing
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 1000
                            }
                        }

                        StyledText {
                            text: card.testing ? Translation.tr("Testing…") : Translation.tr("Test connection")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    StyledToolTip {
                        text: card.dirty ? Translation.tr("Save the key first") : Translation.tr("Sends one tiny message to check the key")
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButton {
                    visible: (card.provider?.key_get_link ?? "").length > 0
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: Qt.openUrlExternally(card.provider.key_get_link)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: Translation.tr("Get a key")
                    }
                }

                RippleButton {
                    visible: card.hasKey
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: {
                        Ai.setApiKeyFor(card.keyId, "");
                        keyInput.text = "";
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: Translation.tr("Remove this key")
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: card.testResult === "ok" || card.testResult === "failed"
                text: Ai.keyTestMessage
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: card.testResult === "ok" ? Appearance.colors.colOnLayer2 : Appearance.m3colors.m3error
            }

            StyledText {
                // What the provider says about getting one — pricing, and the
                // clicks it takes — rather than a bare link.
                Layout.fillWidth: true
                visible: !card.hasKey && (card.provider?.key_get_description ?? "").length > 0
                text: card.provider?.key_get_description ?? ""
                wrapMode: Text.Wrap
                textFormat: Text.MarkdownText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    ColumnLayout {
        id: contentColumnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // Reaches the bottom when the host gives this a height, so the list
        // inside can take the room instead of stopping at a fixed cap.
        anchors.bottom: root.height > contentColumnLayout.implicitHeight ? parent.bottom : undefined
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("API keys")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            StyledText {
                visible: !Ai.apiKeysLoaded
                text: Translation.tr("Reading the keyring…")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StyledFlickable {
            Layout.fillWidth: true
            // Takes the leftover height of the view rather than a fixed cap:
            // as a panel this scroller had 340px to live in, as a canvas view
            // it has the whole middle rectangle.
            Layout.fillHeight: true
            implicitHeight: cardsColumnLayout.implicitHeight
            contentWidth: width
            contentHeight: cardsColumnLayout.implicitHeight
            clip: true

            ColumnLayout {
                id: cardsColumnLayout
                width: parent.width
                spacing: 6

                Repeater {
                    model: ScriptModel {
                        values: root.entries
                    }

                    delegate: KeyCard {
                        required property var modelData
                        provider: modelData
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Keys are kept in the system keyring, never in the chat.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
}
