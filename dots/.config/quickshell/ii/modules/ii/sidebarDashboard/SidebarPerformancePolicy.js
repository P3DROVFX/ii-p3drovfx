.pragma library

// Heavy descendants use asynchronous Loaders, so waiting for the outer width
// animation only creates a visible blank area. A resident dashboard can warm
// them while hidden; a cold dashboard must start them at the open request.
function canActivateDeferredContent(sidebarOpen, keepWarm) {
    return keepWarm || sidebarOpen;
}

function nextDeferredContentReady(currentReady, sidebarOpen, keepWarm) {
    return currentReady || canActivateDeferredContent(sidebarOpen, keepWarm);
}

function shouldQueueEntranceAnimations(enabled, sidebarOpen) {
    return enabled && sidebarOpen;
}

function canTriggerEntranceAnimations(pending, enabled, sidebarOpen, sidebarAnimating) {
    return pending && enabled && sidebarOpen;
}
