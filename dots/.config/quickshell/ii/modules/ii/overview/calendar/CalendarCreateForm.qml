pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property date initialDate: new Date()
    property int defaultDurationMinutes: 30
    property string errorText: ""
    property bool busy: false
    property bool validationAttempted: false
    signal submitted(var fields)
    signal cancelled()

    implicitHeight: formColumn.implicitHeight

    function normalizedDate(value) {
        const match = String(value ?? "").trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
        if (!match)
            return null;
        const result = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
        return isNaN(result.getTime()) ? null : result;
    }

    function normalizedTime(value) {
        return /^([01]\d|2[0-3]):[0-5]\d$/.test(String(value ?? "").trim());
    }

    function localIso(dateValue, timeValue) {
        return Qt.formatDate(dateValue, "yyyy-MM-dd") + "T" + timeValue + ":00";
    }

    function reset() {
        const start = root.initialDate instanceof Date && !isNaN(root.initialDate.getTime())
            ? root.initialDate
            : new Date();
        const roundedMinutes = Math.ceil(start.getMinutes() / 15) * 15;
        start.setMinutes(roundedMinutes, 0, 0);
        const end = new Date(start.getTime() + Math.max(1, root.defaultDurationMinutes) * 60000);
        titleField.text = "";
        startDateField.text = Qt.formatDate(start, "yyyy-MM-dd");
        endDateField.text = Qt.formatDate(end, "yyyy-MM-dd");
        startTimeField.text = Qt.formatTime(start, "HH:mm");
        endTimeField.text = Qt.formatTime(end, "HH:mm");
        locationField.text = "";
        allDayButton.toggled = false;
        root.errorText = "";
        root.validationAttempted = false;
    }

    function focusFirst() {
        titleField.inputItem.forceActiveFocus();
        titleField.inputItem.selectAll();
    }

    function submit() {
        root.validationAttempted = true;
        const title = titleField.text.trim();
        const startDate = root.normalizedDate(startDateField.text);
        const endDate = root.normalizedDate(endDateField.text);
        if (title.length === 0) {
            root.errorText = Translation.tr("Add an event name");
            root.focusFirst();
            return false;
        }
        if (!startDate || !endDate || (!allDayButton.toggled
                && (!root.normalizedTime(startTimeField.text) || !root.normalizedTime(endTimeField.text)))) {
            root.errorText = Translation.tr("Check the date and time fields");
            return false;
        }

        let start = allDayButton.toggled
            ? Qt.formatDate(startDate, "yyyy-MM-dd")
            : root.localIso(startDate, startTimeField.text.trim());
        let end = allDayButton.toggled
            ? Qt.formatDate(endDate, "yyyy-MM-dd")
            : root.localIso(endDate, endTimeField.text.trim());
        if (new Date(end) <= new Date(start)) {
            if (allDayButton.toggled) {
                const nextDay = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate() + 1);
                end = Qt.formatDate(nextDay, "yyyy-MM-dd");
            } else {
                root.errorText = Translation.tr("End time must be after start time");
                return false;
            }
        }

        root.errorText = "";
        root.validationAttempted = false;
        root.submitted({
            summary: title,
            start: start,
            end: end,
            allDay: allDayButton.toggled,
            location: locationField.text.trim(),
            description: ""
        });
        return true;
    }

    Keys.onEscapePressed: event => {
        root.cancelled();
        event.accepted = true;
    }

    component LabeledField: Rectangle {
        id: labeledFieldRoot

        property alias text: fieldInput.text
        property alias inputItem: fieldInput
        property string label: ""
        property string symbol: "edit"
        property string placeholder: ""
        property string supportingText: ""
        property bool required: false
        property bool invalid: false
        property Item tabTarget: null
        signal accepted()

        implicitHeight: Appearance.sizes.elevationMargin * 8
        radius: fieldInput.activeFocus ? Appearance.rounding.full : Appearance.rounding.large
        color: invalid
            ? Appearance.colors.colErrorContainer
            : fieldInput.activeFocus
                ? Appearance.colors.colSecondaryContainer
                : Appearance.colors.colSurfaceContainerHigh

        Behavior on radius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            spacing: Appearance.sizes.elevationMargin

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                shape: fieldInput.activeFocus
                    ? MaterialShape.Shape.Circle
                    : MaterialShape.Shape.Clover4Leaf
                text: labeledFieldRoot.symbol
                iconSize: Appearance.font.pixelSize.large
                padding: Appearance.sizes.elevationMargin * 0.7
                color: labeledFieldRoot.invalid
                    ? Appearance.colors.colError
                    : fieldInput.activeFocus
                        ? Appearance.colors.colSecondary
                        : Appearance.colors.colSurfaceContainerHighest
                colSymbol: labeledFieldRoot.invalid
                    ? Appearance.colors.colOnError
                    : fieldInput.activeFocus
                        ? Appearance.colors.colOnSecondary
                        : Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Appearance.sizes.elevationMargin / 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.elevationMargin / 2

                    StyledText {
                        Layout.fillWidth: true
                        text: labeledFieldRoot.label
                        color: labeledFieldRoot.invalid
                            ? Appearance.colors.colOnErrorContainer
                            : Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        text: labeledFieldRoot.required
                            ? Translation.tr("Required")
                            : labeledFieldRoot.supportingText
                        visible: text.length > 0
                        color: labeledFieldRoot.invalid
                            ? Appearance.colors.colOnErrorContainer
                            : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                ToolbarTextField {
                    id: fieldInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholderText: labeledFieldRoot.placeholder
                    colBackground: labeledFieldRoot.invalid
                        ? Appearance.colors.colErrorContainer
                        : fieldInput.activeFocus
                            ? Appearance.colors.colSecondaryContainer
                            : Appearance.colors.colSurfaceContainerHighest
                    enabled: !root.busy
                    KeyNavigation.tab: labeledFieldRoot.tabTarget
                    onAccepted: labeledFieldRoot.accepted()
                }
            }
        }
    }

    component CompactField: ColumnLayout {
        id: compactFieldRoot

        property alias text: compactInput.text
        property alias inputItem: compactInput
        property string label: ""
        property string symbol: "edit_calendar"
        property string placeholder: ""
        property bool invalid: false
        property Item tabTarget: null
        signal accepted()

        implicitHeight: Appearance.sizes.elevationMargin * 5
        spacing: Appearance.sizes.elevationMargin / 4

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin / 2

            MaterialSymbol {
                text: compactFieldRoot.symbol
                iconSize: Appearance.font.pixelSize.small
                color: compactFieldRoot.invalid
                    ? Appearance.colors.colError
                    : Appearance.colors.colOutline
            }

            StyledText {
                text: compactFieldRoot.label
                color: compactFieldRoot.invalid
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }
        }

        ToolbarTextField {
            id: compactInput
            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholderText: compactFieldRoot.placeholder
            colBackground: compactFieldRoot.invalid
                ? Appearance.colors.colErrorContainer
                : compactInput.activeFocus
                    ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colSurfaceContainerHighest
            enabled: !root.busy
            KeyNavigation.tab: compactFieldRoot.tabTarget
            onAccepted: compactFieldRoot.accepted()
        }
    }

    ColumnLayout {
        id: formColumn
        anchors.fill: parent
        spacing: Appearance.sizes.elevationMargin

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Appearance.sizes.elevationMargin * 5
            spacing: Appearance.sizes.elevationMargin

            RippleButton {
                id: backButton
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.cancelled()

                StyledToolTip {
                    text: Translation.tr("Back to calendar")
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurface
                }
            }

            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.Cookie6Sided
                text: "event"
                iconSize: Appearance.font.pixelSize.large
                padding: Appearance.sizes.elevationMargin
                color: Appearance.colors.colTertiaryContainer
                colSymbol: Appearance.colors.colOnTertiaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Create event")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    text: Translation.tr("Add the essentials now; refine details later in Calendar")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            id: formBody
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.sizes.elevationMargin

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.horizontalStretchFactor: 4
                spacing: Appearance.sizes.elevationMargin

                LabeledField {
                    id: titleField
                    Layout.fillWidth: true
                    label: Translation.tr("Event title")
                    symbol: "title"
                    placeholder: Translation.tr("e.g. Project review")
                    required: true
                    invalid: root.validationAttempted && text.trim().length === 0
                    tabTarget: startDateField.inputItem
                    onAccepted: startDateField.inputItem.forceActiveFocus()
                }

                LabeledField {
                    id: locationField
                    Layout.fillWidth: true
                    label: Translation.tr("Location")
                    symbol: "location_on"
                    placeholder: Translation.tr("Room, address or meeting link")
                    supportingText: Translation.tr("Optional")
                    tabTarget: allDayButton
                    onAccepted: allDayButton.forceActiveFocus()
                }

                RippleButton {
                    id: allDayButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.sizes.elevationMargin * 7
                    buttonRadius: toggled ? Appearance.rounding.full : Appearance.rounding.large
                    colBackground: toggled
                        ? Appearance.colors.colTertiaryContainer
                        : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: toggled
                        ? Appearance.colors.colTertiaryContainerHover
                        : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: toggled
                        ? Appearance.colors.colTertiaryContainerActive
                        : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: toggled = !toggled
                    KeyNavigation.tab: createEventButton

                    contentItem: Item {
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin

                            MaterialShapeWrappedMaterialSymbol {
                                shape: allDayButton.toggled
                                    ? MaterialShape.Shape.Circle
                                    : MaterialShape.Shape.Clover4Leaf
                                text: allDayButton.toggled ? "event_available" : "schedule"
                                iconSize: Appearance.font.pixelSize.large
                                padding: Appearance.sizes.elevationMargin * 0.7
                                color: allDayButton.toggled
                                    ? Appearance.colors.colTertiary
                                    : Appearance.colors.colSurfaceContainerHighest
                                colSymbol: allDayButton.toggled
                                    ? Appearance.colors.colOnTertiary
                                    : Appearance.colors.colOnSurfaceVariant
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    text: Translation.tr("All-day event")
                                    color: allDayButton.toggled
                                        ? Appearance.colors.colOnTertiaryContainer
                                        : Appearance.colors.colOnSurface
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                StyledText {
                                    text: allDayButton.toggled
                                        ? Translation.tr("Times are hidden; dates define the event")
                                        : Translation.tr("Use exact start and end times")
                                    color: allDayButton.toggled
                                        ? Appearance.colors.colOnTertiaryContainer
                                        : Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideRight
                                }
                            }

                            MaterialSymbol {
                                text: allDayButton.toggled ? "check_circle" : "circle"
                                fill: allDayButton.toggled ? 1 : 0
                                iconSize: Appearance.font.pixelSize.large
                                color: allDayButton.toggled
                                    ? Appearance.colors.colOnTertiaryContainer
                                    : Appearance.colors.colOutline
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.horizontalStretchFactor: 6
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin
                    spacing: Appearance.sizes.elevationMargin / 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.elevationMargin

                        MaterialShapeWrappedMaterialSymbol {
                            shape: MaterialShape.Shape.Slanted
                            text: "date_range"
                            iconSize: Appearance.font.pixelSize.large
                            padding: Appearance.sizes.elevationMargin * 0.7
                            color: Appearance.colors.colSecondaryContainer
                            colSymbol: Appearance.colors.colOnSecondaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: Translation.tr("Schedule")
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: allDayButton.toggled
                                    ? Translation.tr("Choose the first and last calendar day")
                                    : Translation.tr("Set a precise beginning and ending")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colSurfaceContainerHigh

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin / 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.sizes.elevationMargin

                                MaterialShapeWrappedMaterialSymbol {
                                    shape: MaterialShape.Shape.Cookie4Sided
                                    text: "play_arrow"
                                    iconSize: Appearance.font.pixelSize.normal
                                    padding: Appearance.sizes.elevationMargin * 0.6
                                    color: Appearance.colors.colPrimaryContainer
                                    colSymbol: Appearance.colors.colOnPrimaryContainer
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        text: Translation.tr("Starts")
                                        color: Appearance.colors.colOnSurface
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        text: Translation.tr("First moment of the event")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.sizes.elevationMargin

                                CompactField {
                                    id: startDateField
                                    Layout.fillWidth: true
                                    label: Translation.tr("Date")
                                    symbol: "calendar_today"
                                    placeholder: Translation.tr("YYYY-MM-DD")
                                    invalid: root.validationAttempted && !root.normalizedDate(text)
                                    tabTarget: allDayButton.toggled
                                        ? endDateField.inputItem
                                        : startTimeField.inputItem
                                    onAccepted: tabTarget.forceActiveFocus()
                                }
                                CompactField {
                                    id: startTimeField
                                    Layout.fillWidth: true
                                    visible: !allDayButton.toggled
                                    label: Translation.tr("Time")
                                    symbol: "schedule"
                                    placeholder: Translation.tr("HH:MM")
                                    invalid: root.validationAttempted && !root.normalizedTime(text)
                                    tabTarget: endDateField.inputItem
                                    onAccepted: endDateField.inputItem.forceActiveFocus()
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colSurfaceContainerHigh

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin / 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.sizes.elevationMargin

                                MaterialShapeWrappedMaterialSymbol {
                                    shape: MaterialShape.Shape.Cookie4Sided
                                    text: "stop"
                                    iconSize: Appearance.font.pixelSize.normal
                                    padding: Appearance.sizes.elevationMargin * 0.6
                                    color: Appearance.colors.colSecondaryContainer
                                    colSymbol: Appearance.colors.colOnSecondaryContainer
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        text: Translation.tr("Ends")
                                        color: Appearance.colors.colOnSurface
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        text: Translation.tr("Must come after the start")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.sizes.elevationMargin

                                CompactField {
                                    id: endDateField
                                    Layout.fillWidth: true
                                    label: Translation.tr("Date")
                                    symbol: "event"
                                    placeholder: Translation.tr("YYYY-MM-DD")
                                    invalid: root.validationAttempted && !root.normalizedDate(text)
                                    tabTarget: allDayButton.toggled
                                        ? locationField.inputItem
                                        : endTimeField.inputItem
                                    onAccepted: tabTarget.forceActiveFocus()
                                }
                                CompactField {
                                    id: endTimeField
                                    Layout.fillWidth: true
                                    visible: !allDayButton.toggled
                                    label: Translation.tr("Time")
                                    symbol: "schedule"
                                    placeholder: Translation.tr("HH:MM")
                                    invalid: root.validationAttempted && !root.normalizedTime(text)
                                    tabTarget: locationField.inputItem
                                    onAccepted: locationField.inputItem.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Appearance.sizes.elevationMargin * 5
            spacing: Appearance.sizes.elevationMargin

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                MaterialSymbol {
                    text: root.errorText.length > 0 ? "error" : "info"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.errorText.length > 0
                        ? Appearance.colors.colError
                        : Appearance.colors.colOutline
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.errorText.length > 0
                        ? root.errorText
                        : Translation.tr("Required fields are checked before the event is created")
                    elide: Text.ElideRight
                    color: root.errorText.length > 0
                        ? Appearance.colors.colError
                        : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            RippleButtonWithIcon {
                id: createEventButton
                Layout.preferredWidth: contentImplicitWidth + Appearance.sizes.elevationMargin * 3
                Layout.fillHeight: true
                buttonRadius: Appearance.rounding.full
                centerContent: true
                materialIcon: root.busy ? "progress_activity" : "add"
                materialIconFill: false
                mainText: root.busy
                    ? Translation.tr("Creating…")
                    : Translation.tr("Create event")
                colText: Appearance.colors.colOnPrimary
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colBackgroundActive: Appearance.colors.colPrimaryActive
                enabled: !root.busy
                KeyNavigation.tab: titleField.inputItem
                onClicked: root.submit()

                StyledToolTip {
                    text: Translation.tr("Create event")
                }
            }
        }
    }
}
