pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Which program a shortcut opens, and what it falls back to.
 *
 * These are not one command but a list tried in order: the first one that is installed runs.
 * That is what makes a config portable, and also what makes it surprising - installing a second
 * terminal can quietly take Super+Return away from the first, which is exactly what happened
 * here once. So the list is shown in order, each entry says whether it is installed, and the one
 * that would actually run is named at the top.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    readonly property string name: HyprlandBinds.editApp
    readonly property var entry: HyprlandBinds.appEntry(subPageRoot.name)
    readonly property string value: HyprlandBinds.appValue(subPageRoot.name)
    readonly property var chain: HyprlandBinds.readChain(subPageRoot.value)
    readonly property string source: HyprlandBinds.appSource(subPageRoot.name)
    readonly property string winner: HyprlandBinds.winningCandidate(subPageRoot.chain.candidates)
    readonly property string selectedCommand: subPageRoot.chain.chain ? subPageRoot.winner : subPageRoot.value

    function commit(candidates: var) {
        HyprlandBinds.saveApp(subPageRoot.name,
            HyprlandBinds.writeChain(subPageRoot.chain.prefix, candidates));
    }

    function move(from: int, to: int) {
        const list = Array.from(subPageRoot.chain.candidates);
        if (from < 0 || to < 0 || from >= list.length || to >= list.length || from === to) return;
        list.splice(to, 0, list.splice(from, 1)[0]);
        subPageRoot.commit(list);
    }

    function drop(index: int) {
        const list = Array.from(subPageRoot.chain.candidates);
        list.splice(index, 1);
        subPageRoot.commit(list);
    }

    function add(candidate: string) {
        const text = String(candidate ?? "").trim();
        if (text === "") return;
        subPageRoot.commit(Array.from(subPageRoot.chain.candidates).concat([text]));
    }

    function appIcon(candidate: string): string {
        return AppSearch.guessIcon(HyprlandBinds.probeWord(candidate));
    }

    component RowButton: RippleButton {
        id: rowButton

        property string buttonIcon: ""

        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        MaterialSymbol {
            anchors.centerIn: parent
            text: rowButton.buttonIcon
            iconSize: 18
            color: Appearance.colors.colSubtext
            opacity: rowButton.enabled ? 1 : 0.3
        }
    }

    /**
     * One candidate. The order is the whole point of this list, so it is changed by dragging
     * rather than by a pair of arrows: two clicks to move an entry up two places used to be two
     * writes and two config reloads, and the list under the pointer moved between them.
     */
    component CandidateRow: RippleButton {
        id: candidateRow

        required property string candidate
        required property int index
        property bool draggable: true
        property bool ghost: false

        signal dragStarted(real y)
        signal dragMoved(real y)
        signal dragEnded

        readonly property var installed: HyprlandBinds.candidateAvailable(candidateRow.candidate)
        readonly property bool winning: candidateRow.candidate === subPageRoot.winner

        implicitHeight: 52
        useDynamicRadius: true
        colBackground: candidateRow.winning ? Appearance.colors.colPrimaryContainer
            : Appearance.colors.colLayer2
        colBackgroundHover: candidateRow.winning ? Appearance.colors.colPrimaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: candidateRow.winning ? Appearance.colors.colPrimaryContainerActive
            : Appearance.colors.colLayer2Active

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            MouseArea {
                id: handle
                visible: candidateRow.draggable
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 22
                implicitHeight: 40
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // Without this the page's own flick takes the drag away as soon as it moves.
                preventStealing: true

                onPressed: mouse => candidateRow.dragStarted(handle.mapToItem(candidateRow, mouse.x, mouse.y).y)
                onPositionChanged: mouse => {
                    if (handle.pressed)
                        candidateRow.dragMoved(handle.mapToItem(candidateRow, mouse.x, mouse.y).y);
                }
                onReleased: candidateRow.dragEnded()
                onCanceled: candidateRow.dragEnded()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "drag_indicator"
                    iconSize: 20
                    color: candidateRow.winning ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
                    opacity: candidateRow.hovered || handle.containsMouse || candidateRow.ghost ? 1 : 0.35

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: candidateRow.installed === true ? "check_circle"
                    : (candidateRow.installed === false ? "cancel" : "help")
                iconSize: Appearance.font.pixelSize.large
                color: candidateRow.installed === true
                    ? (candidateRow.winning ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colPrimary)
                        : Appearance.colors.colSubtext
            }

            IconImage {
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 24
                source: Quickshell.iconPath(subPageRoot.appIcon(candidateRow.candidate), "application-x-executable")
                opacity: candidateRow.installed === false ? 0.4 : 1
            }

            StyledText {
                Layout.fillWidth: true
                text: candidateRow.candidate
                elide: Text.ElideRight
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: candidateRow.winning ? Appearance.colors.colOnPrimaryContainer
                    : (candidateRow.installed === false ? Appearance.colors.colSubtext
                        : Appearance.colors.colOnLayer2)
            }

            RowButton {
                buttonIcon: "close"
                visible: !candidateRow.ghost
                onClicked: subPageRoot.drop(candidateRow.index)
            }
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            IconImage {
                Layout.alignment: Qt.AlignVCenter
                visible: subPageRoot.selectedCommand !== ""
                implicitSize: 32
                source: Quickshell.iconPath(subPageRoot.appIcon(subPageRoot.selectedCommand), "application-x-executable")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: subPageRoot.entry.label
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: subPageRoot.selectedCommand === "" ? Translation.tr("Nothing in this list is installed.")
                        : Translation.tr("Opens %1").arg(subPageRoot.selectedCommand)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: subPageRoot.selectedCommand === "" ? Appearance.colors.colError
                        : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // ── The list ──────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Tried in this order")
            icon: "list"
            visible: subPageRoot.chain.chain

            DragOrderList {
                id: chainList
                Layout.fillWidth: true
                count: subPageRoot.chain.candidates.length
                flick: page.flickable
                onMoved: (from, to) => subPageRoot.move(from, to)

                delegate: CandidateRow {
                    id: chainRow

                    Layout.fillWidth: true
                    candidate: String(subPageRoot.chain.candidates[chainRow.index] ?? "")
                    draggable: chainList.count > 1
                    opacity: chainList.dragFrom === chainRow.index ? 0 : 1

                    transform: Translate {
                        y: chainList.shiftFor(chainRow.index)

                        Behavior on y {
                            enabled: chainList.dragging
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }

                    onDragStarted: y => {
                        chainList.pointerY = chainRow.mapToItem(chainList, 0, y).y;
                        chainList.beginDrag(chainRow.index, y);
                    }
                    onDragMoved: y => chainList.pointerMoved(chainRow, y)
                    onDragEnded: chainList.endDrag()
                }

                ghostDelegate: Item {
                    implicitHeight: ghostRow.implicitHeight

                    StyledRectangularShadow {
                        target: ghostRow
                    }

                    CandidateRow {
                        id: ghostRow
                        anchors {
                            left: parent.left
                            right: parent.right
                        }
                        index: chainList.dragFrom
                        candidate: String(subPageRoot.chain.candidates[chainList.dragFrom] ?? "")
                        ghost: true
                        enabled: false
                        scale: 1.01
                    }
                }
            }

            ConfigTextField {
                id: addField
                Layout.fillWidth: true

                icon: "add"
                text: Translation.tr("Add one")
                placeholderText: Translation.tr("ghostty")

                Connections {
                    target: addField.textField

                    function onAccepted() {
                        subPageRoot.add(addField.inputText);
                        addField.inputText = "";
                    }
                }
            }

            HyprOptionNote {
                notes: {
                    const out = [{ "icon": "info", "text": Translation.tr("The first installed one wins, so the order is the choice. Drag a row by its handle to change it. A tick means the command exists on this machine right now.") }];
                    if (subPageRoot.winner !== "" && subPageRoot.chain.candidates.length > 0
                        && subPageRoot.winner !== subPageRoot.chain.candidates[0])
                        out.push({ "icon": "swap_vert", "text": Translation.tr("%1 is above %2 in the list but is not installed, so it is skipped.")
                            .arg(subPageRoot.chain.candidates[0]).arg(subPageRoot.winner) });
                    return out;
                }
            }
        }

        // ── Not a list ────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Command")
            icon: "terminal"
            visible: !subPageRoot.chain.chain

            ConfigTextField {
                id: plainField
                Layout.fillWidth: true

                readonly property string currentValue: subPageRoot.value

                icon: subPageRoot.entry.icon
                text: subPageRoot.entry.label
                textField.wrapMode: TextInput.NoWrap

                onCurrentValueChanged: {
                    if (plainField.textField.activeFocus) return;
                    plainField.inputText = plainField.currentValue;
                }
                Component.onCompleted: plainField.inputText = plainField.currentValue

                Connections {
                    target: plainField.textField

                    function onEditingFinished() {
                        if (plainField.inputText === plainField.currentValue) return;
                        HyprlandBinds.saveApp(subPageRoot.name, plainField.inputText);
                    }
                }
            }

            HyprOptionNote {
                notes: [{ "icon": "info", "text": Translation.tr("This one is a single command rather than a list of fallbacks, so it is edited as text.") }]
            }
        }

        // ── Where it comes from ───────────────────────────────────────────────
        ContentSection {
            visible: Config.options.hyprland.advancedSettings
            title: Translation.tr("Where this comes from")
            icon: "history"

            HyprNavRow {
                visible: subPageRoot.source === "managed"
                buttonIcon: "undo"
                text: Translation.tr("Undo what this page set")
                value: Translation.tr("Back to the config file")
                onOpenSubPage: HyprlandBinds.resetApp(subPageRoot.name)
            }

            HyprOptionNote {
                notes: {
                    if (subPageRoot.source === "managed")
                        return [{ "icon": "edit", "text": Translation.tr("Set by this page, in the block at the end of custom/variables.lua.") },
                            { "icon": "restart_alt", "text": Translation.tr("The shortcut picks this up on the next config reload, which happens as soon as the file is written.") }];
                    if (subPageRoot.source === "custom")
                        return [{ "icon": "edit_note", "text": Translation.tr("Written by hand in custom/variables.lua. Changing it here leaves that line alone and adds one below it, which runs afterwards and wins.") }];
                    return [{ "icon": "inventory", "text": Translation.tr("This is the shipped default, from hyprland/variables.lua. That file is replaced on every update, so changes go into custom/variables.lua instead.") }];
                }
            }
        }
    }
}
