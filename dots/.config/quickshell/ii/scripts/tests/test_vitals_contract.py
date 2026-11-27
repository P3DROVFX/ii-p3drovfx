#!/usr/bin/env python3
"""Contract tests for ii Vitals (scripts/iiLink/PROTOCOL.md, "Vitals").

The phone and the shell meet at the `vitals` messages; the UI meets the store through
VitalsService. These pin the seams that break silently: a message the link never routes, a
Day shape the store would keep half of, a hash that rewrites every file, a retention that
keeps the wrong days, a night or a zone computed differently from the contract, a backfill
that stops after one page, and files readable by other users. All data here is synthetic.
"""

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOGIC = ROOT / "services/vitals/VitalsLogic.js"
STORE = ROOT / "scripts/vitals/vitals_store.py"
NODE = shutil.which("node")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def js(expression: str, **data):
    """Evaluates `expression` with VitalsLogic's functions and `data` in scope."""
    script = (
        "const vm = require('vm'); const fs = require('fs'); const ctx = {}; vm.createContext(ctx);"
        f"vm.runInContext(fs.readFileSync({json.dumps(str(LOGIC))}, 'utf8').replace(/^\\.pragma library\\s*$/m, ''), ctx);"
        # Through JSON.parse, as the link delivers it: a "__proto__" key stays a plain key.
        f"Object.assign(ctx, JSON.parse({json.dumps(json.dumps(data))}));"
        f"process.stdout.write(JSON.stringify(vm.runInContext({json.dumps(expression)}, ctx)));"
    )
    out = subprocess.run([NODE, "-e", script], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


H1, H2 = "0123456789abcdef", "fedcba9876543210"
EX_A, EX_B = "a1a1a1a1a1a1a1a1", "b2b2b2b2b2b2b2b2"
MIDNIGHT = 1795734000000  # 2026-11-27 00:00 at +01:00


def day(date="2026-11-27", hash_=H1, **kinds):
    d = {"date": date, "tz": "+01:00", "hash": hash_}
    d.update(kinds)
    return d


FULL_DAY = day(
    totals={"steps": {"day": 8412, "hourly": [0] * 7 + [700] * 12 + [12] + [0] * 4}, "distanceM": {"day": 6100}},
    samples={"heartRate": {"min": 47, "max": 141, "avg": 72.4, "count": 3, "last": [MIDNIGHT + 785 * 60000, 64],
                           "binMin": 1, "bins": [[0, 52], [600, 141], [785, 64]]}},
    sessions={
        "sleep": [
            {"start": MIDNIGHT - 46 * 60000, "end": MIDNIGHT + 406 * 60000, "score": 78,
             "stages": [[0, 20, "light"], [20, 40, "deep"], [60, 392, "asleep"]]},
            {"start": MIDNIGHT + 840 * 60000, "end": MIDNIGHT + 860 * 60000, "score": 50, "stages": []},
        ],
        "exercise": [
            {"id": EX_A, "type": "walking", "start": MIDNIGHT + 600 * 60000, "end": MIDNIGHT + 614 * 60000, "route": True},
            {"id": EX_B, "type": "strength_training", "start": MIDNIGHT + 700 * 60000, "end": MIDNIGHT + 747 * 60000, "route": False},
        ],
        "mindfulness": [{"start": MIDNIGHT + 1260 * 60000, "end": MIDNIGHT + 1270 * 60000}],
    },
    measurements={"body": [{"time": MIDNIGHT + 400 * 60000, "weightKg": 74.0},
                           {"time": MIDNIGHT + 460 * 60000, "weightKg": 73.6, "bodyFatPct": 17.1}]},
    scores={"energy": 76},
    source={"steps": "samsung", "sleep": "samsung", "heartRate": "samsung"},
)


@unittest.skipIf(NODE is None, "node is not installed")
class SummaryTests(unittest.TestCase):
    def test_every_kind_lands_in_its_summary_field(self):
        s = js("summarize(d)", d=FULL_DAY)
        self.assertEqual(s["hash"], H1)
        self.assertEqual(s["t"], {"steps": 8412, "distanceM": 6100})
        self.assertEqual(s["s"], {"heartRate": [47, 72.4, 141]})
        self.assertEqual(s["last"], {"heartRate": [MIDNIGHT + 785 * 60000, 64]})
        self.assertEqual(s["n"], {"sleep": 2, "exercise": 2, "mindfulness": 1})
        self.assertEqual(s["exMin"], 61)
        self.assertEqual(s["rt"], [EX_A])
        self.assertEqual(s["m"], {"body": {"time": MIDNIGHT + 460 * 60000, "weightKg": 73.6, "bodyFatPct": 17.1}})
        self.assertEqual(s["sc"], {"energy": 76})

    def test_an_empty_day_has_every_field_but_sleep_and_routes(self):
        s = js("summarize(d)", d=day())
        self.assertEqual(s, {"hash": H1, "t": {}, "s": {}, "last": {}, "n": {}, "exMin": 0, "m": {}, "sc": {}})

    def test_present_and_series_read_the_index(self):
        r = js("(() => { const i = applyDays({}, [a, b]).index; const ds = sortedDates(i);"
               " return {p: present(i), steps: series(i, ds, 'steps', '', ''), sleep: series(i, ds, 'sleepMin', '2026-11-27', ''),"
               " w: series(i, ds, 'body.weightKg', '', ''), hr: latest(i, ds, 'heartRate'), steps2: latest(i, ds, 'steps')}; })()",
               a=day("2026-11-26", H2, totals={"steps": {"day": 5000}}), b=FULL_DAY)
        self.assertEqual(sorted(r["p"]), ["body", "distanceM", "energy", "exercise", "heartRate", "mindfulness", "sleep", "steps"])
        self.assertEqual(r["steps"], [{"date": "2026-11-26", "value": 5000}, {"date": "2026-11-27", "value": 8412}])
        self.assertEqual(r["sleep"], [{"date": "2026-11-27", "value": 452}])
        self.assertEqual(r["w"], [{"date": "2026-11-27", "value": 73.6}])
        self.assertEqual(r["hr"], {"value": 64, "time": MIDNIGHT + 785 * 60000, "date": "2026-11-27"})
        self.assertEqual(r["steps2"], {"value": 8412, "time": None, "date": "2026-11-27"})


@unittest.skipIf(NODE is None, "node is not installed")
class StoreLogicTests(unittest.TestCase):
    def test_unchanged_hash_is_not_written_again(self):
        r = js("(() => { const first = applyDays({}, [d]); const again = applyDays(first.index, [d]);"
               " return {w1: first.write.length, w2: again.write.length, same: again.index === first.index, n: again.unchanged}; })()",
               d=FULL_DAY)
        self.assertEqual(r, {"w1": 1, "w2": 0, "same": True, "n": 1})

    def test_a_changed_hash_is_written(self):
        r = js("(() => { const i = applyDays({}, [a]).index; const r = applyDays(i, [b]);"
               " return [r.write.length, r.index['2026-11-27'].t.steps]; })()",
               a=day(totals={"steps": {"day": 1}}), b=day(hash_=H2, totals={"steps": {"day": 2}}))
        self.assertEqual(r, [1, 2])

    def test_malformed_days_are_skipped_whole_and_the_rest_kept(self):
        bad = [
            day("2026-02-30"),
            day(hash_="not-a-hash"),
            day(totals={"steps": {"day": "8412"}}),
            day(totals={"steps": {"day": 1, "hourly": [1, 2]}}),
            day(samples={"heartRate": {"min": 1, "max": 2}}),
            day(samples={"heartRate": {"min": 1, "max": 2, "avg": 1.5, "bins": [[1440, 60]]}}),
            day(sessions={"exercise": [{"id": "../../evil", "start": 1, "end": 2, "route": True}]}),
            day(sessions={"sleep": [{"start": 5, "end": 1}]}),
            day(sessions={"sleep": [{"start": 1, "end": 5, "stages": [[0, "x"]]}]}),
            day(measurements={"body": [{"weightKg": 70}]}),
            day(scores={"energy": None}),
            day(totals={"__proto__": {"day": 1}}),
            day(source={"steps": 3}),
            day(totals=[]),
            "2026-11-27",
        ]
        r = js("applyDays({}, bad.concat([good]))", bad=bad, good=day("2026-11-20", H2, totals={"steps": {"day": 1}}))
        self.assertEqual(len(r["skipped"]), len(bad))
        self.assertEqual([d["date"] for d in r["write"]], ["2026-11-20"])
        self.assertEqual(list(r["index"]), ["2026-11-20"])
        # Reasons name the key, never a value.
        for s in r["skipped"]:
            self.assertNotIn("8412", s["why"])

    def test_meta_needs_sources(self):
        self.assertEqual(js("metaError(m)", m={"goals": {}}), "meta.sources")
        self.assertEqual(js("metaError(m)", m={"sources": {"samsung": "on"}, "oldest": "2026-05-11"}), "")

    def test_route_points_are_checked(self):
        self.assertEqual(js("routePoints(p)", p=[[1, 45.1, 5.7, None], [2, 45.2, 5.8, 212.5]]), [[1, 45.1, 5.7, None], [2, 45.2, 5.8, 212.5]])
        self.assertIsNone(js("routePoints(p)", p=[[1, 95, 5.7, None]]))
        self.assertIsNone(js("routePoints(p)", p=None))

    def test_retention_cut_off(self):
        self.assertEqual(js("cutoff('2026-11-27', 90)"), "2026-08-30")
        self.assertEqual(js("cutoff('2026-11-27', 365)"), "2025-11-28")
        self.assertEqual(js("cutoff('2026-11-27', 0)"), "")
        index = {
            "2026-08-29": {"hash": H1, "rt": [EX_A]},
            "2026-08-30": {"hash": H1, "rt": [EX_B]},
            "2026-11-27": {"hash": H2},
        }
        r = js("prune(i, cutoff('2026-11-27', 90))", i=index)
        self.assertEqual(sorted(r["index"]), ["2026-08-30", "2026-11-27"])
        self.assertEqual(r["dates"], ["2026-08-29"])
        self.assertEqual(r["routes"], [EX_A])
        self.assertEqual(js("(() => { const r = prune(i, ''); return [r.index === i, r.dates.length]; })()", i=index), [True, 0])

    def test_missing_routes_are_the_kept_ones_the_pc_lacks(self):
        index = {"2026-11-26": {"rt": [EX_A]}, "2026-11-27": {"rt": [EX_B, "c3c3c3c3c3c3c3c3"]}}
        r = js("missingRoutes(i, sortedDates(i), have)", i=index, have={EX_B: 1, "c3c3c3c3c3c3c3c3": 0})
        self.assertEqual(r, [EX_A])


@unittest.skipIf(NODE is None, "node is not installed")
class SleepTests(unittest.TestCase):
    def test_sleep_for_takes_the_longest_session_ending_that_day(self):
        r = js("sleepFor(summarize(d), d)", d=FULL_DAY)
        self.assertEqual(r["start"], MIDNIGHT - 46 * 60000)
        self.assertEqual(r["min"], 452)
        self.assertEqual(r["score"], 78)
        self.assertEqual(r["stages"][1], [20, 40, "deep"])
        self.assertEqual(r["source"], "samsung")

    def test_without_the_day_file_it_answers_from_the_summary(self):
        r = js("sleepFor(summarize(d), null)", d=FULL_DAY)
        self.assertEqual((r["min"], r["score"], r["stages"]), (452, 78, None))
        self.assertIsNone(js("sleepFor(summarize(d), null)", d=day()))


@unittest.skipIf(NODE is None, "node is not installed")
class ProfileTests(unittest.TestCase):
    def test_age_counts_the_birthday(self):
        self.assertEqual(js("age('2003-04-10', '2026-11-27')"), 23)
        self.assertEqual(js("age('2003-11-28', '2026-11-27')"), 22)
        self.assertEqual(js("age('2003-11-27', '2026-11-27')"), 23)
        self.assertEqual(js("age('', '2026-11-27')"), -1)

    def test_hr_zones_follow_tanaka(self):
        # HRmax = 208 - 0.7 x 23 = 191.9 bpm.
        self.assertEqual(js("hrZones(23)"), [
            {"zone": 1, "from": 96, "to": 115},
            {"zone": 2, "from": 115, "to": 134},
            {"zone": 3, "from": 134, "to": 154},
            {"zone": 4, "from": 154, "to": 173},
            {"zone": 5, "from": 173, "to": 192},
        ])
        self.assertEqual(js("hrZones(-1)"), [])


@unittest.skipIf(NODE is None, "node is not installed")
class SyncTests(unittest.TestCase):
    def test_connect_asks_from_a_week_before_the_newest_day(self):
        self.assertEqual(js("sinceOnConnect(['2026-11-01', '2026-11-27'], 'auto', 'auto')"), "2026-11-20")
        self.assertEqual(js("sinceOnConnect(['2026-11-27'], '', 'auto')"), "2026-11-20")
        self.assertEqual(js("sinceOnConnect([], 'auto', 'auto')"), "")

    def test_steps_source_changed_while_away_asks_for_everything(self):
        self.assertEqual(js("sinceOnConnect(['2026-11-27'], 'auto', 'phone')"), "")

    def test_paging_continues_from_next_until_more_is_false(self):
        self.assertEqual(js("nextGet(m, 'phone')", m={"t": "vitals", "days": [], "more": True, "next": "2026-06-10"}),
                         {"t": "get", "what": "vitals", "since": "2026-06-10", "stepsFrom": "phone"})
        self.assertIsNone(js("nextGet(m, 'auto')", m={"t": "vitals", "days": [], "more": False}))
        self.assertIsNone(js("nextGet(m, 'auto')", m={"t": "vitals", "days": [], "more": True, "next": "soon"}))
        self.assertIsNone(js("nextGet(m, 'auto')", m={"t": "vitals", "days": []}))

    def test_progress_runs_from_the_answers_start_to_the_newest_day(self):
        self.assertEqual(js("progress('2026-05-11', '2026-05-11', '2026-11-27')"), 0)
        self.assertAlmostEqual(js("progress('2026-05-11', '2026-08-19', '2026-11-27')"), 0.5, places=2)
        self.assertEqual(js("progress('2026-05-11', '2026-11-27', '2026-11-27')"), 1)
        self.assertEqual(js("progress('', '2026-11-27', '2026-11-27')"), 0)


class StoreWriterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.dir = os.path.join(self.tmp, "vitals")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_store(self, **req):
        req.setdefault("dir", self.dir)
        return subprocess.run([sys.executable, str(STORE)], input=json.dumps(req) + "\n",
                              capture_output=True, text=True)

    def test_files_are_private_and_complete(self):
        r = self.run_store(write=[["days/2026-11-27.json", '{"date":"2026-11-27"}'], ["index.json", "{}"],
                                  ["routes/" + EX_A + ".json", "{}"]])
        self.assertEqual(r.returncode, 0, r.stderr)
        for dirpath, dirs, files in os.walk(self.dir):
            self.assertEqual(stat.S_IMODE(os.stat(dirpath).st_mode), 0o700, dirpath)
            for f in files:
                self.assertFalse(f.endswith(".tmp"), f)
                self.assertEqual(stat.S_IMODE(os.stat(os.path.join(dirpath, f)).st_mode), 0o600, f)
        self.assertEqual(Path(self.dir, "days/2026-11-27.json").read_text(), '{"date":"2026-11-27"}')

    def test_paths_outside_the_layout_are_refused(self):
        for rel in ("../escape.json", "days/x.json", "routes/../../x.json", "notes.txt"):
            r = self.run_store(write=[[rel, "{}"]])
            self.assertEqual(r.returncode, 1, rel)
            self.assertIn("refusing path", r.stderr)
        self.assertEqual(self.run_store(dir="/tmp/not-the-store").returncode, 1)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "escape.json")))

    def test_prune_and_wipe(self):
        days = [["days/%s.json" % d, "{}"] for d in ("2026-08-29", "2026-08-30", "2026-11-27")]
        self.assertEqual(self.run_store(write=days + [["routes/" + EX_A + ".json", "{}"]]).returncode, 0)
        r = self.run_store(pruneBefore="2026-08-30", delete=["routes/" + EX_A + ".json"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(os.listdir(os.path.join(self.dir, "days"))), ["2026-08-30.json", "2026-11-27.json"])
        self.assertEqual(os.listdir(os.path.join(self.dir, "routes")), [])
        self.assertEqual(self.run_store(wipe=True).returncode, 0)
        self.assertFalse(os.path.exists(self.dir))


SERVICE = read("services/VitalsService.qml")
TYPES = read("services/VitalsTypes.qml")
@unittest.skipIf(NODE is None, "node is not installed")
class AssistantDigestTests(unittest.TestCase):
    """What the vitals tools hand the provider: aggregates, never the raw records."""

    def test_profile_gives_age_not_birth_date(self):
        r = js("profileDigest({profile: {birthDate: '2003-04-10', sex: 'male', heightCm: 178}}, '2026-11-27')")
        self.assertEqual(r, {"age": 23, "sex": "male", "heightCm": 178})

    def test_a_day_has_hours_and_stages_but_no_bins_ids_or_routes(self):
        r = js("dayDigest('2026-11-27', summarize(d), d)", d=FULL_DAY)
        text = json.dumps(r)
        for leak in ('"bins"', '"id"', '"route"', EX_A, '"last"'):
            self.assertNotIn(leak, text, leak)
        self.assertEqual(len(r["heartRateByHour"]), 24)
        self.assertEqual(r["heartRateByHour"][10], 141)
        self.assertEqual(r["sleep"]["stageMinutes"], {"light": 20, "deep": 40, "asleep": 392})
        self.assertEqual([w["type"] for w in r["workouts"]], ["walking", "strength_training"])
        self.assertEqual(r["sessions"], {"mindfulness": {"count": 1, "minutes": 10}})

    def test_a_range_aggregates_per_key(self):
        other = day("2026-11-26", H2, totals={"steps": {"day": 2000}}, scores={"energy": 60})
        r = js("(() => { const ix = applyDays({}, days).index; return rangeDigest(ix, sortedDates(ix), '2026-11-26', '2026-11-27'); })()",
               days=[other, FULL_DAY])
        self.assertEqual(r["totals"]["steps"], {"total": 10412, "perDay": 5206, "days": 2, "best": {"date": "2026-11-27", "value": 8412}})
        self.assertEqual(r["scores"]["energy"]["avg"], 68)
        self.assertEqual(r["sleep"]["nights"], 1)

    def test_a_long_trend_folds_into_weeks(self):
        days = [day(f"2026-{m:02d}-{d:02d}", f"{i:016x}", totals={"steps": {"day": 1000 * (i % 7)}})
                for i, (m, d) in enumerate([(9, x) for x in range(1, 31)] + [(10, x) for x in range(1, 32)] + [(11, x) for x in range(1, 11)])]
        r = js("(() => { const ix = applyDays({}, days).index; return trendDigest(ix, sortedDates(ix), 'steps', '', ''); })()", days=days)
        self.assertEqual(r["days"], 71)
        self.assertNotIn("points", r)
        self.assertEqual(len(r["weekly"]), 11)
        self.assertEqual(r["weekly"][0], ["2026-09-01", 3000])


LINK = read("services/IiLinkService.qml")
CONFIG = read("modules/common/Config.qml")
PROTOCOL = read("scripts/iiLink/PROTOCOL.md")


class WiringTests(unittest.TestCase):
    def test_the_link_routes_both_messages_from_the_vitals_phone(self):
        self.assertRegex(LINK, r'case "vitals":\s*case "vitalsRoute":\s*if \(dev === root\.vitalsDev\)\s*VitalsService\.handleMessage\(m\);')
        self.assertIn('.concat(root.vitalsEnabled ? ["vitals"] : [])', LINK)
        self.assertIn("readonly property bool vitalsEnabled: root.opts?.vitals?.enable ?? false", LINK)
        self.assertIn('includes("vitals")', LINK)
        self.assertIn("VitalsService.connected()", LINK)

    def test_config_keys_and_defaults(self):
        self.assertRegex(CONFIG, r"property JsonObject vitals: JsonObject \{\s*property bool enable: false\s*\}")
        self.assertIn('property string stepsFrom: "auto"', CONFIG)
        self.assertIn("property int retentionDays: 0", CONFIG)
        self.assertRegex(CONFIG, r"property JsonObject bedtime: JsonObject \{\s*// [^\n]*\n\s*property bool enable: true")

    def test_service_api(self):
        for member in (
            "readonly property bool enabled", "readonly property bool linked", "readonly property string state",
            "readonly property var meta", "readonly property var index", "readonly property var dates",
            "readonly property var present", "readonly property real lastSync", "readonly property bool syncing",
            "readonly property real progress", "readonly property int dataVersion",
            "function syncNow(", "function day(", "signal dayLoaded(string date)", "function summary(",
            "function series(", "function latest(", "function sleepFor(", "function route(",
            "signal routeLoaded(string id)", "function age(", "function hrZones(", "function setStepsFrom(",
            "function setRetention(", "function deleteLocalCopy(",
        ):
            self.assertIn(member, SERVICE, member)
        for state in ("off", "notPaired", "offline", "noFeature", "syncing", "ready", "empty"):
            self.assertIn(f'return "{state}";', SERVICE, state)

    def test_registry_knows_every_documented_key(self):
        table = PROTOCOL.split("## Vitals (health data)")[1].split("- `meta`")[0]
        keys = {"skinTempDeltaC"}  # named inside a note in the table
        for row in re.findall(r"^  \| `(?:totals|samples|sessions|measurements|scores)` \| (.+) \|$", table, re.M):
            keys.update(re.findall(r"`([A-Za-z0-9]+)`", re.sub(r"\([^)]*\)", "", row)))
        self.assertGreater(len(keys), 40)
        for key in keys:
            self.assertRegex(TYPES, rf"\n        {key}: \{{ label: Translation\.tr\(", key)

    def test_protocol_documents_the_messages(self):
        section = PROTOCOL.split("## Vitals (health data)")[1].split("\n## ")[0]
        for text in ('"what":"vitals"', '"what":"vitalsRoute"', '{"t":"vitalsRoute"', '"more":bool', '"error":"disabled"',
                     "vitals_store.py", "index.json", "retentionDays"):
            self.assertIn(text, section, text)


REGISTRY = read("services/ai/AiToolRegistry.qml")
AI = read("services/Ai.qml")
VITALS_AI = read("services/ai/integrations/AiVitalsIntegration.qml")
SCHEMA = read("services/modes/ModeSchema.js")
BEDTIME = read("services/BedtimeService.qml")
VITALS_TOOLS = ("vitals_summary", "vitals_day", "vitals_trend")


class IntegrationTests(unittest.TestCase):
    def test_tools_exist_only_while_the_assistant_switch_is_on(self):
        self.assertIn("].concat(root.vitalsToolsOn ? root.vitalsDefinitions : [])", REGISTRY)
        self.assertRegex(REGISTRY, r"vitalsToolsOn: \(Config\.options\?\.iiTools\?\.vitals\?\.enable \?\? false\)\s*&& \(Config\.options\?\.vitals\?\.assistant\?\.enable \?\? false\)")
        self.assertRegex(CONFIG, r"property JsonObject assistant: JsonObject \{\s*// [^\n]*\n\s*property bool enable: false")

    def test_tools_are_read_only_and_handled(self):
        block = REGISTRY.split("readonly property var vitalsDefinitions: [")[1].split("\n    ]\n")[0]
        for tool in VITALS_TOOLS:
            self.assertIn(f'id: "{tool}"', block)
            self.assertIn(f'"{tool}": call => root.vitalsIntegration.', AI)
        self.assertEqual(block.count('kind: "localRead"'), len(VITALS_TOOLS))
        self.assertEqual(block.count('network: "never"'), len(VITALS_TOOLS))

    def test_tools_answer_through_the_digests(self):
        for fn in ("Logic.profileDigest(", "Logic.rangeDigest(", "Logic.dayDigest(", "Logic.trendDigest("):
            self.assertIn(fn, VITALS_AI)
        self.assertNotIn("birthDate", VITALS_AI)
        self.assertNotIn("VitalsService.route(", VITALS_AI)

    def test_modes_conditions_are_wired(self):
        for type_, file in (("vitalsSleep", "VitalsSleepCondition"), ("vitalsEnergy", "VitalsEnergyCondition"),
                            ("vitalsStepGoal", "VitalsStepGoalCondition")):
            self.assertIn(f'{type_}: "conditions/{file}.qml"', SCHEMA)
            self.assertRegex(SCHEMA, rf'{type_}: \{{ label: "[^"]+", icon: "[a-z_]+", editor: "vitals"')
            self.assertTrue((ROOT / f"services/modes/conditions/{file}.qml").exists(), file)
        self.assertTrue((ROOT / "modules/ii/modes/forms/TriggerVitals.qml").exists())

    def test_bedtime_asks_the_watch_before_the_usage_estimate(self):
        history = BEDTIME.split("function history(count)")[1].split("function streak(")[0]
        self.assertLess(history.index("VitalsService.summary("), history.index("root.estimateFromUsage(key)"))
        self.assertIn("vitals?.bedtime?.enable", history)
        self.assertNotIn(".stages", history)
        self.assertNotIn("sleepFor(", history.split("not sleepFor()")[1])


if __name__ == "__main__":
    unittest.main()
