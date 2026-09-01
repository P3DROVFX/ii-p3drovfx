.pragma library

function expandedCenterBudget(groupsSlotHeight, expandedBottomHeight, groupSpacing) {
    const slotHeight = Math.max(0, Number(groupsSlotHeight) || 0);
    const targetBottomHeight = Math.max(0, Number(expandedBottomHeight) || 0);
    const spacing = Math.max(0, Number(groupSpacing) || 0);
    return Math.max(0, slotHeight - targetBottomHeight - spacing);
}

function requiresCompactMode(expandedBudget, minimumExpandedHeight, enabled) {
    if (!enabled)
        return false;

    const budget = Math.max(0, Number(expandedBudget) || 0);
    const minimumHeight = Math.max(0, Number(minimumExpandedHeight) || 0);
    return minimumHeight > 0 && budget < minimumHeight;
}

function minimumUsefulNotificationHeight(representativeHeight, visibleCardFactor) {
    const cardHeight = Math.max(0, Number(representativeHeight) || 0);
    const factor = Math.max(0, Number(visibleCardFactor) || 0);
    return cardHeight * factor;
}

function packedGroupsMinimumHeight(expandedBottomHeight, collapsedNotificationHeight, groupSpacing) {
    const bottomHeight = Math.max(0, Number(expandedBottomHeight) || 0);
    const notificationHeight = Math.max(0, Number(collapsedNotificationHeight) || 0);
    const spacing = Math.max(0, Number(groupSpacing) || 0);
    return bottomHeight + notificationHeight + spacing;
}

function expandedBottomFillHeight(availableHeight, naturalExpandedHeight, collapsedNotificationHeight, groupSpacing) {
    const available = Math.max(0, Number(availableHeight) || 0);
    const naturalHeight = Math.max(0, Number(naturalExpandedHeight) || 0);
    const notificationHeight = Math.max(0, Number(collapsedNotificationHeight) || 0);
    const spacing = Math.max(0, Number(groupSpacing) || 0);
    return Math.max(naturalHeight, available - notificationHeight - spacing);
}

function notificationMaximumHeight(collapsed, collapsedHeight, expandedHeight) {
    const pillHeight = Math.max(0, Number(collapsedHeight) || 0);
    const fullHeight = Math.max(pillHeight, Number(expandedHeight) || 0);
    return collapsed ? pillHeight : fullHeight;
}

function notificationMinimumHeight(animatedMaximumHeight, expandedMinimumHeight) {
    const maximumHeight = Math.max(0, Number(animatedMaximumHeight) || 0);
    const minimumHeight = Math.max(0, Number(expandedMinimumHeight) || 0);
    return Math.min(maximumHeight, minimumHeight);
}

function dashboardSpacing(notificationsCollapsed, normalSpacing) {
    return Math.max(0, Number(normalSpacing) || 0);
}

function resolve(compactMode, bottomRequestedExpanded, bottomPersistedCollapsed, forceBottomCollapsed) {
    const bottomOwnsCompactSpace = compactMode
        && bottomRequestedExpanded
        && !bottomPersistedCollapsed
        && !forceBottomCollapsed;

    return {
        notificationsCollapsed: bottomOwnsCompactSpace,
        bottomForcedCollapsed: forceBottomCollapsed || (compactMode && !bottomOwnsCompactSpace)
    };
}
