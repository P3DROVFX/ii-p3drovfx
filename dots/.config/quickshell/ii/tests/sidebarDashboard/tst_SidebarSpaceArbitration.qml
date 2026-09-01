import QtQuick
import QtQuick.Layouts
import QtTest
import "../../modules/ii/sidebarDashboard/SidebarSpaceArbitration.js" as Arbitration

TestCase {
    name: "SidebarSpaceArbitration"

    Component {
        id: layoutHarnessComponent

        Item {
            id: harness
            width: 320
            height: 806

            property bool notificationsCollapsed: false
            property bool bottomCollapsed: true
            readonly property int animationDuration: 80
            readonly property real outerSpacing: outerColumn.spacing
            readonly property real headerHeight: headerCard.height
            readonly property real quickPanelY: quickPanel.y
            readonly property real quickPanelBottom: quickPanel.y + quickPanel.height
            readonly property real adaptiveY: adaptiveArea.y
            readonly property real adaptiveSpacing: adaptiveArea.groupSpacing
            readonly property real adaptiveHeight: adaptiveArea.height
            readonly property real centerY: centerLoader.y
            readonly property real centerHeight: centerLoader.height
            readonly property real centerBottom: centerLoader.y + centerLoader.height
            readonly property real bottomY: bottomCard.y
            readonly property real bottomHeight: bottomCard.height
            readonly property bool centerReady: centerLoader.status === Loader.Ready

            ColumnLayout {
                id: outerColumn
                anchors.fill: parent
                spacing: 10

                Rectangle {
                    id: headerCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                }

                Rectangle {
                    id: quickPanel
                    Layout.fillWidth: true
                    Layout.preferredHeight: 334
                }

                Item {
                    id: adaptiveArea
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    Layout.minimumHeight: containmentHeight
                    readonly property real availableHeight: Math.max(0, outerColumn.height - y)
                    readonly property real packedTakeoverHeight: Arbitration.packedGroupsMinimumHeight(
                        350,
                        centerLoader.collapsedHeight,
                        targetSpacing
                    )
                    readonly property real targetContainmentHeight: harness.notificationsCollapsed
                        ? packedTakeoverHeight
                        : availableHeight
                    property real containmentHeight: targetContainmentHeight
                    readonly property real targetSpacing: Arbitration.dashboardSpacing(
                        harness.notificationsCollapsed,
                        10
                    )
                    readonly property real targetBottomHeight: harness.bottomCollapsed
                        ? 56
                        : harness.notificationsCollapsed
                            ? Arbitration.expandedBottomFillHeight(
                                availableHeight,
                                350,
                                centerLoader.collapsedHeight,
                                targetSpacing
                            )
                            : 350
                    readonly property real expandedCenterTargetHeight: Math.max(
                        0,
                        availableHeight - targetBottomHeight - targetSpacing
                    )
                    property real groupSpacing: targetSpacing
                    property real animatedBottomHeight: targetBottomHeight

                    Behavior on containmentHeight {
                        NumberAnimation { duration: harness.animationDuration }
                    }

                    Behavior on groupSpacing {
                        NumberAnimation { duration: harness.animationDuration }
                    }

                    Behavior on animatedBottomHeight {
                        NumberAnimation { duration: harness.animationDuration }
                    }

                    Loader {
                        id: centerLoader
                        asynchronous: true
                        sourceComponent: Rectangle {
                            readonly property real collapsedHeight: 36
                            implicitHeight: harness.notificationsCollapsed ? 36 : 250
                        }
                        readonly property real collapsedHeight: item?.collapsedHeight ?? 0
                        property real animatedMaximumHeight: Arbitration.notificationMaximumHeight(
                            harness.notificationsCollapsed,
                            collapsedHeight,
                            adaptiveArea.expandedCenterTargetHeight
                        )

                        Behavior on animatedMaximumHeight {
                            NumberAnimation { duration: harness.animationDuration }
                        }

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: bottomCard.top
                        anchors.bottomMargin: adaptiveArea.groupSpacing
                        height: animatedMaximumHeight
                    }

                    Rectangle {
                        id: bottomCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: adaptiveArea.animatedBottomHeight
                    }
                }
            }
        }
    }

    function test_expanded_budget_comes_from_the_stable_groups_slot() {
        compare(Arbitration.expandedCenterBudget(510, 350, 10), 150);
        compare(Arbitration.expandedCenterBudget(500, 350, 10), 140);
    }

    function test_compact_mode_uses_the_expanded_notification_minimum() {
        verify(Arbitration.requiresCompactMode(179, 180, true));
        verify(!Arbitration.requiresCompactMode(180, 180, true));
        verify(!Arbitration.requiresCompactMode(100, 180, false));
    }

    function test_useful_notification_height_is_one_and_a_half_cards_total() {
        compare(Arbitration.minimumUsefulNotificationHeight(80, 1.5), 120);
        compare(Arbitration.minimumUsefulNotificationHeight(0, 1.5), 0);
    }

    function test_packed_takeover_height_reserves_bottom_and_notification_pill() {
        compare(Arbitration.packedGroupsMinimumHeight(350, 36, 10), 396);
    }

    function test_bottom_fills_takeover_space_without_shrinking_below_natural_height() {
        compare(Arbitration.expandedBottomFillHeight(462, 350, 36, 10), 416);
        compare(Arbitration.expandedBottomFillHeight(380, 350, 36, 10), 350);
    }

    function test_notifications_win_when_compact_mode_starts() {
        const state = Arbitration.resolve(true, false, false, false);
        verify(!state.notificationsCollapsed);
        verify(state.bottomForcedCollapsed);
    }

    function test_manual_bottom_expansion_hands_over_compact_space() {
        const state = Arbitration.resolve(true, true, false, false);
        verify(state.notificationsCollapsed);
        verify(!state.bottomForcedCollapsed);
    }

    function test_persistently_collapsed_bottom_cannot_collapse_notifications() {
        const state = Arbitration.resolve(true, true, true, false);
        verify(!state.notificationsCollapsed);
        verify(state.bottomForcedCollapsed);
    }

    function test_compact_mode_never_leaves_both_groups_equal() {
        const booleanValues = [false, true];
        for (let requestedIndex = 0; requestedIndex < booleanValues.length; requestedIndex++) {
            for (let persistedIndex = 0; persistedIndex < booleanValues.length; persistedIndex++) {
                const requestedExpanded = booleanValues[requestedIndex];
                const persistedCollapsed = booleanValues[persistedIndex];
                const state = Arbitration.resolve(true, requestedExpanded, persistedCollapsed, false);
                const notificationsExpanded = !state.notificationsCollapsed;
                const bottomExpanded = !(persistedCollapsed || state.bottomForcedCollapsed);
                compare(Number(notificationsExpanded) + Number(bottomExpanded), 1);
            }
        }
    }

    function test_edit_mode_always_collapses_bottom_without_collapsing_notifications() {
        const state = Arbitration.resolve(false, true, false, true);
        verify(!state.notificationsCollapsed);
        verify(state.bottomForcedCollapsed);
    }

    function test_manual_takeover_can_leave_compact_mode_after_viewport_grows() {
        const minimumExpandedHeight = 180;
        const compactBudget = Arbitration.expandedCenterBudget(320, 350, 10);
        verify(Arbitration.requiresCompactMode(compactBudget, minimumExpandedHeight, true));

        const takeoverState = Arbitration.resolve(true, true, false, false);
        verify(takeoverState.notificationsCollapsed);
        verify(!takeoverState.bottomForcedCollapsed);

        // The slot height comes from the parent column, not the now-capped
        // center and bottom children, so a larger viewport is observable.
        const grownBudget = Arbitration.expandedCenterBudget(600, 350, 10);
        verify(!Arbitration.requiresCompactMode(grownBudget, minimumExpandedHeight, true));

        const normalState = Arbitration.resolve(false, true, false, false);
        verify(!normalState.notificationsCollapsed);
        verify(!normalState.bottomForcedCollapsed);
    }

    function test_notification_layout_targets_full_slot_and_pill() {
        compare(Arbitration.notificationMaximumHeight(false, 46, 420), 420);
        compare(Arbitration.notificationMaximumHeight(true, 46, 420), 46);
        compare(Arbitration.notificationMinimumHeight(420, 120), 120);
        compare(Arbitration.notificationMinimumHeight(46, 120), 46);
    }

    function test_manual_takeover_preserves_consistent_inter_group_spacing() {
        compare(Arbitration.dashboardSpacing(false, 10), 10);
        compare(Arbitration.dashboardSpacing(true, 10), 10);
    }

    function test_layout_animates_takeover_without_shrinking_bottom_or_outer_spacing() {
        const harness = createTemporaryObject(layoutHarnessComponent, this);
        verify(harness !== null);
        tryCompare(harness, "centerReady", true);
        wait(harness.animationDuration + 20);

        const stableAdaptiveHeight = harness.adaptiveHeight;
        const expandedCenterHeight = harness.centerHeight;
        const stableQuickPanelY = harness.quickPanelY;
        const stableQuickPanelBottom = harness.quickPanelBottom;
        compare(harness.outerSpacing, 10);
        compare(stableAdaptiveHeight, 396);
        compare(harness.adaptiveSpacing, 10);
        compare(harness.bottomHeight, 56);
        compare(harness.quickPanelY, harness.headerHeight + harness.outerSpacing);
        compare(harness.adaptiveY, harness.quickPanelBottom + harness.outerSpacing);
        verify(expandedCenterHeight > 120);

        harness.notificationsCollapsed = true;
        harness.bottomCollapsed = false;
        wait(harness.animationDuration / 2);

        verify(harness.centerHeight < expandedCenterHeight);
        verify(harness.centerHeight > 36);
        verify(harness.bottomHeight > 56);
        verify(harness.bottomHeight < 350);

        wait(harness.animationDuration);
        compare(harness.outerSpacing, 10);
        compare(harness.adaptiveSpacing, 10);
        compare(harness.centerHeight, 36);
        compare(harness.bottomHeight, 350);
        compare(harness.adaptiveHeight, stableAdaptiveHeight);
        compare(harness.quickPanelY, stableQuickPanelY);
        compare(harness.quickPanelBottom, stableQuickPanelBottom);
        compare(harness.centerBottom + harness.adaptiveSpacing, harness.bottomY);
    }

    function test_short_layout_does_not_overlap_quick_panel_during_takeover() {
        const harness = createTemporaryObject(layoutHarnessComponent, this, { height: 700 });
        verify(harness !== null);
        tryCompare(harness, "centerReady", true);

        harness.notificationsCollapsed = true;
        harness.bottomCollapsed = false;
        wait(harness.animationDuration * 2);

        verify(harness.adaptiveHeight >= 396);
        verify(harness.centerY >= 0);
        compare(harness.centerBottom + harness.adaptiveSpacing, harness.bottomY);
        verify(harness.adaptiveY >= harness.quickPanelBottom + harness.outerSpacing);

        harness.notificationsCollapsed = false;
        harness.bottomCollapsed = true;
        wait(harness.animationDuration / 2);

        verify(harness.centerY >= 0);
        compare(harness.centerBottom + harness.adaptiveSpacing, harness.bottomY);
        verify(harness.adaptiveY >= harness.quickPanelBottom + harness.outerSpacing);

        wait(harness.animationDuration);
        compare(harness.adaptiveHeight, 290);
        verify(harness.centerY >= 0);
        compare(harness.centerBottom + harness.adaptiveSpacing, harness.bottomY);
    }

    function test_tall_takeover_fills_all_space_below_notification_pill() {
        const harness = createTemporaryObject(layoutHarnessComponent, this, { height: 872 });
        verify(harness !== null);
        tryCompare(harness, "centerReady", true);

        harness.notificationsCollapsed = true;
        harness.bottomCollapsed = false;
        wait(harness.animationDuration * 2);

        compare(harness.adaptiveHeight, 462);
        compare(harness.centerY, 0);
        compare(harness.centerHeight, 36);
        compare(harness.adaptiveSpacing, 10);
        compare(harness.bottomHeight, 416);
        compare(harness.centerBottom + harness.adaptiveSpacing, harness.bottomY);
    }

}
