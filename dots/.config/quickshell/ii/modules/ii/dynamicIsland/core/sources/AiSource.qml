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
}
