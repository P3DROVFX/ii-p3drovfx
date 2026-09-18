pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/** Background jobs with a measurable progress. */
ContinuousSource {
    id: source

    activityId: "progress"
    condition: ProgressService.hasActiveJobs
    payload: ProgressService.jobs
}
