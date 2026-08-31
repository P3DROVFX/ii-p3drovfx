#!/usr/bin/env python3
"""Executable contracts for ESPN summary projection and timeline rendering."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TIMETABLE = ROOT / "modules" / "ii" / "cheatsheet" / "timetable"


class TimetableSportsDetailsProjectionTests(unittest.TestCase):
    def test_real_espn_summary_shapes_are_projected_before_the_repeater(self) -> None:
        helper = TIMETABLE / "SportsDetailsHelpers.js"
        fixture = {
            "rosters": [{
                "team": {"displayName": "Newcastle United"},
                "roster": [
                    {"starter": True, "jersey": "10", "athlete": {"displayName": "William Osula"}, "position": {"abbreviation": "F"}},
                    {"starter": False, "jersey": "8", "athlete": {"displayName": "Sandro Tonali"}, "position": {"abbreviation": "M"}},
                ],
            }],
            "boxscore": {"teams": [{
                "team": {"displayName": "Newcastle United"},
                "statistics": [{"label": "Shots", "displayValue": "12"}],
            }]},
            "leaders": [{
                "team": {"displayName": "Newcastle United"},
                "leaders": [{
                    "displayName": "Total Shots",
                    "leaders": [{"displayValue": "2", "athlete": {"displayName": "William Osula"}}],
                }],
            }],
            "keyEvents": [{
                "clock": {"displayValue": "25'"},
                "type": {"text": "Yellow Card"},
                "text": "Yoane Wissa is shown the yellow card.",
            }],
        }
        script = f"""
const H = require({json.dumps(str(helper))});
const fixture = {json.dumps(fixture)};
const result = {{
  lineups: H.lineupRows(fixture.rosters),
  statistics: H.statisticsRows(fixture.boxscore.teams),
  leaders: H.leaderRows(fixture.leaders),
  events: H.keyEventRows(fixture.keyEvents)
}};
if (result.lineups.length !== 2) throw new Error(JSON.stringify(result));
if (result.lineups[0].team !== "Newcastle United" || result.lineups[0].group !== "starters") throw new Error(JSON.stringify(result));
if (!result.lineups[0].value.includes("William Osula")) throw new Error(JSON.stringify(result));
if (result.statistics[0].value !== "Shots: 12") throw new Error(JSON.stringify(result));
if (!result.leaders[0].value.includes("William Osula")) throw new Error(JSON.stringify(result));
if (result.events[0].time !== "25'" || result.events[0].text !== "Yoane Wissa is shown the yellow card.") throw new Error(JSON.stringify(result));
"""
        subprocess.run(["node", "-e", script], check=True, capture_output=True, text=True)

    def test_qml_array_like_lists_and_empty_payloads_are_supported(self) -> None:
        helper = TIMETABLE / "SportsDetailsHelpers.js"
        script = f"""
const H = require({json.dumps(str(helper))});
const arrayLikeRoster = {{
  0: {{starter: true, athlete: {{displayName: "Player One"}}}},
  length: 1
}};
const arrayLikeRosters = {{
  0: {{team: {{displayName: "Team One"}}, roster: arrayLikeRoster}},
  length: 1
}};
const rows = H.lineupRows(arrayLikeRosters);
if (rows.length !== 1 || rows[0].value !== "Player One") throw new Error(JSON.stringify(rows));
if (H.lineupRows(null).length !== 0) throw new Error("lineups must stay empty");
if (H.statisticsRows(undefined).length !== 0) throw new Error("statistics must stay empty");
if (H.leaderRows({{length: 0}}).length !== 0) throw new Error("leaders must stay empty");
if (H.keyEventRows([]).length !== 0) throw new Error("events must stay empty");
"""
        subprocess.run(["node", "-e", script], check=True, capture_output=True, text=True)

    def test_key_events_render_individual_rows_with_time_pills(self) -> None:
        details = (TIMETABLE / "SportsEventDetails.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property var keyEventRows", details)
        self.assertIn("model: root.keyEventRows", details)
        self.assertIn("id: eventTimePill", details)
        self.assertIn("text: modelData.time", details)
        self.assertIn("visible: index < root.keyEventRows.length - 1", details)
        self.assertNotIn("value: root.keyEventsText()", details)


if __name__ == "__main__":
    unittest.main()
