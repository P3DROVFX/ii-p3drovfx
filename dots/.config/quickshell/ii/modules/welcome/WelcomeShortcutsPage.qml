pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The keyboard, and where the rest of it lives.
 *
 * The onboarding used to end without teaching a single key, which on a
 * keyboard-driven shell is the one omission a new user cannot recover from on
 * their own. The lesson of the page is not the eleven shortcuts on it — it is
 * the last card: forget one, and the cheatsheet has all of them.
 *
 * Nothing here spells a key combination. Every card resolves its own keys from
 * the descriptions Hyprland parsed out of the real config, so a rebound key
 * shows up rebound and an unbound one says so.
 */
Item {
    id: root

    property bool nextButtonHovered: false

    signal openSettingsTarget(string pageId, string subPageId, string sectionId)

    readonly property bool compactWidth: root.width < Appearance.rounding.verylarge * 22
    readonly property var cheatsheetKeys: WelcomeKeybindRegistry.keysFor("cheatsheet")
    /**
     * How many of the four the reader has actually pressed. Shown, never
     * required: the step advances the same whether this is four or zero.
     */
    readonly property int triedCount: WelcomeKeybindRegistry.performedEverydayCount
    /**
     * Three, on one row. The page is not a reference — the card at the bottom
     * is, and every card added above it pushes that card under the navigation
     * on a short window.
     */
    readonly property var secondaryActions: WelcomeKeybindRegistry.exploreActions.slice(0, 3)

    function openCheatsheet(): void {
        root.openSettingsTarget("cheatSheet", "", "keyboard");
    }

    /**
     * A click on a card does what the card says, not what the page is about.
     * Unbound actions have nothing to run, and those fall back to the place
     * that can tell the reader why — the cheatsheet.
     */
    function runShortcut(actionId: string): void {
        if (WelcomeKeybindRegistry.trigger(actionId)) {
            // Ticked here as well as by the watcher: a few of these open
            // something the shell publishes no flag for, and having run it
            // from the card is exactly as true as having pressed the key.
            WelcomeKeybindRegistry.markPerformed(actionId);
            return;
        }
        root.openCheatsheet();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.small

        // Two across, not four: a hero card carries its title and its keycaps
        // on one line, and four columns left "Search" — the shortest label on
        // the page — elided to "Sear…" next to a two-key combination.
        GridLayout {
            Layout.fillWidth: true
            columns: root.compactWidth ? 1 : 2
            columnSpacing: Appearance.rounding.small
            rowSpacing: Appearance.rounding.small

            Repeater {
                model: WelcomeKeybindRegistry.everydayActions

                delegate: WelcomeKeybindCard {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    hero: true
                    materialIcon: modelData.icon
                    title: Translation.tr(modelData.labelKey)
                    keys: WelcomeKeybindRegistry.keysFor(modelData.id)
                    unassignedText: Translation.tr("Not assigned")
                    performed: WelcomeKeybindRegistry.hasPerformed(modelData.id)
                    onActivated: root.runShortcut(modelData.id)
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.compactWidth ? 2 : 3
            columnSpacing: Appearance.rounding.small
            rowSpacing: Appearance.rounding.small

            Repeater {
                model: root.secondaryActions

                delegate: WelcomeKeybindCard {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    materialIcon: modelData.icon
                    title: Translation.tr(modelData.labelKey)
                    keys: WelcomeKeybindRegistry.keysFor(modelData.id)
                    unassignedText: Translation.tr("Not assigned")
                    performed: WelcomeKeybindRegistry.hasPerformed(modelData.id)
                    onActivated: root.runShortcut(modelData.id)
                }
            }
        }

        Item { Layout.fillHeight: true }

        // The point of the page.
        Rectangle {
            id: cheatsheetCard

            Layout.fillWidth: true
            implicitHeight: cheatsheetContent.implicitHeight + Appearance.rounding.normal * 2
            radius: Appearance.rounding.large
            color: Appearance.colors.colTertiaryContainer

            RowLayout {
                id: cheatsheetContent

                anchors.fill: parent
                anchors.margins: Appearance.rounding.normal
                spacing: Appearance.rounding.small

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "help"
                    shape: MaterialShape.Shape.Cookie9Sided
                    iconSize: Appearance.font.pixelSize.large
                    padding: Appearance.rounding.small
                    fill: 1
                    color: Appearance.colors.colTertiary
                    colSymbol: Appearance.colors.colOnTertiary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.triedCount > 0
                            ? Translation.tr("Nice — you don't have to remember the rest either")
                            : Translation.tr("Try one now, or don't — they're all in the cheatsheet")
                        color: Appearance.colors.colOnTertiaryContainer
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.triedCount > 0
                            ? Translation.tr("%1 of %2 tried — the cheatsheet has the other %3.")
                                .arg(String(root.triedCount))
                                .arg(String(WelcomeKeybindRegistry.everydayActions.length))
                                .arg(String(Math.max(0, WelcomeKeybindRegistry.describedKeybindCount - root.triedCount)))
                            : WelcomeKeybindRegistry.describedKeybindCount > 0
                            ? Translation.tr("The cheatsheet lists all %1 shortcuts, and stays in sync with your config.")
                                .arg(String(WelcomeKeybindRegistry.describedKeybindCount))
                            : Translation.tr("The cheatsheet lists every shortcut, and stays in sync with your config.")
                        color: Appearance.colors.colOnTertiaryContainer
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.cheatsheetKeys.length > 0
                    spacing: Appearance.rounding.unsharpen

                    Repeater {
                        model: root.cheatsheetKeys

                        delegate: RowLayout {
                            required property string modelData
                            required property int index

                            spacing: Appearance.rounding.unsharpen

                            KeyboardKey {
                                key: modelData
                                pixelSize: Appearance.font.pixelSize.smaller
                            }

                            StyledText {
                                visible: index < root.cheatsheetKeys.length - 1
                                text: "+"
                                color: Appearance.colors.colOnTertiaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }
                }

                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: Appearance.rounding.verylarge + Appearance.rounding.verysmall
                    centerContent: true
                    materialIcon: "open_in_new"
                    mainText: Translation.tr("Open it now")
                    textPixelSize: Appearance.font.pixelSize.small
                    iconPixelSize: Appearance.font.pixelSize.large
                    buttonRadius: Appearance.rounding.full
                    colText: Appearance.colors.colOnTertiary
                    colBackground: Appearance.colors.colTertiary
                    colBackgroundHover: Appearance.colors.colTertiaryHover
                    colBackgroundActive: Appearance.colors.colTertiaryActive
                    colRipple: Appearance.colors.colTertiaryActive
                    onClicked: root.openCheatsheet()
                }
            }
        }
    }
}
