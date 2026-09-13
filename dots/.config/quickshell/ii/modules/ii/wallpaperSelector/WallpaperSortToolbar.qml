import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Toolbar {
    id: root

    property bool expanded: false
    property real expandedProgress: expanded ? 1.0 : 0.0
    property bool sortDialogOpen: false

    readonly property string selectedSortField: Wallpapers.sortField
    readonly property bool sortReversed: Wallpapers.sortReversed
    readonly property var sortOptions: [
        { value: "name", label: Translation.tr("Name"), icon: "sort_by_alpha" },
        { value: "modified", label: Translation.tr("Date modified"), icon: "update" },
        { value: "created", label: Translation.tr("Date created"), icon: "calendar_add_on" },
        { value: "size", label: Translation.tr("Size"), icon: "straighten" }
    ]
    readonly property string selectedSortLabel: {
        for (let i = 0; i < sortOptions.length; i++) {
            if (sortOptions[i].value === root.selectedSortField)
                return sortOptions[i].label;
        }
        return sortOptions[1].label;
    }

    padding: 6
    spacing: 6 * expandedProgress
    colBackground: Appearance.m3colors.m3surfaceContainerLow

    Behavior on expandedProgress {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    component SortButton: IconToolbarButton {
        implicitWidth: height

        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        colRipple: Appearance.colors.colLayer2Active
        colRippleToggled: Appearance.colors.colPrimaryActive
    }

    SortButton {
        id: sortButton
        toggled: root.expanded
        text: "sort"
        onClicked: {
            if (root.expanded) {
                root.closeSortDialog();
                root.expanded = false;
            } else {
                root.expanded = true;
            }
        }

        StyledToolTip {
            text: root.expanded ? Translation.tr("Collapse wallpaper sorting") : Translation.tr("Sort wallpapers")
        }
    }

    Item {
        id: summarySlot
        clip: true
        opacity: root.expandedProgress
        enabled: root.expandedProgress > 0.5

        Layout.fillHeight: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: root.expandedProgress * sortSummary.implicitWidth
        Layout.maximumWidth: root.expandedProgress * sortSummary.implicitWidth

        Behavior on Layout.preferredWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(summarySlot)
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(summarySlot)
        }

        RippleButton {
            id: sortSummary
            anchors.fill: parent
            implicitWidth: summaryContent.implicitWidth + Appearance.font.pixelSize.hugeass * 2
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colBackgroundActive: Appearance.colors.colLayer2Active
            colRipple: Appearance.colors.colLayer2Active

            contentItem: RowLayout {
                id: summaryContent
                anchors.fill: parent
                anchors.leftMargin: Appearance.font.pixelSize.large
                anchors.rightMargin: Appearance.font.pixelSize.large
                spacing: Appearance.font.pixelSize.small

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                    text: root.selectedSortLabel
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    iconSize: Appearance.font.pixelSize.huge
                    text: root.sortReversed ? "arrow_downward" : "arrow_upward"
                    color: Appearance.colors.colOnLayer2
                }
            }

            onClicked: {
                if (root.sortDialogOpen)
                    root.closeSortDialog();
                else
                    root.openSortDialog();
            }
        }
    }

    Popup {
        id: sortDialog
        parent: root
        x: Math.max(0, root.width - width)
        y: -height - Appearance.sizes.hyprlandGapsOut
        width: Appearance.sizes.wallpaperSelectorSortDialogWidth
        padding: Appearance.font.pixelSize.smaller
        modal: false
        focus: true
        // Keep clicks on the trigger toolbar available to its own handlers.
        // CloseOnPressOutside would consume that click before the summary can
        // toggle an already-open dialog.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        onOpened: root.sortDialogOpen = true
        onClosed: {
            // CloseOnPressOutside can emit this before the summary button's
            // click handler. Defer the state reset so that clicking the
            // summary while the dialog is open remains a close operation.
            Qt.callLater(() => root.sortDialogOpen = false);
        }

        background: Rectangle {
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.large
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation {
                    target: sortDialog
                    property: "y"
                    from: -sortDialog.height - Appearance.sizes.hyprlandGapsOut + Appearance.sizes.hyprlandGapsOut
                    to: -sortDialog.height - Appearance.sizes.hyprlandGapsOut
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardDecel
                }
                NumberAnimation {
                    target: sortDialog
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardDecel
                }
            }
        }

        exit: Transition {
            ParallelAnimation {
                NumberAnimation {
                    target: sortDialog
                    property: "y"
                    from: -sortDialog.height - Appearance.sizes.hyprlandGapsOut
                    to: -sortDialog.height - Appearance.sizes.hyprlandGapsOut + Appearance.sizes.hyprlandGapsOut
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardAccel
                }
                NumberAnimation {
                    target: sortDialog
                    property: "opacity"
                    from: 1.0
                    to: 0.0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardAccel
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Appearance.sizes.hyprlandGapsOut

            Repeater {
                model: root.sortOptions

                delegate: RippleButton {
                    id: sortOptionButton
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut * 2
                    buttonRadius: Appearance.rounding.large
                    buttonRadiusPressed: Appearance.rounding.large
                    useDynamicRadius: true
                    toggled: modelData.value === root.selectedSortField
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    colBackgroundToggled: Appearance.colors.colPrimary
                    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                    colBackgroundToggledActive: Appearance.colors.colPrimaryActive
                    colRipple: Appearance.colors.colLayer2Active
                    colRippleToggled: Appearance.colors.colPrimaryActive

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.font.pixelSize.small
                        anchors.rightMargin: Appearance.font.pixelSize.small
                        spacing: Appearance.font.pixelSize.small

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                            iconSize: Appearance.font.pixelSize.huge
                            text: sortOptionButton.modelData.icon
                            color: sortOptionButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                            text: sortOptionButton.modelData.label
                            color: sortOptionButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                            visible: sortOptionButton.modelData.value === root.selectedSortField
                            iconSize: Appearance.font.pixelSize.huge
                            text: root.sortReversed ? "arrow_downward" : "arrow_upward"
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    onClicked: Wallpapers.selectSortField(sortOptionButton.modelData.value)
                }
            }
        }
    }

    function openSortDialog() {
        root.expanded = true;
        root.sortDialogOpen = true;
        sortDialog.open();
    }

    function closeSortDialog() {
        root.sortDialogOpen = false;
        sortDialog.close();
    }
}
