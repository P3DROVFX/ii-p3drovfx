"""Read-only, offline verification. Does not launch or contact Quickshell."""
from pathlib import Path
import hashlib
import json
import statistics

BASE = Path(__file__).resolve().parent


def main():
    manifest = json.loads((BASE / "manifest.json").read_text())
    summary = json.loads((BASE / "summary.json").read_text())
    expected_summary = []
    total_samples = 0
    total_rows = 0
    for case, metadata in sorted(manifest["cases"].items()):
        path = BASE / "data" / case / "measurements.json"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == metadata["sha256"], case
        data = json.loads(path.read_text())
        assert data["case"]["id"] == case
        assert len(data["samples"]) == metadata["samples"]
        assert data["stages"] == metadata["stages"]
        assert any(m["phase"] == "done" for m in data["markers"]), case
        pid = str(data["pid"])
        total_samples += len(data["samples"])
        for row in data["summary"]:
            phase = [s for s in data["samples"] if s["phase"] == row["phase"]]
            samples = [s for s in phase if s["elapsed"] - phase[0]["elapsed"] >= 5
                       and pid in s["processes"]]
            first, last = samples[0], samples[-1]
            dt = last["elapsed"] - first["elapsed"]
            assert len(samples) == row["samples"]
            def median(get):
                return statistics.median(get(s) for s in samples)
            def total_cpu(sample):
                return sum(p["cpuSeconds"] + p["waitedChildCpuSeconds"]
                           for p in sample["processes"].values())
            computed = {
                "seconds": round(dt, 2),
                "rssMiB": median(lambda s: s["processes"][pid]["memoryMiB"]["Rss"]),
                "pssMiB": median(lambda s: s["processes"][pid]["memoryMiB"]["Pss"]),
                "privateMiB": median(lambda s: s["processes"][pid]["memoryMiB"]["Private"]),
                "treePssMiB": median(lambda s: sum(p["memoryMiB"]["Pss"]
                                                  for p in s["processes"].values())),
                "cpuPercent": 100 * (last["processes"][pid]["cpuSeconds"]
                                     - first["processes"][pid]["cpuSeconds"]) / dt,
                "treeCpuPercent": 100 * (total_cpu(last) - total_cpu(first)) / dt,
            }
            if all(s["gpu"]["memoryStatus"] == 0 for s in samples):
                computed["vramMiB"] = median(lambda s: s["gpu"]["memoryMiB"].get(pid, 0))
            else:
                assert row["vramMiB"] is None
            for key, value in computed.items():
                assert abs(round(value, 3) - row[key]) < 1e-5, (case, row["phase"], key)
            expected_summary.append({"case": case, **row})
            total_rows += 1
    sort_key = lambda r: (r["case"], r["phase"])
    assert sorted(summary, key=sort_key) == sorted(expected_summary, key=sort_key)
    print(json.dumps({"cases": len(manifest["cases"]), "samples": total_samples,
                      "summaryRows": total_rows, "hashesVerified": True,
                      "ramCpuVramRecomputed": True, "runtimeStarted": False,
                      "scope": "Arithmetic/integrity, not causal validity"}, indent=2))


if __name__ == "__main__":
    main()
