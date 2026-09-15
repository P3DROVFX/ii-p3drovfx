.pragma library

// Descendant construction must not invalidate Connect's full-height sidebar
// cache while the outer width animation is running.
function canActivateDeferredContent(sidebarOpen, sidebarAnimating, eagerEntranceEnabled) {
    return sidebarOpen && (eagerEntranceEnabled || !sidebarAnimating);
}

function nextDeferredContentReady(currentReady, sidebarOpen, sidebarAnimating, eagerEntranceEnabled) {
    return currentReady || canActivateDeferredContent(sidebarOpen, sidebarAnimating, eagerEntranceEnabled);
}

function shouldQueueEntranceAnimations(enabled, sidebarOpen) {
    return enabled && sidebarOpen;
}

function canTriggerEntranceAnimations(pending, enabled, sidebarOpen, sidebarAnimating) {
    return pending && enabled && sidebarOpen;
}
