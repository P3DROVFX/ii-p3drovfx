pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A list of short strings as removable chips, with a field to type another and, when the
 * caller can offer some, a menu of suggestions (running windows, paired devices, known
 * networks…) so the user rarely has to know the exact spelling.
 *
 * The suggestions open as a side sheet beside the editor, so the row being filled in stays
 * in sight and each pick lands on it at once; the sheet stays open to pick several. The
 * sheet host is `panels`, or the first ancestor that carries one (the Modes editor does).
 * Without a host (a settings page) they fall back to a small dropdown under the button.
 */
ColumnLayout {
    id: root

    property var values: []
    property string placeholder: ""
    /// [{ label, value }] — shown under a "Pick" button; empty hides it.
    property var suggestions: []
    /// Maps a stored value to what the chip shows.
    property var display: v => v
    /// Heading of the suggestions sheet.
    property string pickTitle: Translation.tr("Pick from the list")
    /// The ClockSidePanel the suggestions open in; null looks one up the parent chain.
    property Item panels: null

    signal changed(var list)

    readonly property Item sheetHost: {
        if (root.panels)
            return root.panels;
        for (let p = root.parent; p; p = p.parent) {
            if (p.panels && typeof p.panels.show === "function")
                return p.panels;
        }
        return null;
    }
    property Item sheet: null
    readonly property bool sheetShown: root.sheet !== null && root.sheetHost !== null
        && root.sheetHost.open && root.sheetHost.current === root.sheet
    readonly property bool pickerOpen: root.sheetShown || suggestionMenu.opened

    spacing: ClockStyle.gapSmall - 2

    function toggle(value): void {
        const index = Array.from(root.values).indexOf(String(value));
        if (index === -1)
            root.add(value);
        else
            root.removeAt(index);
    }

    function openPicker(): void {
        if (root.pickerOpen) {
            if (root.sheetShown)
                root.sheetHost.close();
            else
                suggestionMenu.close();
            return;
        }
        if (!root.sheetHost) {
            suggestionMenu.open();
            return;
        }
        root.sheet = root.sheetHost.show(suggestionSheet, {
            source: root,
            title: root.pickTitle,
            placeholder: root.placeholder
        });
    }

    // Folding the form drops the field; a sheet still open for it would edit nothing.
    Component.onDestruction: {
        if (root.sheetShown)
            root.sheetHost.close();
    }

    /// The suggestions as a grouped list in a side sheet. It reads and writes through
    /// `source` (the ChipInput) and closes itself if that goes away.
    component SuggestionSheet: ClockSheet {
        id: sheet

        property Item source: null
        property string placeholder: ""
        property string query: ""

        readonly property var values: sheet.source?.values ?? []
        readonly property var filtered: {
            const all = Array.from(sheet.source?.suggestions ?? []);
            const q = sheet.query.trim().toLowerCase();
            if (!q.length)
                return all;
            return all.filter(s => String(s.label ?? "").toLowerCase().indexOf(q) !== -1
                || String(s.value ?? "").toLowerCase().indexOf(q) !== -1);
        }

        subtitle: Array.from(sheet.values).length
            ? Translation.tr("%1 picked").arg(Array.from(sheet.values).length)
            : Translation.tr("Click to add, click again to remove")
        scrollable: false

        onSourceChanged: {
            if (!sheet.source)
                sheet.close();
        }

        Component.onCompleted: Qt.callLater(search.focusInput)

        ClockFormField {
            id: search
            symbol: "search"
            shapeKind: MaterialShape.Shape.Gem
            caption: Translation.tr("Search")
            placeholder: sheet.placeholder.length ? sheet.placeholder : Translation.tr("Filter the list")
            onTextChanged: sheet.query = text
            // Enter takes the first match, or the typed text itself when nothing matches.
            onAccepted: {
                const first = sheet.filtered[0];
                if (first)
                    sheet.source?.toggle(first.value);
                else if (sheet.query.trim().length)
                    sheet.source?.add(sheet.query);
                search.text = "";
            }
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            popin: false
            animateAppearance: false
            animatePopulate: false
            model: sheet.filtered

            delegate: RippleButton {
                id: suggestion
                required property var modelData
                required property int index

                readonly property bool picked: Array.from(sheet.values).indexOf(String(suggestion.modelData.value)) !== -1

                width: list.width
                implicitHeight: 52
                // One grouped shape: large outer corners, tight joins.
                buttonRadius: Appearance.rounding.verysmall
                topLeftRadius: suggestion.index === 0 ? Appearance.rounding.large : Appearance.rounding.verysmall
                topRightRadius: topLeftRadius
                bottomLeftRadius: suggestion.index === list.count - 1 ? Appearance.rounding.large : Appearance.rounding.verysmall
                bottomRightRadius: bottomLeftRadius
                colBackground: suggestion.picked ? ClockStyle.colSecondaryContainer : ClockStyle.colField
                colBackgroundHover: suggestion.picked ? ClockStyle.colSecondaryContainerHover : ClockStyle.colFieldHover
                colRipple: suggestion.picked ? ClockStyle.colSecondaryContainerActive : ClockStyle.colSurfaceActive
                onClicked: sheet.source?.toggle(suggestion.modelData.value)

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: ClockStyle.gap
                        rightMargin: ClockStyle.gap
                    }
                    spacing: ClockStyle.gapSmall

                    MaterialSymbol {
                        text: suggestion.picked ? "check" : "add"
                        iconSize: ClockStyle.iconSmall
                        color: suggestion.picked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            id: suggestionLabel
                            Layout.fillWidth: true
                            text: String(suggestion.modelData.label ?? suggestion.modelData.value)
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: suggestion.picked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface

                            HoverHandler {
                                id: suggestionHover
                            }

                            StyledToolTip {
                                extraVisibleCondition: suggestionHover.hovered && suggestionLabel.truncated
                                text: suggestionLabel.text
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: String(suggestion.modelData.label) !== String(suggestion.modelData.value)
                            text: String(suggestion.modelData.value)
                            elide: Text.ElideMiddle
                            font.pixelSize: ClockStyle.textSmall
                            color: suggestion.picked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                        }
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: list.count === 0
                text: Translation.tr("Nothing matches — Enter adds it as typed")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colSubtext
            }
        }
    }

    Component {
        id: suggestionSheet
        SuggestionSheet {}
    }

    function add(value) {
        const v = String(value ?? "").trim();
        if (!v.length)
            return;
        const list = Array.from(root.values);
        if (list.indexOf(v) !== -1)
            return;
        list.push(v);
        root.changed(list);
    }

    function removeAt(index) {
        const list = Array.from(root.values);
        list.splice(index, 1);
        root.changed(list);
    }

    Flow {
        Layout.fillWidth: true
        visible: root.values.length > 0
        spacing: ClockStyle.gapTiny + 2

        Repeater {
            model: root.values

            delegate: Rectangle {
                id: chip
                required property string modelData
                required property int index

                implicitWidth: chipRow.implicitWidth + ClockStyle.gap + ClockStyle.gapTiny
                implicitHeight: 32
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colSecondaryContainer

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny

                    StyledText {
                        Layout.leftMargin: 2
                        text: root.display(chip.modelData)
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.Medium
                        color: ClockStyle.colOnSecondaryContainer
                    }

                    RippleButton {
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: 11
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.12)
                        colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.2)
                        onClicked: root.removeAt(chip.index)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 16
                            color: ClockStyle.colOnSecondaryContainer
                        }

                        StyledToolTip {
                            text: Translation.tr("Remove")
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ClockStyle.gapTiny + 2

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: ClockStyle.radiusSmall
            color: entry.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: entry.forceActiveFocus()
            }

            StyledTextInput {
                id: entry
                anchors {
                    fill: parent
                    leftMargin: ClockStyle.gap + 2
                    rightMargin: ClockStyle.gap + 2
                }
                verticalAlignment: TextInput.AlignVCenter
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textNormal
                clip: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.add(entry.text);
                        entry.text = "";
                        event.accepted = true;
                    }
                }
                onEditingFinished: {
                    if (entry.text.trim().length) {
                        root.add(entry.text);
                        entry.text = "";
                    }
                }

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !entry.text.length
                    text: root.placeholder
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }
        }

        RippleButton {
            id: pickButton
            visible: root.suggestions.length > 0
            implicitHeight: 40
            implicitWidth: pickRow.implicitWidth + ClockStyle.gapLarge * 2
            buttonRadius: ClockStyle.pill(40)
            buttonRadiusPressed: ClockStyle.radiusSmall
            colBackground: root.pickerOpen ? ClockStyle.colSecondaryContainer : ClockStyle.colSurfaceHigh
            colBackgroundHover: root.pickerOpen ? ClockStyle.colSecondaryContainerHover : ClockStyle.colSurfaceHover
            colRipple: ClockStyle.colSecondaryContainerActive
            onClicked: root.openPicker()

            contentItem: Item {
                implicitWidth: pickRow.implicitWidth
                implicitHeight: pickRow.implicitHeight

                RowLayout {
                    id: pickRow
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny

                    StyledText {
                        text: Translation.tr("Pick")
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: root.pickerOpen ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    }

                    // Points where the list opens (the sheet on the right, or the dropdown
                    // below) and turns back while it is open.
                    MaterialSymbol {
                        text: root.sheetHost ? "chevron_right" : "expand_more"
                        iconSize: ClockStyle.iconSmall + 2
                        rotation: root.pickerOpen ? 180 : 0
                        color: root.pickerOpen ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant

                        Behavior on rotation {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                    }
                }
            }

            // Fallback for hosts without a side panel (the settings page).
            Popup {
                id: suggestionMenu
                y: parent.height + ClockStyle.gapTiny
                x: parent.width - width
                width: 300
                height: Math.min(320, suggestionList.contentHeight + ClockStyle.gapSmall * 2)
                padding: ClockStyle.gapSmall
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                enter: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: ClockStyle.motionFast.duration
                    }
                }
                exit: Transition {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: ClockStyle.motionFast.duration
                    }
                }

                background: Rectangle {
                    radius: ClockStyle.radiusLarge
                    color: ClockStyle.colSheet

                    StyledRectangularShadow {
                        target: parent
                    }
                }

                contentItem: StyledListView {
                    id: suggestionList
                    clip: true
                    spacing: 2
                    popin: false
                    animateAppearance: false
                    animatePopulate: false
                    model: root.suggestions

                    delegate: RippleButton {
                        id: suggestion
                        required property var modelData

                        width: suggestionList.width
                        implicitHeight: 44
                        buttonRadius: ClockStyle.radiusSmall
                        colBackground: "transparent"
                        colBackgroundHover: ClockStyle.colFieldHover
                        colRipple: ClockStyle.colSurfaceActive
                        onClicked: {
                            root.add(suggestion.modelData.value);
                            suggestionMenu.close();
                        }

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: ClockStyle.gap
                                rightMargin: ClockStyle.gap
                            }
                            spacing: ClockStyle.gapSmall

                            MaterialSymbol {
                                text: Array.from(root.values).indexOf(String(suggestion.modelData.value)) !== -1 ? "check" : "add"
                                iconSize: ClockStyle.iconSmall
                                color: ClockStyle.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: suggestion.modelData.label
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                color: ClockStyle.colOnSurface
                            }

                            StyledText {
                                visible: suggestion.modelData.label !== suggestion.modelData.value
                                text: suggestion.modelData.value
                                elide: Text.ElideMiddle
                                Layout.maximumWidth: 120
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
