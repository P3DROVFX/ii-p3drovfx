pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * An AI agent is working.
 *
 * `AiStatusService` holds the agents and only reassigns that list when it really
 * changes, so this source can bind straight to it. An agent that needs an answer is
 * promoted to the interrupt tier, because that is the one case where the island should
 * take the centre and stay there.
 */
ContinuousSource {
    id: source

    activityId: "ai"

    condition: AiStatusService.hasActiveAgents
    payload: AiStatusService.agents

    readonly property bool needsAction: AiStatusService.agents.some(agent => agent.requiresAttention === true)
    readonly property string tierOverride: source.needsAction ? "interrupt" : ""

    /**
     * A turn ending is the one thing about an agent worth being told: it is the moment
     * to go back to it. In a bubble that was a status line nobody had open, so the turn
     * finishing - or being interrupted - takes the centre for the few seconds the
     * monitor announces it, and the session then rests in its bubble until it is
     * prompted again or closed.
     */
    readonly property bool announcing: AiStatusService.agents.some(agent => agent.announce === true)
    onAnnouncingChanged: {
        // A fresh revision is what brings a retracted island out for it.
        if (source.announcing && source.active)
            source.revision += 1;
    }
}
