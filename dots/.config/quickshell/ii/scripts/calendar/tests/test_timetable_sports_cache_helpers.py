#!/usr/bin/env python3
"""Executable contracts for the timetable sports cache helpers.

The helpers decide three things that are invisible in a screenshot but decide
whether the month grid rebuilds itself: how a range is turned into ESPN
queries, whether a republished list of games actually changed, and whether a
day keeps its array identity. Node runs the real module; no QML engine, no
network.
"""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "services" / "SportsServiceHelpers.js"


def run_node(script: str) -> None:
    result = subprocess.run(["node", "-e", script], capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"node failed:\n{result.stdout.strip()}\n{result.stderr.strip()}")


def game(game_id, content, state="pre", status="Scheduled", start="14:00"):
    return {"id": game_id, "content": content, "state": state, "status": status, "start": start}


class TimetableSportsCacheHelperTests(unittest.TestCase):
    def test_ranges_become_month_queries(self) -> None:
        """ESPN rejects `from-to` ranges, so a range must be walked by month."""
        script = f"""
const H = require({json.dumps(str(HELPER))});
const sameMonth = H.espnMonths("2026-09-01", "2026-09-30");
if (JSON.stringify(sameMonth) !== JSON.stringify(["202609"])) throw new Error(JSON.stringify(sameMonth));

const grid = H.espnMonths("2026-08-30", "2026-10-03");
if (JSON.stringify(grid) !== JSON.stringify(["202608", "202609", "202610"])) throw new Error(JSON.stringify(grid));

const newYear = H.espnMonths("2026-12-28", "2027-01-05");
if (JSON.stringify(newYear) !== JSON.stringify(["202612", "202701"])) throw new Error(JSON.stringify(newYear));

if (H.espnMonths("2026-09-30", "2026-09-01").length !== 0) throw new Error("reversed range must stay empty");
if (H.espnMonths("", "2026-09-30").length !== 0) throw new Error("empty key must stay empty");
if (H.espnMonths(undefined, undefined).length !== 0) throw new Error("missing keys must stay empty");
"""
        run_node(script)

    def test_month_index_is_clamped_to_the_request(self) -> None:
        script = f"""
const H = require({json.dumps(str(HELPER))});
const months = ["202608", "202609", "202610"];
if (H.monthForIndex(months, 0) !== "202608") throw new Error("first month");
if (H.monthForIndex(months, 2) !== "202610") throw new Error("last month");
if (H.monthForIndex(months, 9) !== "202610") throw new Error("index past the end must clamp");
if (H.monthForIndex(months, -3) !== "202608") throw new Error("negative index must clamp");
if (H.monthForIndex([], 0) !== "") throw new Error("no months must stay empty");
if (H.monthForIndex(undefined, 0) !== "") throw new Error("missing months must stay empty");
"""
        run_node(script)

    def test_only_rendered_game_fields_count_as_a_change(self) -> None:
        """A score or live-minute change must publish; nothing else needs to."""
        script = f"""
const H = require({json.dumps(str(HELPER))});
const base = {json.dumps(game("1", "Liverpool 1-0 Arsenal", "in", "45'"))};
if (!H.sameGame(base, {{...base}})) throw new Error("identical games must match");
if (H.sameGame(base, {{...base, content: "Liverpool 2-0 Arsenal"}})) throw new Error("score change must differ");
if (H.sameGame(base, {{...base, status: "67'"}})) throw new Error("live minute must differ");
if (H.sameGame(base, {{...base, state: "post"}})) throw new Error("state change must differ");
if (H.sameGame(base, {{...base, start: "15:30"}})) throw new Error("kick-off change must differ");
if (H.sameGame(base, {{...base, id: "2"}})) throw new Error("identity change must differ");
if (!H.sameGame(base, {{...base, venue: "somewhere else"}})) throw new Error("unrendered fields must not differ");

if (!H.sameGames([base], [{{...base}}])) throw new Error("lists with the same games must match");
if (H.sameGames([base], [{{...base}}, {{...base, id: "2"}}])) throw new Error("added game must differ");
if (H.sameGames([base], [])) throw new Error("removed game must differ");
if (H.sameGames(undefined, [])) throw new Error("undefined previous must differ");
if (!H.sameGames([], [])) throw new Error("two empty lists must match");
"""
        run_node(script)

    def test_unchanged_days_keep_their_array_identity(self) -> None:
        """The month cell rebuilds its chips when this array changes identity."""
        script = f"""
const H = require({json.dumps(str(HELPER))});
const dayKeyOf = value => value ? String(value).slice(0, 10) : "";
const monday = {json.dumps(game("1", "A vs B"))};
const tuesday = {json.dumps(game("2", "C vs D"))};
const first = H.gamesByDay(
  [{{...monday, startDate: "2026-09-07"}}, {{...tuesday, startDate: "2026-09-08"}}], dayKeyOf, ({{}}));
if (Object.keys(first).length !== 2 || first["2026-09-07"].length !== 1) throw new Error(JSON.stringify(first));

const unchanged = H.gamesByDay(
  [{{...monday, startDate: "2026-09-07"}}, {{...tuesday, startDate: "2026-09-08"}}], dayKeyOf, first);
if (unchanged["2026-09-07"] !== first["2026-09-07"]) throw new Error("unchanged day must keep its array");
if (unchanged["2026-09-08"] !== first["2026-09-08"]) throw new Error("unchanged day must keep its array");

const changed = H.gamesByDay(
  [{{...monday, startDate: "2026-09-07", content: "A 1-0 B", state: "in", status: "12'"}}, {{...tuesday, startDate: "2026-09-08"}}],
  dayKeyOf, first);
if (changed["2026-09-07"] === first["2026-09-07"]) throw new Error("changed day must get a new array");
if (changed["2026-09-08"] !== first["2026-09-08"]) throw new Error("untouched day must keep its array");

const dropped = H.gamesByDay([{{...monday, startDate: "2026-09-07"}}], dayKeyOf, first);
if (dropped["2026-09-08"] !== undefined) throw new Error("day without games must disappear");

const ignored = H.gamesByDay([{{...monday, startDate: undefined}}], dayKeyOf, ({{}}));
if (Object.keys(ignored).length !== 0) throw new Error("games without a day must be skipped");
"""
        run_node(script)

    def test_input_signature_tracks_everything_the_projection_reads(self) -> None:
        script = f"""
const H = require({json.dumps(str(HELPER))});
const source = ({{key: "soccer|eng.1|2026-08-30|2026-10-03", cached: {{fetchedAt: 1000}}, events: [1, 2, 3]}});
const base = H.sourceSignature("2026-08-30", "2026-10-03", "", [source]);
if (base !== H.sourceSignature("2026-08-30", "2026-10-03", "", [{{...source}}])) throw new Error("same inputs must sign the same");
if (base === H.sourceSignature("2026-08-30", "2026-09-30", "", [source])) throw new Error("range must sign differently");
if (base === H.sourceSignature("2026-08-30", "2026-10-03", "Liverpool", [source])) throw new Error("team filter must sign differently");
if (base === H.sourceSignature("2026-08-30", "2026-10-03", "", [{{...source, cached: {{fetchedAt: 2000}}}}])) throw new Error("refresh must sign differently");
if (base === H.sourceSignature("2026-08-30", "2026-10-03", "", [{{...source, events: [1, 2]}}])) throw new Error("event count must sign differently");
if (base === H.sourceSignature("2026-08-30", "2026-10-03", "", [])) throw new Error("missing league must sign differently");
if (H.sourceSignature("", "", "", []) !== H.sourceSignature("", "", "", [])) throw new Error("empty inputs must be stable");
"""
        run_node(script)


if __name__ == "__main__":
    unittest.main()